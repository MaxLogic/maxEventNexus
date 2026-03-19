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
