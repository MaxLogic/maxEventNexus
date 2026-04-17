unit MaxEventNexus.Scheduler.Tests;

{$DEFINE max_DELPHI}

interface

uses
  // RTL
  System.Classes, System.Diagnostics, System.Generics.Collections, System.SyncObjs, System.SysUtils, System.Threading,
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
    procedure ZeroWindowCoalesceRequestsPositiveDelayAcrossShippedSchedulers;
    procedure RawThreadZeroWindowClearKeepsStaleFlushInert;
  end;
  {$M-}

  TRecordingScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fDelayedCallCount: Integer;
    fInner: IEventNexusScheduler;
    fLastDelayUs: Integer;
  public
    constructor Create(const aInner: IEventNexusScheduler);
    function DelayedCallCount: Integer;
    function LastDelayUs: Integer;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

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

  TGatedRawThreadScheduler = class(TTestableRawThreadScheduler)
  private
    fCompleted: TArray<TEvent>;
    fNextSlot: Integer;
    fRelease: TArray<TEvent>;
    fStarted: TArray<TEvent>;
  protected
    function CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread; override;
  public
    constructor Create(aSlotCount: Integer);
    destructor Destroy; override;
    procedure ReleaseAll;
    procedure ReleaseSlot(aSlot: Integer);
    function WaitUntilCompleted(aSlot: Integer; aTimeoutMs: Cardinal): Boolean;
    function WaitUntilStarted(aSlot: Integer; aTimeoutMs: Cardinal): Boolean;
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

constructor TRecordingScheduler.Create(const aInner: IEventNexusScheduler);
begin
  inherited Create;
  fInner := aInner;
  fLastDelayUs := -1;
end;

function TRecordingScheduler.DelayedCallCount: Integer;
begin
  Result := TInterlocked.CompareExchange(fDelayedCallCount, 0, 0);
end;

function TRecordingScheduler.LastDelayUs: Integer;
begin
  Result := TInterlocked.CompareExchange(fLastDelayUs, 0, 0);
end;

procedure TRecordingScheduler.RunAsync(const aProc: TmaxProc);
begin
  fInner.RunAsync(aProc);
end;

procedure TRecordingScheduler.RunOnMain(const aProc: TmaxProc);
begin
  fInner.RunOnMain(aProc);
end;

procedure TRecordingScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  TInterlocked.Increment(fDelayedCallCount);
  TInterlocked.Exchange(fLastDelayUs, aDelayUs);
  fInner.RunDelayed(aProc, aDelayUs);
end;

function TRecordingScheduler.IsMainThread: Boolean;
begin
  Result := fInner.IsMainThread;
end;

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

constructor TGatedRawThreadScheduler.Create(aSlotCount: Integer);
var
  i: Integer;
begin
  inherited Create;
  if aSlotCount < 1 then
    aSlotCount := 1;
  SetLength(fCompleted, aSlotCount);
  SetLength(fStarted, aSlotCount);
  SetLength(fRelease, aSlotCount);
  for i := 0 to Pred(aSlotCount) do
  begin
    fCompleted[i] := TEvent.Create(nil, True, False, '');
    fStarted[i] := TEvent.Create(nil, True, False, '');
    fRelease[i] := TEvent.Create(nil, True, False, '');
  end;
  fNextSlot := 0;
end;

destructor TGatedRawThreadScheduler.Destroy;
var
  i: Integer;
begin
  ReleaseAll;
  for i := 0 to High(fRelease) do
  begin
    fCompleted[i].Free;
    fRelease[i].Free;
    fStarted[i].Free;
  end;
  inherited Destroy;
end;

function TGatedRawThreadScheduler.CreateProcThread(const aProc: TmaxProc; aDelayMs: Integer): TThread;
var
  lSlot: Integer;
