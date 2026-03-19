program MaxEventNexusTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  SysUtils,
  System.IOUtils,
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
  [TestFixture]
  TEventNexusLegacyFixture = class
  public
    [Test]
    procedure RunLegacySuite;
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
