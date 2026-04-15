program MaxEventNexusTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.SyncObjs,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  DUnitX.TestRunner,
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas',
  maxLogic.EventNexus.Core in '..\maxLogic.EventNexus.Core.pas',
  maxLogic.EventNexus.Threading.Adapter in '..\maxLogic.EventNexus.Threading.Adapter.pas',
  maxLogic.EventNexus.Threading.MaxAsync in '..\maxLogic.EventNexus.Threading.MaxAsync.pas',
  maxLogic.EventNexus.Threading.RawThread in '..\maxLogic.EventNexus.Threading.RawThread.pas',
  maxLogic.EventNexus.Threading.TTask in '..\maxLogic.EventNexus.Threading.TTask.pas',
  MaxEventNexus.Main.Tests in 'src\MaxEventNexus.Main.Tests.pas',
  MaxEventNexus.Scheduler.Tests in 'src\MaxEventNexus.Scheduler.Tests.pas',
  MaxEventNexus.Testing in 'src\MaxEventNexus.Testing.pas';

type
  TDefaultAsyncProbeThread = class(TThread)
  private
    fScheduler: IEventNexusScheduler;
    fStartEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(const aStartEvent: TEvent);
    property Scheduler: IEventNexusScheduler read fScheduler;
  end;

  [TestFixture]
  TEventNexusLegacyFixture = class
  public
    [Test]
    procedure RunLegacySuite;
  end;