begin
  lSlot := TInterlocked.Increment(fNextSlot) - 1;
  if (lSlot < 0) or (lSlot >= Length(fStarted)) then
    raise Exception.CreateFmt('Unexpected gated raw-thread slot %d', [lSlot]);

  Result := inherited CreateProcThread(
    procedure
    begin
      fStarted[lSlot].SetEvent;
      fRelease[lSlot].WaitFor(5000);
      try
        if Assigned(aProc) then
          aProc();
      finally
        fCompleted[lSlot].SetEvent;
      end;
    end,
    aDelayMs);
end;

procedure TGatedRawThreadScheduler.ReleaseAll;
var
  i: Integer;
begin
  for i := 0 to High(fRelease) do
    fRelease[i].SetEvent;
end;

procedure TGatedRawThreadScheduler.ReleaseSlot(aSlot: Integer);
begin
  if (aSlot < 0) or (aSlot >= Length(fRelease)) then
    raise Exception.CreateFmt('Invalid gated raw-thread slot %d', [aSlot]);
  fRelease[aSlot].SetEvent;
end;

function TGatedRawThreadScheduler.WaitUntilCompleted(aSlot: Integer; aTimeoutMs: Cardinal): Boolean;
begin
  if (aSlot < 0) or (aSlot >= Length(fCompleted)) then
    raise Exception.CreateFmt('Invalid gated raw-thread slot %d', [aSlot]);
  Result := fCompleted[aSlot].WaitFor(aTimeoutMs) = wrSignaled;
end;

function TGatedRawThreadScheduler.WaitUntilStarted(aSlot: Integer; aTimeoutMs: Cardinal): Boolean;
begin
  if (aSlot < 0) or (aSlot >= Length(fStarted)) then
    raise Exception.CreateFmt('Invalid gated raw-thread slot %d', [aSlot]);
  Result := fStarted[aSlot].WaitFor(aTimeoutMs) = wrSignaled;
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

procedure TTestSchedulerContracts.ZeroWindowCoalesceRequestsPositiveDelayAcrossShippedSchedulers;
  procedure AssertZeroWindowPositiveDelay(const aName: string; const aInner: IEventNexusScheduler);
  const
    cTopicName = 'scheduler.zero-window';
  var
    lBus: ImaxBus;
    lCount: Integer;
    lDone: TEvent;
    lLock: TCriticalSection;
    lProbe: TRecordingScheduler;
    lScheduler: IEventNexusScheduler;
    lValue: Integer;
  begin
    lDone := TEvent.Create(nil, True, False, '');
    lLock := TCriticalSection.Create;
    lProbe := TRecordingScheduler.Create(aInner);
    lScheduler := lProbe;
    lBus := TmaxBus.Create(lScheduler);
    lCount := 0;
    lValue := 0;
    try
      maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cTopicName,
        function(const aValue: Integer): TmaxString
        begin
          Result := 'same';
        end,
        0);
      maxBusObj(lBus).SubscribeNamedOf<Integer>(cTopicName,
        procedure(const aValue: Integer)
        begin
          lLock.Enter;
          try
            Inc(lCount);
            lValue := aValue;
            lDone.SetEvent;
          finally
            lLock.Leave;
          end;
        end);

      maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 1);
      maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 2);

      CheckEquals(1, lProbe.DelayedCallCount, aName + ' should schedule one zero-window delayed flush');
      Check(lProbe.LastDelayUs > 0, aName + ' should request a positive zero-window delay');
      CheckEquals(Integer(wrSignaled), Integer(lDone.WaitFor(2000)), aName + ' zero-window coalesced delivery timed out');
      lLock.Enter;
      try
        CheckEquals(1, lCount, aName + ' should deliver one coalesced value');
        CheckEquals(2, lValue, aName + ' should deliver the latest coalesced value');
      finally
        lLock.Leave;
      end;
    finally
      maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cTopicName, nil);
      lBus.Clear;
      lDone.Free;
      lLock.Free;
    end;
  end;
