unit MaxEventNexus.Scheduler.Tests;

{$DEFINE max_DELPHI}

interface

uses
  // RTL
  System.Classes, System.Diagnostics, System.SyncObjs, System.SysUtils, System.Threading,
  // Third-party
  DUnitX.TestFramework, MaxEventNexus.Testing,
  // Project
  maxLogic.EventNexus.Core, maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.MaxAsync, maxLogic.EventNexus.Threading.RawThread,
  maxLogic.EventNexus.Threading.TTask;

type
  {$M+}
  TTestSchedulerContracts = class(TmaxTestCase)
  published
    procedure MaxAsyncEnqueueFailureFallsBackOffThread;
    procedure MaxAsyncDelayedSubmissionFailureFallsBackOffThread;
    procedure RawThreadCreatesDedicatedThreadsForAsyncAndDelayedWork;
    procedure RawThreadRuntimeDelayConversionRoundsUpSubMillisecondWork;
    procedure RuntimeDelayContractAcrossSchedulers;
    procedure PositiveSubMillisecondDelaysRoundUpAcrossSchedulers;
  end;
  {$M-}

  TTestableMaxAsyncScheduler = class(TmaxAsyncScheduler)
  public
    class function DelayUsToDelayMsForTest(aDelayUs: Integer): Integer; static;
  end;

  TTestableTTaskScheduler = class(TmaxTTaskScheduler)
  public
    class function DelayUsToDelayMsForTest(aDelayUs: Integer): Integer; static;
  end;

  TTestableRawThreadScheduler = class(TmaxRawThreadScheduler)
  strict private
    class var fCreatedThreadCount: Integer;
    class var fLastDelayMs: Integer;
  protected
    function ResolveDelayMs(aDelayUs: Integer): Integer; override;
    function CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread; override;
  public
    class function DelayUsToDelayMsForTest(aDelayUs: Integer): Integer; static;
    class function CreatedThreadCount: Integer; static;
    class function LastDelayMs: Integer; static;
    class procedure ResetCreatedThreadCount; static;
  end;

  TFaultingMaxAsyncScheduler = class(TTestableMaxAsyncScheduler)
  private
    fFailEnqueue: Boolean;
    fFailSubmit: Boolean;
  protected
    procedure EnqueueWork(const aProc: TmaxProc); override;
    procedure SubmitDelayedWork(const aProc: TmaxProc; aDelayMs: Integer); override;
  public
    constructor Create(aFailEnqueue: Boolean; aFailSubmit: Boolean);
  end;

implementation

class function TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(aDelayUs: Integer): Integer;
begin
  Result := DelayUsToDelayMs(aDelayUs);
end;

class function TTestableTTaskScheduler.DelayUsToDelayMsForTest(aDelayUs: Integer): Integer;
begin
  Result := DelayUsToDelayMs(aDelayUs);
end;

class function TTestableRawThreadScheduler.DelayUsToDelayMsForTest(aDelayUs: Integer): Integer;
begin
  Result := DelayUsToDelayMs(aDelayUs);
end;

function TTestableRawThreadScheduler.CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread;
begin
  TInterlocked.Increment(fCreatedThreadCount);
  Result := inherited CreateProcThread(aProc, aDelayMs);
end;

function TTestableRawThreadScheduler.ResolveDelayMs(aDelayUs: Integer): Integer;
begin
  Result := inherited ResolveDelayMs(aDelayUs);
  TInterlocked.Exchange(fLastDelayMs, Result);
end;

class function TTestableRawThreadScheduler.CreatedThreadCount: Integer;
begin
  Result := TInterlocked.CompareExchange(fCreatedThreadCount, 0, 0);
end;

class function TTestableRawThreadScheduler.LastDelayMs: Integer;
begin
  Result := TInterlocked.CompareExchange(fLastDelayMs, 0, 0);
end;

class procedure TTestableRawThreadScheduler.ResetCreatedThreadCount;
begin
  TInterlocked.Exchange(fCreatedThreadCount, 0);
  TInterlocked.Exchange(fLastDelayMs, -1);
end;

constructor TFaultingMaxAsyncScheduler.Create(aFailEnqueue: Boolean; aFailSubmit: Boolean);
begin
  inherited Create;
  fFailEnqueue := aFailEnqueue;
  fFailSubmit := aFailSubmit;
end;