constructor TDefaultAsyncProbeThread.Create(const aStartEvent: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fStartEvent := aStartEvent;
end;

procedure TDefaultAsyncProbeThread.Execute;
begin
  if (fStartEvent <> nil) and (fStartEvent.WaitFor(5000) = wrSignaled) then
    fScheduler := maxGetAsyncScheduler;
end;

function HasArg(const aValue: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if SameText(ParamStr(i), aValue) then
      Exit(True);
end;

function RunDefaultAsyncRaceProbe: Integer;
const
  cThreadCount = 48;
var
  lSchedulers: TDictionary<NativeUInt, Byte>;
  lStartEvent: TEvent;
  lThreads: array of TDefaultAsyncProbeThread;
  lKey: NativeUInt;
  i: Integer;
begin
  lStartEvent := TEvent.Create(nil, True, False, '');
  lSchedulers := TDictionary<NativeUInt, Byte>.Create;
  try
    SetLength(lThreads, cThreadCount);
    for i := 0 to High(lThreads) do
    begin
      lThreads[i] := TDefaultAsyncProbeThread.Create(lStartEvent);
      lThreads[i].Start;
    end;
    lStartEvent.SetEvent;
    for i := 0 to High(lThreads) do
    begin
      lThreads[i].WaitFor;
      if lThreads[i].Scheduler = nil then
        Exit(2);
      lKey := NativeUInt(Pointer(lThreads[i].Scheduler));
      if not lSchedulers.ContainsKey(lKey) then
        lSchedulers.Add(lKey, 0);
    end;
    if lSchedulers.Count = 1 then
      Result := 0
    else
      Result := 1;
  finally
    for i := 0 to High(lThreads) do
      lThreads[i].Free;
    lSchedulers.Free;
    lStartEvent.Free;
  end;
end;

function RunStressSuite: Integer;
const
  cAsyncPosts = 2000;
  cDelayedPosts = 40;
var
  lAsyncDone: TEvent;
  lAsyncHits: Integer;
  lBus: ImaxBus;
  lCoalesceDone: TEvent;
  lCoalesceHits: Integer;
  lCoalesceLock: TObject;
  lDeliveredByKey: TDictionary<string, Integer>;
  lDelayedDone: TEvent;
  lDelayedHits: Integer;

  procedure RunAsyncPhase;
  var
    lIdx: Integer;
    lLock: TObject;
    lValue: Integer;
  begin
    lAsyncDone := TEvent.Create(nil, True, False, '');
    lLock := TObject.Create;
    lAsyncHits := 0;
    try
      lBus.Clear;
      maxBusObj(lBus).Subscribe<Integer>(
        procedure(const aEvent: Integer)
        begin
          TMonitor.Enter(lLock);
          try
            Inc(lAsyncHits);
            lValue := lAsyncHits;
          finally
            TMonitor.Exit(lLock);
          end;
          if lValue = cAsyncPosts then
            lAsyncDone.SetEvent;
        end,
        TmaxDelivery.Async);
      for lIdx := 1 to cAsyncPosts do
        maxBusObj(lBus).Post<Integer>(lIdx);
      if lAsyncDone.WaitFor(10000) <> wrSignaled then
        raise Exception.Create('Stress async phase timed out');
      if lAsyncHits <> cAsyncPosts then
        raise Exception.CreateFmt('Stress async phase expected %d hits but got %d', [cAsyncPosts, lAsyncHits]);
    finally
      lLock.Free;
      lAsyncDone.Free;
    end;
  end;

  procedure RunDelayedPhase;
  var
    lIdx: Integer;
    lLock: TObject;
    lValue: Integer;
  begin
    lDelayedDone := TEvent.Create(nil, True, False, '');
    lLock := TObject.Create;
    lDelayedHits := 0;
    try
      lBus.Clear;
      lBus.SubscribeNamed('stress.delayed',
        procedure
        begin
          TMonitor.Enter(lLock);
          try
            Inc(lDelayedHits);
            lValue := lDelayedHits;
          finally
            TMonitor.Exit(lLock);
          end;
          if lValue = cDelayedPosts then
            lDelayedDone.SetEvent;
        end,
        TmaxDelivery.Posting);
      for lIdx := 1 to cDelayedPosts do
        lBus.PostDelayedNamed('stress.delayed', 15);
      if lDelayedDone.WaitFor(10000) <> wrSignaled then
        raise Exception.Create('Stress delayed-post phase timed out');
      if lDelayedHits <> cDelayedPosts then
        raise Exception.CreateFmt('Stress delayed-post phase expected %d hits but got %d',
          [cDelayedPosts, lDelayedHits]);
    finally
      lLock.Free;
      lDelayedDone.Free;
    end;
  end;

  procedure RunCoalescePhase;
  var
    lEvent: TKeyed;
    lIdx: Integer;
  begin
    lCoalesceDone := TEvent.Create(nil, True, False, '');
    lCoalesceHits := 0;
    lCoalesceLock := TObject.Create;
    lDeliveredByKey := TDictionary<string, Integer>.Create;
    try
      lBus.Clear;
      maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
        function(const aValue: TKeyed): TmaxString
        begin
          Result := aValue.Key;
        end,
        0);
      maxBusObj(lBus).Subscribe<TKeyed>(
        procedure(const aValue: TKeyed)
        begin
          TMonitor.Enter(lCoalesceLock);
          try
            lDeliveredByKey.AddOrSetValue(aValue.Key, aValue.Value);
            Inc(lCoalesceHits);
            if (lDeliveredByKey.Count = 2) and lDeliveredByKey.ContainsKey('A') and lDeliveredByKey.ContainsKey('B') and
              (lDeliveredByKey['A'] = 100) and (lDeliveredByKey['B'] = 200) then
              lCoalesceDone.SetEvent;
          finally
            TMonitor.Exit(lCoalesceLock);
          end;
        end,
        TmaxDelivery.Posting);
      for lIdx := 1 to 100 do
      begin
        lEvent.Key := 'A';
        lEvent.Value := lIdx;
        maxBusObj(lBus).Post<TKeyed>(lEvent);
      end;
      for lIdx := 1 to 200 do
      begin
        lEvent.Key := 'B';
        lEvent.Value := lIdx;
        maxBusObj(lBus).Post<TKeyed>(lEvent);
      end;
      if lCoalesceDone.WaitFor(5000) <> wrSignaled then
        raise Exception.Create('Stress coalesce phase timed out');
      if lCoalesceHits < 2 then
        raise Exception.CreateFmt('Stress coalesce phase expected at least 2 deliveries but got %d', [lCoalesceHits]);
    finally
      lDeliveredByKey.Free;
      lCoalesceLock.Free;
      lCoalesceDone.Free;
    end;
  end;
begin
  lBus := TmaxBus.Create(CreateMaxAsyncScheduler);
  try
    RunAsyncPhase;
    RunDelayedPhase;
    RunCoalescePhase;
    Writeln('STRESS PASS');
    Result := 0;
  finally
    lBus := nil;
  end;
end;

procedure TEventNexusLegacyFixture.RunLegacySuite;
begin
  RunPublishedTests('MaxEventNexus', [
    TTestAggregateException,
    TTestAsyncDelivery,
    TTestAsyncExceptions,
    TTestCoalesce,
    TTestFuzz,
    TTestGuidTopics,
    TTestHighWaterReset,
    TTestMailbox,
    TTestMainThreadPolicy,
    TTestAutoSubscribe,
    TTestMetrics,
    TTestMetricsConcurrent,
    TTestMetricsThrottling,
    TTestMetricsCallbackTotals,
    TTestNamedTopics,
    TTestQueuePolicy,
    TTestQueuePolicyPresets,
    TTestSchedulers,
    TTestSticky,
    TTestStress,
    TTestSubscribeOrdering,
    TTestSubscriptionTokens,
    TTestPostResult,
    TTestDispatchErrorDetails,
    TTestTracingHooks,
    TTestBulkDispatch,
    TTestWildcardNamed,
    TTestDelayedPosting,
    TTestSchedulerContracts,
    TTestUnsubscribeAll,
    TTestWeakTargets,
    TTestStrongTargets,
    TTestWeakTargetABA,
    TTestInterfaceGenerics
  ]);
end;

var
  lExitCode: Integer;
  lLogger: ITestLogger;
  lLogsDir: string;
  lResults: IRunResults;
  lRunner: ITestRunner;

begin
  if HasArg('--default-async-race-probe') then
    Halt(RunDefaultAsyncRaceProbe);
  if HasArg('--stress-suite') then
    Halt(RunStressSuite);

  lLogsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
  if TDirectory.Exists(lLogsDir) then
    TDirectory.Delete(lLogsDir, True);
  TDirectory.CreateDirectory(lLogsDir);

  TDUnitX.CheckCommandLine;
  TDUnitX.RegisterTestFixture(TEventNexusLegacyFixture);

  lRunner := TDUnitX.CreateRunner;
  lRunner.UseRTTI := True;
  lRunner.FailsOnNoAsserts := False;

  lLogger := TDUnitXConsoleLogger.Create(True);
  lRunner.AddLogger(lLogger);

  lResults := lRunner.Execute;
  if lResults.AllPassed then
    lExitCode := 0
  else
    lExitCode := 1;

  Halt(lExitCode);
end.