begin
  AssertZeroWindowPositiveDelay('maxAsync', TTestableMaxAsyncScheduler.Create);
  AssertZeroWindowPositiveDelay('TTask', TTestableTTaskScheduler.Create);
  AssertZeroWindowPositiveDelay('raw-thread', TTestableRawThreadScheduler.Create);
end;

procedure TTestSchedulerContracts.RawThreadZeroWindowClearKeepsStaleFlushInert;
const
  cTopicName = 'scheduler.zero-window.clear.rawthread';
var
  lBus: ImaxBus;
  lDelivered: TEvent;
  lGate: TGatedRawThreadScheduler;
  lLock: TCriticalSection;
  lProbe: TRecordingScheduler;
  lScheduler: IEventNexusScheduler;
  lValues: TList<Integer>;
begin
  TTestableRawThreadScheduler.ResetCreatedThreadCount;
  lGate := TGatedRawThreadScheduler.Create(2);
  lProbe := TRecordingScheduler.Create(lGate);
  lScheduler := lProbe;
  lBus := TmaxBus.Create(lScheduler);
  lDelivered := TEvent.Create(nil, True, False, '');
  lLock := TCriticalSection.Create;
  lValues := TList<Integer>.Create;
  try
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cTopicName,
      function(const aValue: Integer): TmaxString
      begin
        Result := 'same';
      end,
      0);
    maxBusObj(lBus).SubscribeNamedOf<Integer>(cTopicName,
      procedure(const aValue: Integer)
      begin
        lLock.Enter;
        try
          lValues.Add(aValue);
          lDelivered.SetEvent;
        finally
          lLock.Leave;
        end;
      end);

    maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 1);
    maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 2);

    CheckEquals(1, lProbe.DelayedCallCount, 'RawThread should schedule one zero-window flush for the first burst');
    Check(lProbe.LastDelayUs > 0, 'RawThread should request a positive delay for zero-window coalescing');
    Check(lGate.WaitUntilStarted(0, 2000), 'Stale raw-thread zero-window callback did not reach the gate');

    lBus.Clear;

    maxBusObj(lBus).SubscribeNamedOf<Integer>(cTopicName,
      procedure(const aValue: Integer)
      begin
        lLock.Enter;
        try
          lValues.Add(aValue);
          lDelivered.SetEvent;
        finally
          lLock.Leave;
        end;
      end);

    maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 3);
    maxBusObj(lBus).PostNamedOf<Integer>(cTopicName, 4);

    CheckEquals(2, lProbe.DelayedCallCount, 'RawThread should schedule a fresh zero-window flush after Clear');
    Check(lGate.WaitUntilStarted(1, 2000), 'Fresh raw-thread zero-window callback did not reach the gate');

    lGate.ReleaseSlot(0);
    Check(lGate.WaitUntilCompleted(0, 2000), 'Stale raw-thread zero-window callback did not finish after release');
    lLock.Enter;
    try
      CheckEquals(0, lValues.Count, 'Releasing the stale raw-thread callback after Clear must stay inert');
    finally
      lLock.Leave;
    end;

    lDelivered.ResetEvent;
    lGate.ReleaseSlot(1);
    Check(lGate.WaitUntilCompleted(1, 2000), 'Fresh raw-thread zero-window callback did not finish after release');
    Check(lDelivered.WaitFor(2000) = wrSignaled, 'Fresh raw-thread callback did not deliver the coalesced value');

    lLock.Enter;
    try
      CheckEquals(1, lValues.Count, 'Fresh raw-thread callback should deliver exactly one coalesced value');
      CheckEquals(4, lValues[0], 'Fresh raw-thread callback should deliver only the new final value');
    finally
      lLock.Leave;
    end;
  finally
    lGate.ReleaseAll;
    maxBusObj(lBus).EnableCoalesceNamedOf<Integer>(cTopicName, nil);
    lBus.Clear;
    lValues.Free;
    lLock.Free;
    lDelivered.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSchedulerContracts);

end.