procedure TFaultingMaxAsyncScheduler.EnqueueWork(const aProc: TmaxProc);
begin
  if fFailEnqueue then
    raise Exception.Create('enqueue failed');
  inherited EnqueueWork(aProc);
end;

procedure TFaultingMaxAsyncScheduler.SubmitDelayedWork(const aProc: TmaxProc; aDelayMs: Integer);
begin
  if fFailSubmit then
    raise Exception.Create('submit failed');
  inherited SubmitDelayedWork(aProc, aDelayMs);
end;

procedure TTestSchedulerContracts.MaxAsyncEnqueueFailureFallsBackOffThread;
var
  lDone: TEvent;
  lMainId: TThreadID;
  lWorkerId: TThreadID;
  lScheduler: IEventNexusScheduler;
begin
  lDone := TEvent.Create(nil, True, False, '');
  try
    lMainId := TThread.CurrentThread.ThreadID;
    lWorkerId := lMainId;
    lScheduler := TFaultingMaxAsyncScheduler.Create(True, False);
    lScheduler.RunAsync(
      procedure
      begin
        lWorkerId := TThread.CurrentThread.ThreadID;
        lDone.SetEvent;
      end);
    Check(lDone.WaitFor(1000) = wrSignaled, 'maxAsync enqueue fallback timed out');
    Check(lWorkerId <> lMainId, 'maxAsync enqueue fallback should preserve async semantics');
  finally
    lDone.Free;
  end;
end;

procedure TTestSchedulerContracts.MaxAsyncDelayedSubmissionFailureFallsBackOffThread;
const
  cDelayUs = 80000;
var
  lDone: TEvent;
  lElapsedMs: UInt64;
  lMainId: TThreadID;
  lStopwatch: TStopwatch;
  lWorkerId: TThreadID;
  lScheduler: IEventNexusScheduler;
begin
  lDone := TEvent.Create(nil, True, False, '');
  try
    lMainId := TThread.CurrentThread.ThreadID;
    lWorkerId := lMainId;
    lScheduler := TFaultingMaxAsyncScheduler.Create(False, True);
    lStopwatch := TStopwatch.StartNew;
    lScheduler.RunDelayed(
      procedure
      begin
        lWorkerId := TThread.CurrentThread.ThreadID;
        lDone.SetEvent;
      end,
      cDelayUs);
    Check(lDone.WaitFor(20) = wrTimeout, 'maxAsync delayed fallback collapsed the delay boundary');
    Check(lDone.WaitFor(1000) = wrSignaled, 'maxAsync delayed fallback timed out');
    lElapsedMs := lStopwatch.ElapsedMilliseconds;
    Check(lElapsedMs >= 60, Format('maxAsync delayed fallback fired too quickly (%dms)', [lElapsedMs]));
    Check(lWorkerId <> lMainId, 'maxAsync delayed fallback should preserve async semantics');
  finally
    lDone.Free;
  end;
end;

procedure TTestSchedulerContracts.RawThreadCreatesDedicatedThreadsForAsyncAndDelayedWork;
var
  lAsyncDone: TEvent;
  lDelayedDone: TEvent;
  lScheduler: IEventNexusScheduler;
begin
  lAsyncDone := TEvent.Create(nil, True, False, '');
  lDelayedDone := TEvent.Create(nil, True, False, '');
  try
    TTestableRawThreadScheduler.ResetCreatedThreadCount;
    lScheduler := TTestableRawThreadScheduler.Create;
    lScheduler.RunAsync(
      procedure
      begin
        lAsyncDone.SetEvent;
      end);
    lScheduler.RunDelayed(
      procedure
      begin
        lDelayedDone.SetEvent;
      end,
      1000);
    Check(lAsyncDone.WaitFor(1000) = wrSignaled, 'RawThread async work timed out');
    Check(lDelayedDone.WaitFor(1000) = wrSignaled, 'RawThread delayed work timed out');
    CheckEquals(2, TTestableRawThreadScheduler.CreatedThreadCount,
      'RawThread should create a dedicated TThread for async and delayed work');
  finally
    lAsyncDone.Free;
    lDelayedDone.Free;
  end;
end;

procedure TTestSchedulerContracts.RawThreadRuntimeDelayConversionRoundsUpSubMillisecondWork;
var
  lDone: TEvent;
  lScheduler: IEventNexusScheduler;
begin
  lDone := TEvent.Create(nil, True, False, '');
  try
    TTestableRawThreadScheduler.ResetCreatedThreadCount;
    lScheduler := TTestableRawThreadScheduler.Create;
    lScheduler.RunDelayed(
      procedure
      begin
        lDone.SetEvent;
      end,
      1);
    Check(lDone.WaitFor(1000) = wrSignaled, 'RawThread delayed work timed out');
    CheckEquals(1, TTestableRawThreadScheduler.LastDelayMs,
      'RawThread runtime delay conversion should round positive sub-millisecond delays up to 1 ms');
  finally
    lDone.Free;
  end;
end;

procedure TTestSchedulerContracts.RuntimeDelayContractAcrossSchedulers;
  procedure AssertZeroDelayCompletes(const aName: string; const aScheduler: IEventNexusScheduler);
  var
    lDone: TEvent;
  begin
    lDone := TEvent.Create(nil, True, False, '');
    try
      aScheduler.RunDelayed(
        procedure
        begin
          lDone.SetEvent;
        end,
        0);
      Check(lDone.WaitFor(1000) = wrSignaled, aName + ' zero delay did not complete');
    finally
      lDone.Free;
    end;
  end;

  procedure AssertPositiveDelayStaysDeferred(const aName: string; const aScheduler: IEventNexusScheduler);
  var
    lDone: TEvent;
    lRanBeforeReturn: Boolean;
    lReturned: Boolean;
  begin
    lDone := TEvent.Create(nil, True, False, '');
    try
      lRanBeforeReturn := False;
      lReturned := False;
      aScheduler.RunDelayed(
        procedure
        begin
          if not lReturned then
            lRanBeforeReturn := True;
          lDone.SetEvent;
        end,
        1);
      lReturned := True;
      Check(not lRanBeforeReturn, aName + ' positive sub-millisecond delay executed inline');
      Check(lDone.WaitFor(1000) = wrSignaled, aName + ' positive sub-millisecond delay did not complete');
    finally
      lDone.Free;
    end;
  end;
begin
  AssertZeroDelayCompletes('maxAsync', TTestableMaxAsyncScheduler.Create);
  AssertZeroDelayCompletes('TTask', TTestableTTaskScheduler.Create);
  AssertZeroDelayCompletes('raw-thread', TTestableRawThreadScheduler.Create);
  AssertPositiveDelayStaysDeferred('maxAsync', TTestableMaxAsyncScheduler.Create);
  AssertPositiveDelayStaysDeferred('TTask', TTestableTTaskScheduler.Create);
  AssertPositiveDelayStaysDeferred('raw-thread', TTestableRawThreadScheduler.Create);
end;

procedure TTestSchedulerContracts.PositiveSubMillisecondDelaysRoundUpAcrossSchedulers;
  procedure AssertRoundedDelay(const aName: string; aActual: Integer);
  begin
    CheckEquals(1, aActual, aName + ' should round positive sub-millisecond delay up to 1 ms');
  end;
begin
  CheckEquals(0, TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(-1));
  CheckEquals(0, TTestableTTaskScheduler.DelayUsToDelayMsForTest(-1));
  CheckEquals(0, TTestableRawThreadScheduler.DelayUsToDelayMsForTest(-1));
  CheckEquals(0, TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(0));
  CheckEquals(0, TTestableTTaskScheduler.DelayUsToDelayMsForTest(0));
  CheckEquals(0, TTestableRawThreadScheduler.DelayUsToDelayMsForTest(0));
  AssertRoundedDelay('maxAsync', TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(1));
  AssertRoundedDelay('TTask', TTestableTTaskScheduler.DelayUsToDelayMsForTest(1));
  AssertRoundedDelay('raw-thread', TTestableRawThreadScheduler.DelayUsToDelayMsForTest(1));
  AssertRoundedDelay('maxAsync', TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(999));
  AssertRoundedDelay('TTask', TTestableTTaskScheduler.DelayUsToDelayMsForTest(999));
  AssertRoundedDelay('raw-thread', TTestableRawThreadScheduler.DelayUsToDelayMsForTest(999));
  CheckEquals(2, TTestableMaxAsyncScheduler.DelayUsToDelayMsForTest(1001));
  CheckEquals(2, TTestableTTaskScheduler.DelayUsToDelayMsForTest(1001));
  CheckEquals(2, TTestableRawThreadScheduler.DelayUsToDelayMsForTest(1001));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSchedulerContracts);

end.
