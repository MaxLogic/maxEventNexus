unit MaxEventNexus.Main.Tests;

{$DEFINE max_DELPHI}

interface

uses
  // RTL
  Classes, SysUtils, SyncObjs, TypInfo, System.Generics.Collections,
  // OS/API
  Winapi.Windows,
  // Third-party
  MaxEventNexus.Testing,
  // Project
  maxLogic.EventNexus.Threading.Adapter, maxLogic.EventNexus.Threading.RawThread,
  maxLogic.EventNexus.Core, maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.TTask, maxLogic.EventNexus;

type
  TKeyed = record
    Key: string;
    Value: integer;
  end;

  TABAEvent = record
    Value: integer;
  end;

  TMetricEvent = record
    Value: integer;
  end;

  TPresetEvent = record
    Value: integer;
  end;

  TPostResultNoTopicEvent = record
    Value: integer;
  end;

type
  TTestAggregateException = class(TmaxTestCase)
  published
    procedure AggregatesMultiple;
    procedure QueueContinuesAfterAggregate;
  end;

  TTestAsyncDelivery = class(TmaxTestCase)
  published
    procedure AsyncAndBackgroundRunOffPostingThread;
  end;

  TTestAsyncExceptions = class(TmaxTestCase)
  published
    procedure InlineMainOnMainThreadRaisesAndForwardsHookForTyped;
    procedure DegradeToPostingRaisesAndForwardsHookForNamed;
    procedure InlineBackgroundOnWorkerThreadRaisesAndForwardsHookForGuid;
    procedure InlineSchedulerPostNamedAsyncForwardsError;
    procedure InlineSchedulerTryPostNamedAsyncForwardsError;
  end;

  TTestCoalesce = class(TmaxTestCase)
  private
    class function MakeKeyed(const aKey: string; aValue: integer): TKeyed; static;
    procedure AddKeyedValue(const aLock: TCriticalSection; const aValues: TList<TKeyed>; const aEvent: TKeyed);
    function FindKeyedValue(const aLock: TCriticalSection; const aValues: TList<TKeyed>; const aKey: string): integer;
    procedure WaitForKeyedCount(const aLock: TCriticalSection; const aValues: TList<TKeyed>; aExpected: integer;
      aTimeoutMs: Cardinal);
  published
    procedure DropsIntermediateDeliversLatest;
    procedure ZeroWindowBatchesPosts;
    procedure ClearPreservesCoalesceForTypedTopic;
    procedure ClearPreservesCoalesceForNamedOfTopic;
    procedure ClearPreservesCoalesceForGuidTopic;
  end;

  TTestFuzz = class(TmaxTestCase)
  published
    procedure RandomDeliveryNoDeadlock;
  end;

  TTestStress = class(TmaxTestCase)
  published
    procedure OneMillionPosts;
    procedure StressSuiteSwitchRunsSuccessfully;
  end;

  TPostBurstThread = class(TThread)
  public
    fBus: ImaxBus;
    fCount: integer;
    constructor Create(const aBus: ImaxBus; aCount: integer);
  protected
    procedure Execute; override;
  end;

  TTestMetrics = class(TmaxTestCase)
  published
    procedure CountsPostsAndDelivered;
    procedure CountsDropped;
    procedure CountsExceptions;
  end;

  TTestMetricsThrottling = class(TmaxTestCase)
  published
    procedure ThrottlesMetricCallback;
  end;

  TMetricPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fCount: integer;
    fStart: TEvent;
    fDone: TEvent;
    constructor Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aCount: integer);
  protected
    procedure Execute; override;
  end;

  TMetricNamedTopicCreateThread = class(TThread)
  public
    fBus: ImaxBus;
    fStart: TEvent;
    fDone: TEvent;
    fCount: integer;
    constructor Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aCount: integer);
  protected
    procedure Execute; override;
  end;

  TMetricReadThread = class(TThread)
  public
    fBus: ImaxBus;
    fStart: TEvent;
    fDone: TEvent;
    fIterations: integer;
    constructor Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aIterations: integer);
  protected
    procedure Execute; override;
  end;

  TTestMetricsConcurrent = class(TmaxTestCase)
  published
    procedure TotalsReadWhilePostingAndCreatingTopics;
    procedure StatsReadsAreSafeDuringTopicPublish;
  end;

  TPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TMainPolicyPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fValue: integer;
    fThreadId: TThreadID;
    fRaised: boolean;
    fRaisedClass: string;
    constructor Create(const aBus: ImaxBus; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TNamedDispatchCaptureThread = class(TThread)
  public
    fBus: ImaxBus;
    fDelivery: integer;
    fRaisedClass: string;
    fRaisedMessage: string;
    fRaisedTopic: string;
    fTopicName: TmaxString;
    constructor Create(const aBus: ImaxBus; const aTopicName: TmaxString);
  protected
    procedure Execute; override;
  end;

  TGuidDispatchCaptureThread = class(TThread)
  public
    fBus: ImaxBus;
    fDelivery: integer;
    fRaisedClass: string;
    fRaisedMessage: string;
    fRaisedTopic: string;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TTestNamedTopics = class(TmaxTestCase)
  published
    procedure StickyAndCoalesceNamed;
    procedure QueuePolicyAndMetricsNamed;
    procedure TryPostNamedNoTopicReturnsTrueWithoutCounters;
    procedure TryPostNamedDeliversWhenSubscriberExists;
    procedure TryPostNamedDropNewestDrops;
    procedure TryPostNamedDropOldestDropsQueuedOldest;
    procedure TryPostNamedBlockWaits;
    procedure TryPostNamedDeadlineDrops;
  end;

  TNamedPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fName: TmaxString;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; const aName: TmaxString; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TPresetNamedPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fName: TmaxString;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; const aName: TmaxString; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TGuidPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TTestSticky = class(TmaxTestCase)
  published
    procedure LateSubscriberGetsLastEvent;
    procedure ClearPreservesStickyConfig;
    procedure TryPostStickyFirstCountsPost;
  end;

  TTarget = class
  private
    fCount: integer;
    fLastValue: integer;
  public
    procedure Handle(const aValue: integer);
    property Count: integer read fCount;
    property LastValue: integer read fLastValue;
  end;

  TTestUnsubscribeAll = class(TmaxTestCase)
  published
    procedure RemovesAllHandlers;
  end;

  TTestSchedulers = class(TmaxTestCase)
  private
    function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): boolean;
    procedure ExerciseScheduler(const aScheduler: IEventNexusScheduler; const aName: string);
	  published
	    procedure RawThreadScheduler;
	    {$IFDEF max_DELPHI}
	    procedure MaxAsyncScheduler;
	    procedure TTaskScheduler;
	    procedure SchedulerSwapUpdatesLiveBus;
      procedure DefaultAsyncProbeReturnsSingleInstanceAcrossThreads;
	    {$ENDIF}
	  end;

  TTestGuidTopics = class(TmaxTestCase)
  published
    procedure GuidPublishDelivers;
    procedure StickyGuidDeliversLast;
    procedure CoalesceGuidDeliversLatest;
    procedure QueuePolicyAndMetricsGuid;
  end;

  TTestMainThreadPolicy = class(TmaxTestCase)
  published
    procedure StrictRaisesOffMain;
    procedure DegradeToPostingRunsInline;
    procedure DegradeToAsyncRunsOffPostingThread;
    procedure ClearDoesNotRebindMainThreadIdentity;
  end;

  {$IFDEF max_DELPHI}
  TTestAutoSubscribe = class(TmaxTestCase)
  published
    procedure RegistersTypedNamedAndInherited;
    procedure AutoUnsubscribeClearsHandlers;
    procedure UnsubscribeAllForClearsAutoSubscriptions;
    procedure InvalidAttributedFormsRaise;
    procedure NamedNoArgBindsCorrectMethod;
    procedure GuidOneParamBindsAndUnsubscribes;
  end;
  {$ENDIF}

  IIntEvent = interface
    ['{E0A90F15-6C16-4BD7-9057-CC95B2E98F03}']
    function GetValue: integer;
  end;

  IPostResultGuidEvent = interface
    ['{9F1962EE-B102-4A3D-AF64-DBAC6D3A0A7E}']
    function GetValue: integer;
  end;

  IQueueMetricsGuidEvent = interface
    ['{87E79E11-04A4-49AE-A630-4898A2BC728D}']
    function GetValue: integer;
  end;

  IQueuePresetGuidEvent = interface
    ['{F85E099C-4F60-4062-975C-3D2AB9C65215}']
    function GetValue: integer;
  end;

  TIntEvent = class(TInterfacedObject, IIntEvent)
  private
    fVal: integer;
  public
    constructor Create(aValue: integer);
    function GetValue: integer;
  end;

  TPostResultGuidEvent = class(TInterfacedObject, IPostResultGuidEvent)
  private
    fVal: integer;
  public
    constructor Create(aValue: integer);
    function GetValue: integer;
  end;

  TQueueMetricsGuidEvent = class(TInterfacedObject, IQueueMetricsGuidEvent)
  private
    fVal: integer;
  public
    constructor Create(aValue: integer);
    function GetValue: integer;
  end;

  TQueuePresetGuidEvent = class(TInterfacedObject, IQueuePresetGuidEvent)
  private
    fVal: integer;
  public
    constructor Create(aValue: integer);
    function GetValue: integer;
  end;

  TWeakTargetProbe = class
  public
    class var HitsInt: integer;
    class var HitsIntf: integer;
    class var LastInt: integer;
    class var LastIntfWasNil: boolean;
    procedure OnInt(const aValue: integer);
    procedure OnIntf(const aValue: IIntEvent);
  end;

  TTestWeakTargets = class(TmaxTestCase)
  published
    procedure SkipsFreedTargetTyped;
    procedure SkipsFreedTargetNamedOf;
    procedure SkipsFreedTargetGuidOf;
  end;

  TTestStrongTargets = class(TmaxTestCase)
  published
    procedure UnsubscribeAllForRemovesTypedStrong;
    procedure UnsubscribeAllForRemovesNamedStrong;
    procedure UnsubscribeAllForRemovesGuidStrong;
  end;

  TTestWeakTargetABA = class(TmaxTestCase)
  published
    procedure PreventsQueuedABARedirect;
  end;

  TTestSubscriptionTokens = class(TmaxTestCase)
  published
    procedure TokenReleaseAutoUnsubscribes;
    procedure QueuedBeforeCancelSkipsExecution;
    procedure ClearInvalidatesOldHandlesWithoutCrossUnsubscribe;
    procedure ClearInFlightAsyncNamedKeepsNewSubscriptionActive;
    procedure ClearInFlightAsyncGuidKeepsNewSubscriptionActive;
  end;

  TTestPostResult = class(TmaxTestCase)
  published
    procedure NoTopicReturnsNoTopic;
    procedure DropNewestReturnsDropped;
    procedure NamedOfDropNewestReturnsDropped;
    procedure CoalescedReturnsCoalesced;
    procedure AcceptedReturnsInlineOrQueued;
    procedure GuidOfQueuePressureReturnsQueuedThenDropped;
    procedure GuidOfAcceptedReturnsInline;
    procedure ClearPreservesTypedExplicitPolicy;
    procedure ClearPreservesNamedExplicitPolicy;
    procedure ClearPreservesGuidExplicitPolicy;
    procedure PostResultTypedAutoSubscribeIsNotNoTopic;
    procedure PostResultNamedOfAutoSubscribeIsNotNoTopic;
    procedure PostResultGuidOfAutoSubscribeIsNotNoTopic;
    procedure PostResultTypedAutoSubscribeAsyncReturnsQueued;
    procedure PostResultNamedOfAutoSubscribeBackgroundReturnsQueued;
    procedure PostResultGuidOfAutoSubscribeMainReturnsQueued;
    procedure PostResultTypedAsyncSubscriberReportsInline;
    procedure PostResultNamedOfBackgroundSubscriberReportsInline;
    procedure PostResultGuidOfMainSubscriberReportsInline;
  end;

  TTestDispatchErrorDetails = class(TmaxTestCase)
  private
    procedure AssertSingleCoalescedDetail(const aTopicName: string; const aDetails: TArray<TmaxDispatchErrorDetail>);
  published
    procedure IncludesSubscriberMetadataForPost;
    procedure IncludesMetadataForCoalescedAsyncHook;
    procedure WildcardSubscriberFailuresExposeWildcardMetadata;
  end;

  TTestTracingHooks = class(TmaxTestCase)
  published
    procedure EmitsEnqueueInvokeStartAndEnd;
    procedure EmitsInvokeError;
    procedure DisabledTraceProducesNoCallbacks;
  end;

  TTestBulkDispatch = class(TmaxTestCase)
  published
    procedure TypedBulkPreservesOrder;
    procedure NamedOfBulkPreservesOrder;
    procedure GuidOfBulkPreservesOrder;
    procedure BulkAggregatesAcrossItems;
    procedure TypedAsyncPostsPreserveOrderAgainstReorderingScheduler;
    procedure NamedOfMainPostsPreserveOrderAgainstReorderingScheduler;
    procedure GuidOfBackgroundPostsPreserveOrderAgainstReorderingScheduler;
    procedure TypedAsyncBulkPreservesOrderAgainstReorderingScheduler;
    procedure NamedOfMainBulkPreservesOrderAgainstReorderingScheduler;
    procedure GuidOfBackgroundBulkPreservesOrderAgainstReorderingScheduler;
  end;

  TTestWildcardNamed = class(TmaxTestCase)
  private
    procedure AssertInvalidWildcardPattern(const aPattern: string; const aMessage: string);
  published
    procedure PrefixAndGlobalWildcardMatch;
    procedure InvalidWildcardPatternsAreRejected;
    procedure LongerPrefixWildcardPrecedenceWins;
    procedure UnsubscribeStopsWildcardDelivery;
    procedure WildcardDispatchesWithoutPrecreatedNamedTopic;
    procedure SamePrefixLengthUsesSubscriptionOrder;
  end;

  TTestDelayedPosting = class(TmaxTestCase)
  published
    procedure NamedDelayedPostWaitsBeforeDelivery;
    procedure NamedOfDelayedPostWaitsBeforeDelivery;
    procedure GuidDelayedPostWaitsBeforeDelivery;
    procedure CancelPreventsTypedDelayedDelivery;
    procedure CancelNearDeadlineHasConsistentOutcome;
    procedure ClearDropsPendingDelayedPosts;
    procedure ZeroDelayDispatchesAndUpdatesMetrics;
    procedure LargeDelayRemainsPendingUntilCanceled;
    procedure TypedLargeDelayRemainsPendingUntilCanceled;
    procedure TypedDelayedFailureWithoutAsyncHookStaysSilent;
    procedure TypedDelayedFailureForwardsAsyncHook;
    procedure NamedDelayedFailureForwardsAsyncHook;
    procedure NamedOfDelayedFailureForwardsAsyncHook;
    procedure GuidDelayedFailureForwardsAsyncHook;
    procedure SchedulerFailureDelayedNamedForwardsAsyncHook;
    procedure SchedulerFailureStillWaitsBeforeNamedDelivery;
    procedure SchedulerFailureCancelAndClearPreventDelayedDelivery;
  end;

  TTestMetricsCallbackTotals = class(TmaxTestCase)
  published
    procedure MetricCallbackReceivesSnapshots;
    procedure GetTotalsAggregates;
  end;

  TTestQueuePolicy = class(TmaxTestCase)
  published
    procedure DropNewestDrops;
    procedure DropOldestRemoves;
    procedure BlockWaits;
    procedure DeadlineDrops;
  end;

  TTestQueuePolicyPresets = class(TmaxTestCase)
  private
    procedure AssertNamedOfDropNewestPolicy(const aBus: ImaxBus; const aName: TmaxString);
    procedure AssertNamedOfUnboundedPresetEventPolicy(const aBus: ImaxBus; const aName: TmaxString);
    procedure AssertNamedOfStatePolicy(const aBus: ImaxBus; const aName: TmaxString);
  published
    procedure TypedPresetAffectsGetPolicy;
    procedure NamedStatePresetUsesDropOldest;
    procedure NamedOfTypePresetFallbackUsesState;
    procedure NamedOfNamePresetOverridesTypePreset;
    procedure NamedOfExplicitPolicyOverridesPresets;
    procedure NamedOfRemovingNamePresetFallsBackToTypePreset;
    procedure NamedOfRemovingNamePresetFallsBackPerType;
    procedure NamedOfTypePresetUpdateReappliesToExistingImplicitTopic;
    procedure ClearPreservesNamedOfTypePresetFallback;
    procedure NamedPresetsReturnDefaultPolicy;
    procedure GuidPresetAffectsGetPolicy;
    procedure GuidExplicitPolicyBeatsPreset;
  end;

  TTestHighWaterReset = class(TmaxTestCase)
  published
    procedure ResetsAfterDraining;
  end;

  TTestSubscribeOrdering = class(TmaxTestCase)
  published
    procedure PreservesOrderAndHandlesChurn;
  end;

  TTestInterfaceGenerics = class(TmaxTestCase)
  private
    procedure VerifyPostAndTryPost(const aBus: ImaxBus; const aBusObj: TmaxBus; var aReceived: integer);
    procedure VerifyStickyBehavior(const aBus: ImaxBus; const aBusObj: TmaxBus; var aReceived: integer);
    procedure VerifyQueuePolicyRoundTrip(const aBus: ImaxBus; const aBusObj: TmaxBus);
    procedure VerifyStatsForInteger(const aBus: ImaxBus; const aBusObj: TmaxBus);
  published
    procedure UsesInterfaceGenerics;
  end;

implementation

uses
  System.IOUtils,
  maxLogic.Utils;

{$IFDEF max_DELPHI}
type
  TAutoSubBase = class
  public
    IntHits: integer;
    LastInt: integer;
    [maxSubscribe]
    procedure OnInt(const aValue: integer);
  end;

  TAutoSubDerived = class(TAutoSubBase)
  public
    PingHits: integer;
    DataHits: integer;
    LastData: integer;
    [maxSubscribe('ping')]
    procedure OnPing;
    [maxSubscribe('data')]
    procedure OnData(const aValue: integer);
  end;

  TBadAutoSub = class
  public
    [maxSubscribe]
    procedure Bad(const aFirst, aSecond: integer);
  end;

  TBadAutoSubClassMethod = class
  public
    [maxSubscribe]
    class procedure BadClass(const aValue: integer);
  end;

  TBadAutoSubCtor = class
  public
    [maxSubscribe]
    constructor Create;
  end;

  TBadAutoSubDtor = class
  public
    [maxSubscribe]
    destructor Destroy; override;
  end;

  TAbstractAutoSub = class abstract
  public
    [maxSubscribe]
    procedure OnInt(const aValue: integer); virtual; abstract;
  end;

  TRepeatedAutoSub = class
  public
    [maxSubscribe]
    [maxSubscribe('dup')]
    procedure OnInt(const aValue: integer);
  end;

  TAutoSubNamedNoArg = class
  public
    FirstHits: integer;
    SecondHits: integer;
    [maxSubscribe('first')]
    procedure OnFirst;
    [maxSubscribe('second')]
    procedure OnSecond;
  end;

  TAutoSubGuid = class
  public
    GuidHits: integer;
    LastGuidValue: integer;
    [maxSubscribe]
    procedure OnGuid(const aValue: IIntEvent);
  end;

  TAutoSubDeferred = class
  public
    IntHits: integer;
    LastInt: integer;
    DataHits: integer;
    LastData: integer;
    GuidHits: integer;
    LastGuidValue: integer;
    [maxSubscribe(TmaxDelivery.Async)]
    procedure OnIntAsync(const aValue: integer);
    [maxSubscribe('data.defer', TmaxDelivery.Background)]
    procedure OnDataBackground(const aValue: integer);
    [maxSubscribe(TmaxDelivery.Main)]
    procedure OnGuidMain(const aValue: IIntEvent);
  end;
{$ENDIF}

{$IFDEF max_DELPHI}
procedure TAutoSubBase.OnInt(const aValue: integer);
begin
  Inc(IntHits);
  LastInt := aValue;
end;

procedure TAutoSubDerived.OnPing;
begin
  Inc(PingHits);
end;

procedure TAutoSubDerived.OnData(const aValue: integer);
begin
  Inc(DataHits);
  LastData := aValue;
end;

procedure TBadAutoSub.Bad(const aFirst, aSecond: integer);
begin
  if aFirst = aSecond then
    Exit;
end;

class procedure TBadAutoSubClassMethod.BadClass(const aValue: integer);
begin
  if aValue = -1 then
    Exit;
end;

constructor TBadAutoSubCtor.Create;
begin
  inherited Create;
end;

destructor TBadAutoSubDtor.Destroy;
begin
  inherited Destroy;
end;

procedure TRepeatedAutoSub.OnInt(const aValue: integer);
begin
  if aValue = -1 then
    Exit;
end;

procedure TAutoSubNamedNoArg.OnFirst;
begin
  Inc(FirstHits);
end;

procedure TAutoSubNamedNoArg.OnSecond;
begin
  Inc(SecondHits);
end;

procedure TAutoSubGuid.OnGuid(const aValue: IIntEvent);
begin
  Inc(GuidHits);
  if aValue <> nil then
    LastGuidValue := aValue.GetValue
  else
    LastGuidValue := 0;
end;

procedure TAutoSubDeferred.OnIntAsync(const aValue: integer);
begin
  Inc(IntHits);
  LastInt := aValue;
end;

procedure TAutoSubDeferred.OnDataBackground(const aValue: integer);
begin
  Inc(DataHits);
  LastData := aValue;
end;

procedure TAutoSubDeferred.OnGuidMain(const aValue: IIntEvent);
begin
  Inc(GuidHits);
  if aValue <> nil then
    LastGuidValue := aValue.GetValue
  else
    LastGuidValue := 0;
end;

function LogsDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
end;

var
  glLogCs: TCriticalSection;

procedure LogLine(const aTestName, aLine: string);
var
  lLine, lFileName: string;
begin
  {$IFDEF DEBUG}
  if glLogCs = nil then
    Exit;
  glLogCs.Enter;
  try
    if not TDirectory.Exists(LogsDir) then
      TDirectory.CreateDirectory(LogsDir);
    lFileName := TPath.Combine(LogsDir, aTestName + '.log');
    lLine := FormatDateTime('hh:nn:ss.zzz', Now) + ' [T' + IntToStr(TThread.CurrentThread.ThreadID) + '] ' + aLine + sLineBreak + sLineBreak;
    TFile.AppendAllText(lFileName, lLine, TEncoding.UTF8);
  finally
    glLogCs.Leave;
  end;
  {$ELSE}
  if (aTestName = '') and (aLine = '') then
    Exit;
  {$ENDIF}
end;
{$ENDIF}

type
  TSignalScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fAsyncCalled: TEvent;
  public
    constructor Create(const aAsyncCalled: TEvent);
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

constructor TSignalScheduler.Create(const aAsyncCalled: TEvent);
begin
  inherited Create;
  fAsyncCalled := aAsyncCalled;
end;

procedure TSignalScheduler.RunAsync(const aProc: TmaxProc);
begin
  if fAsyncCalled <> nil then
    fAsyncCalled.SetEvent;
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TSignalScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TSignalScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if aDelayUs = -1 then
    Exit;
  if ProcAssigned(aProc) then
    aProc();
end;

function TSignalScheduler.IsMainThread: Boolean;
begin
  Result := False;
end;

type
  TABATarget = class
  public
    fStarted: TEvent;
    fRelease: TEvent;
    fHits: integer;
    procedure OnInt(const aValue: integer);
    procedure OnABA(const aValue: TABAEvent);
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
    class procedure CleanupReuse;
  private
    class var fReuseMem: Pointer;
  end;

  TQueueBlockProbe = class
  public
    fStarted: TEvent;
    fRelease: TEvent;
    fHits: integer;
    procedure OnInt(const aValue: integer);
  end;

  TAsyncClearProbe = class
  public
    fStarted: TEvent;
    fRelease: TEvent;
    fFinished: TEvent;
    fDone: TEvent;
    fOldHits: integer;
    fNewHits: integer;
    constructor Create;
    destructor Destroy; override;
    procedure OnOldNamed;
    procedure OnNewNamed;
    procedure OnOldGuid(const aValue: IIntEvent);
    procedure OnNewGuid(const aValue: IIntEvent);
  end;

  TNamedQueueBlockProbe = class
  public
    fStarted: TEvent;
    fRelease: TEvent;
    fHits: integer;
    constructor Create;
    destructor Destroy; override;
    procedure OnNamed;
  end;

  TInlineScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  THoldDelayedScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  TRaiseDelayedScheduler = class(TInterfacedObject, IEventNexusScheduler)
  public
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  TReverseScheduler = class(TInterfacedObject, IEventNexusScheduler)
  private
    fAsyncQueue: TList<TmaxProc>;
    fMainQueue: TList<TmaxProc>;
    procedure DrainReverse(const aQueue: TList<TmaxProc>);
  public
    constructor Create;
    destructor Destroy; override;
    function AsyncCount: integer;
    function MainCount: integer;
    procedure DrainAsyncReverse;
    procedure DrainMainReverse;
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  TAsyncErrorCapture = class
  public
    DetailMessage: string;
    ErrorMessage: string;
    InnerCount: integer;
    Topic: string;
    WasDispatchError: Boolean;
  end;

function BuildQueuePolicy(aMaxDepth: integer; aOverflow: TmaxOverflow; aDeadlineUs: Int64): TmaxQueuePolicy;
begin
  Result.MaxDepth := aMaxDepth;
  Result.Overflow := aOverflow;
  Result.DeadlineUs := aDeadlineUs;
end;

function MakePresetEvent(aValue: integer): TPresetEvent;
begin
  Result.Value := aValue;
end;

function CreateIsolatedBus: ImaxBus;
begin
  Result := TmaxBus.Create(CreateMaxAsyncScheduler);
end;

procedure PostIntegerValue(const aBus: ImaxBus; aValue: integer);
begin
  {$IFDEF max_FPC}
  aBus.Post<integer>(aValue);
  {$ELSE}
  maxBusObj(aBus).Post<integer>(aValue);
  {$ENDIF}
end;

procedure PostKeyedValues(const aBus: ImaxBus; const aValues: array of TKeyed);
var
  lValue: TKeyed;
begin
  for lValue in aValues do
  begin
    {$IFDEF max_FPC}
    aBus.Post<TKeyed>(lValue);
    {$ELSE}
    maxBusObj(aBus).Post<TKeyed>(lValue);
    {$ENDIF}
  end;
end;

procedure PostGuidValues(const aBus: ImaxBus; const aValues: array of integer);
var
  i: integer;
begin
  for i := Low(aValues) to High(aValues) do
  begin
    {$IFDEF max_FPC}
    aBus.PostGuidOf<IIntEvent>(TIntEvent.Create(aValues[i]));
    {$ELSE}
    maxBusObj(aBus).PostGuidOf<IIntEvent>(TIntEvent.Create(aValues[i]));
    {$ENDIF}
  end;
end;

procedure AssertLockedKeyedCount(const aLock: TCriticalSection; const aValues: TList<TKeyed>; aExpected: integer);
begin
  aLock.Enter;
  try
    if aValues.Count <> aExpected then
      raise Exception.CreateFmt('Expected keyed count %d but got %d.', [aExpected, aValues.Count]);
  finally
    aLock.Leave;
  end;
end;

procedure AssertLockedIntegerState(const aLock: TCriticalSection; const aValues: TList<integer>; aExpectedCount,
  aExpectedFirst: integer);
begin
  aLock.Enter;
  try
    if aValues.Count <> aExpectedCount then
      raise Exception.CreateFmt('Expected integer count %d but got %d.', [aExpectedCount, aValues.Count]);
    if aValues[0] <> aExpectedFirst then
      raise Exception.CreateFmt('Expected first integer %d but got %d.', [aExpectedFirst, aValues[0]]);
  finally
    aLock.Leave;
  end;
end;

procedure AddLockedIntegerValue(const aLock: TCriticalSection; const aValues: TList<integer>; aValue: integer);
begin
  aLock.Enter;
  try
    aValues.Add(aValue);
  finally
    aLock.Leave;
  end;
end;

procedure AddLockedIntEventValue(const aLock: TCriticalSection; const aValues: TList<integer>; const aEvent: IIntEvent);
begin
  if aEvent = nil then
    AddLockedIntegerValue(aLock, aValues, 0)
  else
    AddLockedIntegerValue(aLock, aValues, aEvent.GetValue);
end;

procedure WaitForLockedIntegerCount(const aLock: TCriticalSection; const aValues: TList<integer>; aExpected: integer;
  aTimeoutMs: Cardinal);
var
  lCount: integer;
  lStart: UInt64;
begin
  lStart := GetTickCount64;
  repeat
    aLock.Enter;
    try
      lCount := aValues.Count;
    finally
      aLock.Leave;
    end;
    if lCount >= aExpected then
      Exit;
    CheckSynchronize(0);
    Sleep(1);
  until GetTickCount64 - lStart >= aTimeoutMs;
end;

function SubscribeGuidValueCapture(const aBus: ImaxBus; const aLock: TCriticalSection;
  const aValues: TList<integer>): ImaxSubscription;
begin
  Result := maxBusObj(aBus).SubscribeGuidOf<IIntEvent>(
    procedure(const aValue: IIntEvent)
    begin
      AddLockedIntEventValue(aLock, aValues, aValue);
    end,
    TmaxDelivery.Posting);
end;

procedure ReleaseAndJoinThread(const aRelease: TEvent; var aThread: TThread);
begin
  if aRelease <> nil then
    aRelease.SetEvent;
  if aThread <> nil then
  begin
    aThread.WaitFor;
    aThread.Free;
    aThread := nil;
  end;
end;

function PostGuidResultOffMain(const aBus: ImaxBus; const aValue: IIntEvent): TmaxPostResult;
var
  lDone: TEvent;
  lError: string;
  lResult: TmaxPostResult;
  lThread: TThread;
  lValue: IIntEvent;
begin
  lDone := TEvent.Create(nil, True, False, '');
  lError := '';
  lResult := TmaxPostResult.NoTopic;
  lThread := nil;
  lValue := aValue;
  try
    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          lResult := maxBusObj(aBus).PostResultGuidOf<IIntEvent>(lValue);
        except
          on e: Exception do
            lError := e.ClassName + ': ' + e.Message;
        end;
        lDone.SetEvent;
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    if lDone.WaitFor(1000) <> wrSignaled then
      raise Exception.Create('Timed out waiting for off-main auto-subscribed guid PostResult');

    lThread.WaitFor;
    if lError <> '' then
      raise Exception.Create(lError);
    Result := lResult;
  finally
    if lThread <> nil then
      lThread.Free;
    lDone.Free;
  end;
end;

procedure RestoreAsyncSchedulerState(const aPrevScheduler: IEventNexusScheduler);
begin
  maxSetAsyncErrorHandler(nil);
  maxSetAsyncScheduler(aPrevScheduler);
end;

procedure InstallAsyncErrorCapture(const aCapture: TAsyncErrorCapture; const aSignal: TEvent);
begin
  if aCapture = nil then
    Exit;
  aCapture.DetailMessage := '';
  aCapture.ErrorMessage := '';
  aCapture.InnerCount := 0;
  aCapture.Topic := '';
  aCapture.WasDispatchError := False;
  maxSetAsyncErrorHandler(
    procedure(const aTopic: string; const aE: Exception)
    begin
      aCapture.Topic := aTopic;
      aCapture.WasDispatchError := aE is EmaxDispatchError;
      if aCapture.WasDispatchError then
      begin
        aCapture.InnerCount := EmaxDispatchError(aE).Inner.Count;
        if Length(EmaxDispatchError(aE).Details) > 0 then
          aCapture.DetailMessage := EmaxDispatchError(aE).Details[0].ExceptionMessage;
      end;
      aCapture.ErrorMessage := aE.Message;
      if aSignal <> nil then
        aSignal.SetEvent;
    end);
end;

procedure AssertDelayedHookCapture(const aCapture: TAsyncErrorCapture; const aExpectedTopic: string;
  const aExpectedDetail: string);
begin
  if (aCapture = nil) or (not aCapture.WasDispatchError) then
    raise Exception.Create('Delayed-post hook should receive EmaxDispatchError');
  if aCapture.InnerCount <> 1 then
    raise Exception.CreateFmt('Expected one delayed-post inner error but got %d', [aCapture.InnerCount]);
  if aCapture.Topic <> aExpectedTopic then
    raise Exception.CreateFmt('Expected delayed-post topic [%s] but got [%s]', [aExpectedTopic, aCapture.Topic]);
  if aCapture.ErrorMessage <> '1 exception(s) occurred' then
    raise Exception.CreateFmt('Expected delayed-post error message [%s] but got [%s]',
      ['1 exception(s) occurred', aCapture.ErrorMessage]);
  if aCapture.DetailMessage <> aExpectedDetail then
    raise Exception.CreateFmt('Expected delayed-post detail [%s] but got [%s]', [aExpectedDetail, aCapture.DetailMessage]);
end;

function RunProcessAndGetExitCode(const aExePath: string; const aArgs: string): Cardinal;
var
  lCommandLine: string;
  lExitCode: Cardinal;
  lProcessInfo: TProcessInformation;
  lStartupInfo: TStartupInfo;
begin
  FillChar(lStartupInfo, SizeOf(lStartupInfo), 0);
  lStartupInfo.cb := SizeOf(lStartupInfo);
  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);
  lCommandLine := '"' + aExePath + '"';
  if aArgs <> '' then
    lCommandLine := lCommandLine + ' ' + aArgs;
  UniqueString(lCommandLine);
  if not CreateProcess(nil, PChar(lCommandLine), nil, nil, False, 0, nil, PChar(ExtractFilePath(aExePath)),
    lStartupInfo, lProcessInfo) then
    raise EOSError.CreateFmt('CreateProcess failed (%d) for %s', [GetLastError, lCommandLine]);
  try
    if WaitForSingleObject(lProcessInfo.hProcess, 15000) <> WAIT_OBJECT_0 then
      raise Exception.CreateFmt('Timed out waiting for process %s', [lCommandLine]);
    if not GetExitCodeProcess(lProcessInfo.hProcess, lExitCode) then
      raise EOSError.CreateFmt('GetExitCodeProcess failed (%d) for %s', [GetLastError, lCommandLine]);
    Result := lExitCode;
  finally
    CloseHandle(lProcessInfo.hThread);
    CloseHandle(lProcessInfo.hProcess);
  end;
end;

procedure TABATarget.OnInt(const aValue: integer);
begin
  if aValue = 1 then
  begin
    Inc(fHits);
    if fStarted <> nil then
      fStarted.SetEvent;
    if fRelease <> nil then
      fRelease.WaitFor(5000);
    Exit;
  end;
  Inc(fHits);
end;

procedure TABATarget.OnABA(const aValue: TABAEvent);
begin
  if aValue.Value = -1 then
    Exit;
end;

class function TABATarget.NewInstance: TObject;
begin
  if fReuseMem <> nil then
  begin
    Result := InitInstance(fReuseMem);
    fReuseMem := nil;
    Exit;
  end;
  Result := inherited NewInstance;
end;

procedure TABATarget.FreeInstance;
begin
  if fReuseMem = nil then
  begin
    CleanupInstance;
    fReuseMem := Pointer(Self);
    Exit;
  end;
  inherited FreeInstance;
end;

class procedure TABATarget.CleanupReuse;
var
  p: Pointer;
begin
  p := fReuseMem;
  fReuseMem := nil;
  if p <> nil then
    FreeMem(p);
end;

procedure TQueueBlockProbe.OnInt(const aValue: integer);
begin
  Inc(fHits);
  if aValue = 1 then
  begin
    if fStarted <> nil then
      fStarted.SetEvent;
    if fRelease <> nil then
      fRelease.WaitFor(5000);
  end;
end;

constructor TNamedQueueBlockProbe.Create;
begin
  inherited Create;
  fStarted := TEvent.Create(nil, True, False, '');
  fRelease := TEvent.Create(nil, True, False, '');
  fHits := 0;
end;

destructor TNamedQueueBlockProbe.Destroy;
begin
  fRelease.Free;
  fStarted.Free;
  inherited;
end;

procedure TNamedQueueBlockProbe.OnNamed;
begin
  Inc(fHits);
  if fHits = 1 then
  begin
    fStarted.SetEvent;
    fRelease.WaitFor(5000);
  end;
end;

constructor TAsyncClearProbe.Create;
begin
  inherited Create;
  fStarted := TEvent.Create(nil, True, False, '');
  fRelease := TEvent.Create(nil, True, False, '');
  fFinished := TEvent.Create(nil, True, False, '');
  fDone := TEvent.Create(nil, True, False, '');
  fOldHits := 0;
  fNewHits := 0;
end;

destructor TAsyncClearProbe.Destroy;
begin
  fDone.Free;
  fFinished.Free;
  fRelease.Free;
  fStarted.Free;
  inherited;
end;

procedure TAsyncClearProbe.OnOldNamed;
begin
  Inc(fOldHits);
  fStarted.SetEvent;
  fRelease.WaitFor(5000);
  fFinished.SetEvent;
end;

procedure TAsyncClearProbe.OnNewNamed;
begin
  Inc(fNewHits);
  fDone.SetEvent;
end;

procedure TAsyncClearProbe.OnOldGuid(const aValue: IIntEvent);
begin
  if aValue = nil then
    Exit;
  Inc(fOldHits);
  fStarted.SetEvent;
  fRelease.WaitFor(5000);
  fFinished.SetEvent;
end;

procedure TAsyncClearProbe.OnNewGuid(const aValue: IIntEvent);
begin
  if aValue = nil then
    Exit;
  Inc(fNewHits);
  fDone.SetEvent;
end;

procedure StartNamedPostThread(const aBus: ImaxBus; const aName: TmaxString);
var
  lThread: TThread;
begin
  lThread := TThread.CreateAnonymousThread(
    procedure
    begin
      aBus.PostNamed(aName);
    end);
  lThread.FreeOnTerminate := True;
  lThread.Start;
end;

procedure WaitForNamedHits(const aProbe: TNamedQueueBlockProbe; aExpected: integer; aTimeoutMs: Cardinal);
var
  lStart: UInt64;
begin
  lStart := GetTickCount64;
  while GetTickCount64 - lStart < aTimeoutMs do
  begin
    if aProbe.fHits >= aExpected then
      Exit;
    CheckSynchronize(0);
    Sleep(1);
  end;
  raise Exception.CreateFmt('Timed out waiting for named hits=%d (current=%d)', [aExpected, aProbe.fHits]);
end;

procedure SetupNamedQueuePressure(const aBus: ImaxBus; const aName: TmaxString; aOverflow: TmaxOverflow;
  aDeadlineUs: Int64; out aSub: ImaxSubscription; out aProbe: TNamedQueueBlockProbe);
var
  lPolicy: TmaxQueuePolicy;
  lProbe: TNamedQueueBlockProbe;
  lQueues: ImaxBusQueues;
begin
  lQueues := aBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := aOverflow;
  lPolicy.DeadlineUs := aDeadlineUs;
  lQueues.SetPolicyNamed(aName, lPolicy);
  lProbe := TNamedQueueBlockProbe.Create;
  aProbe := lProbe;
  aSub := aBus.SubscribeNamed(aName, lProbe.OnNamed, TmaxDelivery.Posting);
end;

procedure TInlineScheduler.RunAsync(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TInlineScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TInlineScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if ProcAssigned(aProc) then
    aProc();
  if aDelayUs = -1 then
    Exit;
end;

function TInlineScheduler.IsMainThread: Boolean;
begin
  Result := False;
end;

procedure THoldDelayedScheduler.RunAsync(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure THoldDelayedScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure THoldDelayedScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if (aDelayUs = 0) and ProcAssigned(aProc) then
    aProc();
end;

function THoldDelayedScheduler.IsMainThread: Boolean;
begin
  Result := False;
end;

procedure TRaiseDelayedScheduler.RunAsync(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TRaiseDelayedScheduler.RunOnMain(const aProc: TmaxProc);
begin
  if ProcAssigned(aProc) then
    aProc();
end;

procedure TRaiseDelayedScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if aDelayUs = -1 then
    Exit;
  raise Exception.Create('run-delayed submit failed');
end;

function TRaiseDelayedScheduler.IsMainThread: Boolean;
begin
  Result := False;
end;

constructor TReverseScheduler.Create;
begin
  inherited Create;
  fAsyncQueue := TList<TmaxProc>.Create;
  fMainQueue := TList<TmaxProc>.Create;
end;

destructor TReverseScheduler.Destroy;
begin
  fMainQueue.Free;
  fAsyncQueue.Free;
  inherited Destroy;
end;

function TReverseScheduler.AsyncCount: integer;
begin
  Result := fAsyncQueue.Count;
end;

function TReverseScheduler.MainCount: integer;
begin
  Result := fMainQueue.Count;
end;

procedure TReverseScheduler.DrainReverse(const aQueue: TList<TmaxProc>);
var
  lProc: TmaxProc;
begin
  while aQueue.Count > 0 do
  begin
    lProc := aQueue[aQueue.Count - 1];
    aQueue.Delete(aQueue.Count - 1);
    if ProcAssigned(lProc) then
      lProc();
  end;
end;

procedure TReverseScheduler.DrainAsyncReverse;
begin
  DrainReverse(fAsyncQueue);
end;

procedure TReverseScheduler.DrainMainReverse;
begin
  DrainReverse(fMainQueue);
end;

procedure TReverseScheduler.RunAsync(const aProc: TmaxProc);
begin
  fAsyncQueue.Add(aProc);
end;

procedure TReverseScheduler.RunOnMain(const aProc: TmaxProc);
begin
  fMainQueue.Add(aProc);
end;

procedure TReverseScheduler.RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
begin
  if (aDelayUs = 0) and ProcAssigned(aProc) then
    aProc();
end;

function TReverseScheduler.IsMainThread: Boolean;
begin
  Result := False;
end;

{ TTestAggregateException }

procedure TTestAggregateException.AggregatesMultiple;
var
  lBus: ImaxBus;

  {$IFDEF max_FPC}
  procedure First(const aValue: integer);
  begin
    raise Exception.Create('first');
  end;

  procedure Second(const aValue: integer);
  begin
    raise Exception.Create('second');
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@First);
  lBus.Subscribe<integer>(@Second);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('first');
    end);
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('second');
    end);
  {$ENDIF}
  try
    maxBusObj(lBus).Post<integer>(42);
    Check(False, 'Expected aggregate exception');
  except
    on e: EmaxDispatchError do
    begin
      CheckEquals(2, e.Inner.Count);
      CheckEquals('first', e.Inner.Items[0].Message);
      CheckEquals('second', e.Inner.Items[1].Message);
    end;
  end;
end;

procedure TTestAggregateException.QueueContinuesAfterAggregate;
var
  lBus: ImaxBus;
  lDelivered: integer;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lDelivered := 0;

  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      if aValue = 1 then
        raise Exception.Create('first');
      Inc(lDelivered);
    end);
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      if aValue = 1 then
        raise Exception.Create('second');
      Inc(lDelivered);
    end);

  try
    maxBusObj(lBus).Post<integer>(1);
    Check(False, 'Expected aggregate exception');
  except
    on EmaxDispatchError do
      ;
  end;

  maxBusObj(lBus).Post<integer>(2);
  CheckEquals(2, lDelivered, 'Queue must continue draining after prior aggregate failure');
end;

{ TTestAsyncDelivery }

procedure TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread;
var
  lBus: ImaxBus;
  lMainId, lAsyncId, lBgId: TThreadID;
  lEvAsync, lEvBg: TEvent;

  {$IFDEF max_FPC}
  procedure AsyncHandler(const aVal: integer);
  begin
    lAsyncId := TThread.CurrentThread.ThreadID;
    lEvAsync.SetEvent;
  end;

  procedure BgHandler(const aVal: integer);
  begin
    lBgId := TThread.CurrentThread.ThreadID;
    lEvBg.SetEvent;
  end;
  {$ENDIF}
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lMainId := TThread.CurrentThread.ThreadID;
  {$IFDEF max_DELPHI} LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread', 'Start; MainTID=' + IntToStr(lMainId)); {$ENDIF}
  lEvAsync := TEvent.Create(nil, True, False, '');
  lEvBg := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    lBus.Subscribe<integer>(@AsyncHandler, Async);
    lBus.Subscribe<integer>(@BgHandler, Background);
    {$ELSE}
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        lAsyncId := TThread.CurrentThread.ThreadID;
        lEvAsync.SetEvent;
      end,
      Async);
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        lBgId := TThread.CurrentThread.ThreadID;
        lEvBg.SetEvent;
      end,
      Background);
    {$ENDIF}
    {$IFDEF max_DELPHI} LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread', 'Subscribed Async and Background'); {$ENDIF}
    maxBusObj(lBus).Post<integer>(1);
    {$IFDEF max_DELPHI} LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread', 'Posted integer=1'); {$ENDIF}
    Check(lEvAsync.WaitFor(1000) = wrSignaled);
    Check(lEvBg.WaitFor(1000) = wrSignaled);
    {$IFDEF max_DELPHI}
    LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread',
      'Events signaled? Async=' + BoolToStr(lEvAsync.WaitFor(0)=wrSignaled, True) +
      ', Bg=' + BoolToStr(lEvBg.WaitFor(0)=wrSignaled, True));
    LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread',
      Format('TIDs Main=%d, Async=%d, Bg=%d', [lMainId, lAsyncId, lBgId]));
    {$ENDIF}
    Check(lMainId <> lAsyncId);
    Check(lMainId <> lBgId);
  finally
    lEvAsync.Free;
    lEvBg.Free;
  end;
end;

{ TTestCoalesce }

class function TTestCoalesce.MakeKeyed(const aKey: string; aValue: integer): TKeyed;
begin
  Result.Key := aKey;
  Result.Value := aValue;
end;

procedure TTestCoalesce.AddKeyedValue(const aLock: TCriticalSection; const aValues: TList<TKeyed>;
  const aEvent: TKeyed);
begin
  aLock.Enter;
  try
    aValues.Add(aEvent);
  finally
    aLock.Leave;
  end;
end;

function TTestCoalesce.FindKeyedValue(const aLock: TCriticalSection; const aValues: TList<TKeyed>;
  const aKey: string): integer;
var
  lValue: TKeyed;
begin
  aLock.Enter;
  try
    for lValue in aValues do
      if lValue.Key = aKey then
        Exit(lValue.Value);
    Result := -1;
  finally
    aLock.Leave;
  end;
end;

procedure TTestCoalesce.WaitForKeyedCount(const aLock: TCriticalSection; const aValues: TList<TKeyed>;
  aExpected: integer; aTimeoutMs: Cardinal);
var
  lStart: UInt64;
  lCount: integer;
begin
  lStart := GetTickCount64;
  repeat
    aLock.Enter;
    try
      lCount := aValues.Count;
    finally
      aLock.Leave;
    end;
    if lCount >= aExpected then
      Exit;
    CheckSynchronize(0);
    Sleep(1);
  until GetTickCount64 - lStart >= aTimeoutMs;
end;

procedure TTestCoalesce.DropsIntermediateDeliversLatest;
var
  lBus: ImaxBusAdvanced;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<TKeyed>;
  function KeyOf(const aEvent: TKeyed): TmaxString;
  begin
    Result := aEvent.Key;
  end;
  procedure Handler(const aEvent: TKeyed);
  begin
    AddKeyedValue(lLock, lValues, aEvent);
  end;
  {$ELSE}
  lValues: TList<TKeyed>;
  {$ENDIF}
  lLock: TCriticalSection;
begin
  lBus := maxBus as ImaxBusAdvanced;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  try
    {$IFDEF max_FPC}
    lBus.EnableCoalesceOf<TKeyed>(@KeyOf, 10000);
    lValues := specialize TList<TKeyed>.Create;
    lSub := lBus.Subscribe<TKeyed>(@Handler);
    {$ELSE}
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
      function(const aEvt: TKeyed): TmaxString
      begin
        Result := aEvt.Key;
      end,
      10000);
    lValues := TList<TKeyed>.Create;
    lSub := maxBusObj(lBus).Subscribe<TKeyed>(
      procedure(const aEvent: TKeyed)
      begin
        AddKeyedValue(lLock, lValues, aEvent);
      end);
    {$ENDIF}
    try
      PostKeyedValues(lBus, [MakeKeyed('A', 1), MakeKeyed('A', 2), MakeKeyed('B', 10), MakeKeyed('B', 11)]);
      WaitForKeyedCount(lLock, lValues, 2, 2000);
      AssertLockedKeyedCount(lLock, lValues, 2);
      CheckEquals(2, FindKeyedValue(lLock, lValues, 'A'));
      CheckEquals(11, FindKeyedValue(lLock, lValues, 'B'));
    finally
      lSub := nil;
      lValues.Free;
    end;
  finally
    lLock.Free;
    {$IFDEF max_FPC}
    lBus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
  end;
end;

procedure TTestCoalesce.ZeroWindowBatchesPosts;
var
  lBus: ImaxBusAdvanced;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<TKeyed>;
  function KeyOf(const aEvent: TKeyed): TmaxString;
  begin
    Result := aEvent.Key;
  end;
  procedure Handler(const aEvent: TKeyed);
  begin
    AddKeyedValue(lLock, lValues, aEvent);
  end;
  {$ELSE}
  lValues: TList<TKeyed>;
  {$ENDIF}
  lLock: TCriticalSection;
begin
  lBus := maxBus as ImaxBusAdvanced;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  {$IFDEF max_FPC}
  lBus.EnableCoalesceOf<TKeyed>(@KeyOf, 0);
  lValues := specialize TList<TKeyed>.Create;
  lSub := lBus.Subscribe<TKeyed>(@Handler);
  {$ELSE}
  maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    0);
  lValues := TList<TKeyed>.Create;
  lSub := maxBusObj(lBus).Subscribe<TKeyed>(
    procedure(const aEvent: TKeyed)
    begin
      AddKeyedValue(lLock, lValues, aEvent);
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    lBus.Post<TKeyed>(MakeKeyed('A', 1));
    lBus.Post<TKeyed>(MakeKeyed('A', 2));
    {$ELSE}
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('A', 1));
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('A', 2));
    {$ENDIF}
    WaitForKeyedCount(lLock, lValues, 1, 1000);
    lLock.Enter;
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(2, lValues[0].Value);
    finally
      lLock.Leave;
    end;
  finally
    lSub := nil;
    lValues.Free;
    {$IFDEF max_FPC}
    lBus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
    lLock.Free;
  end;
end;

procedure TTestCoalesce.ClearPreservesCoalesceForTypedTopic;
const
  cWindowUs = 50000;
  cWaitMs = 250;
var
  lBus: ImaxBus;
  lLock: TCriticalSection;
  lValue: integer;
  lValues: TList<TKeyed>;
begin
  lBus := maxBus;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  lValues := TList<TKeyed>.Create;
  try
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
      function(const aEvent: TKeyed): TmaxString
      begin
        Result := aEvent.Key;
      end,
      cWindowUs);

    maxBusObj(lBus).Subscribe<TKeyed>(
      procedure(const aEvent: TKeyed)
      begin
        AddKeyedValue(lLock, lValues, aEvent);
      end);
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('typed', 1));
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('typed', 2));

    lBus.Clear;

    maxBusObj(lBus).Subscribe<TKeyed>(
      procedure(const aEvent: TKeyed)
      begin
        AddKeyedValue(lLock, lValues, aEvent);
      end);
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('typed', 3));
    maxBusObj(lBus).Post<TKeyed>(MakeKeyed('typed', 4));

    WaitForKeyedCount(lLock, lValues, 1, 2000);
    Sleep(cWaitMs);
    AssertLockedKeyedCount(lLock, lValues, 1);
    lValue := FindKeyedValue(lLock, lValues, 'typed');
    CheckEquals(4, lValue);
  finally
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(nil);
    lBus.Clear;
    lValues.Free;
    lLock.Free;
  end;
end;

procedure TTestCoalesce.ClearPreservesCoalesceForNamedOfTopic;
const
  cName = 'clear.coalesce.named';
  cWindowUs = 50000;
  cWaitMs = 250;
var
  lBus: ImaxBus;
  lLock: TCriticalSection;
  lValue: integer;
  lValues: TList<TKeyed>;
begin
  lBus := maxBus;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  lValues := TList<TKeyed>.Create;
  try
    maxBusObj(lBus).EnableCoalesceNamedOf<TKeyed>(cName,
      function(const aEvent: TKeyed): TmaxString
      begin
        Result := aEvent.Key;
      end,
      cWindowUs);

    maxBusObj(lBus).SubscribeNamedOf<TKeyed>(cName,
      procedure(const aEvent: TKeyed)
      begin
        AddKeyedValue(lLock, lValues, aEvent);
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostNamedOf<TKeyed>(cName, MakeKeyed('named', 1));
    maxBusObj(lBus).PostNamedOf<TKeyed>(cName, MakeKeyed('named', 2));

    lBus.Clear;

    maxBusObj(lBus).SubscribeNamedOf<TKeyed>(cName,
      procedure(const aEvent: TKeyed)
      begin
        AddKeyedValue(lLock, lValues, aEvent);
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostNamedOf<TKeyed>(cName, MakeKeyed('named', 3));
    maxBusObj(lBus).PostNamedOf<TKeyed>(cName, MakeKeyed('named', 4));

    WaitForKeyedCount(lLock, lValues, 1, 2000);
    Sleep(cWaitMs);
    AssertLockedKeyedCount(lLock, lValues, 1);
    lValue := FindKeyedValue(lLock, lValues, 'named');
    CheckEquals(4, lValue);
  finally
    maxBusObj(lBus).EnableCoalesceNamedOf<TKeyed>(cName, nil);
    lBus.Clear;
    lValues.Free;
    lLock.Free;
  end;
end;

procedure TTestCoalesce.ClearPreservesCoalesceForGuidTopic;
const
  cWindowUs = 50000;
  cWaitMs = 250;
var
  lBus: ImaxBus;
  lLock: TCriticalSection;
  lSub: ImaxSubscription;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  lValues := TList<integer>.Create;
  lSub := nil;
  try
    maxBusObj(lBus).EnableCoalesceGuidOf<IIntEvent>(
      function(const aValue: IIntEvent): TmaxString
      begin
        Result := 'guid';
      end,
      cWindowUs);
    lSub := SubscribeGuidValueCapture(lBus, lLock, lValues);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(1));
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(2));

    lBus.Clear;

    lSub := SubscribeGuidValueCapture(lBus, lLock, lValues);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(3));
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(4));

    WaitForLockedIntegerCount(lLock, lValues, 1, 2000);
    Sleep(cWaitMs);
    lLock.Enter;
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(4, lValues[0]);
    finally
      lLock.Leave;
    end;
  finally
    lSub := nil;
    maxBusObj(lBus).EnableCoalesceGuidOf<IIntEvent>(nil);
    lBus.Clear;
    lValues.Free;
    lLock.Free;
  end;
end;

{ TPostBurstThread }

constructor TPostBurstThread.Create(const aBus: ImaxBus; aCount: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fCount := aCount;
end;

procedure TPostBurstThread.Execute;
var
  i: integer;
begin
  for i := 1 to fCount do
    {$IFDEF max_FPC}
    fBus.Post<integer>(i);
  {$ELSE}
    maxBusObj(fBus).Post<integer>(i);
  {$ENDIF}
end;

{ TMetricPostThread }

constructor TMetricPostThread.Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aCount: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fStart := aStart;
  fDone := aDone;
  fCount := aCount;
end;

procedure TMetricPostThread.Execute;
var
  i: integer;
  lEvt: TMetricEvent;
begin
  if fStart.WaitFor(10000) <> wrSignaled then
  begin
    {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
    LogLine('TMetricPostThread', 'Start event timed out');
    {$ENDIF}
    fDone.SetEvent;
    Exit;
  end;
  try
    for i := 1 to fCount do
    begin
      lEvt.Value := i;
      {$IFDEF max_FPC}
      fBus.Post<TMetricEvent>(lEvt);
      {$ELSE}
      maxBusObj(fBus).Post<TMetricEvent>(lEvt);
      {$ENDIF}
    end;
  finally
    fDone.SetEvent;
  end;
end;

{ TMetricNamedTopicCreateThread }

constructor TMetricNamedTopicCreateThread.Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aCount: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fStart := aStart;
  fDone := aDone;
  fCount := aCount;
end;

procedure TMetricNamedTopicCreateThread.Execute;
var
  i: integer;
  lPolicy: TmaxQueuePolicy;
begin
  if fStart.WaitFor(10000) <> wrSignaled then
  begin
    {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
    LogLine('TMetricNamedTopicCreateThread', 'Start event timed out');
    {$ENDIF}
    fDone.SetEvent;
    Exit;
  end;
  try
    FillChar(lPolicy, SizeOf(lPolicy), 0);
    lPolicy.MaxDepth := 0;
    lPolicy.Overflow := DropNewest;
    lPolicy.DeadlineUs := 0;
    for i := 1 to fCount do
      {$IFDEF max_FPC}
      (fBus as ImaxBusQueues).SetPolicyNamed('N' + IntToStr(i), lPolicy);
      {$ELSE}
      maxBusObj(fBus).SetPolicyNamed('N' + IntToStr(i), lPolicy);
      {$ENDIF}
  finally
    fDone.SetEvent;
  end;
end;

{ TMetricReadThread }

constructor TMetricReadThread.Create(const aBus: ImaxBus; const aStart, aDone: TEvent; aIterations: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fStart := aStart;
  fDone := aDone;
  fIterations := aIterations;
end;

procedure TMetricReadThread.Execute;
var
  i: integer;
  lTotals: TmaxTopicStats;
begin
  if fStart.WaitFor(10000) <> wrSignaled then
  begin
    {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
    LogLine('TMetricReadThread', 'Start event timed out');
    {$ENDIF}
    fDone.SetEvent;
    Exit;
  end;
  try
    for i := 1 to fIterations do
    begin
      {$IFDEF max_FPC}
      lTotals := (fBus as ImaxBusMetrics).GetTotals;
      (fBus as ImaxBusMetrics).GetStatsNamed('N1');
      {$ELSE}
      lTotals := maxBusObj(fBus).GetTotals;
      maxBusObj(fBus).GetStatsFor<TMetricEvent>;
      maxBusObj(fBus).GetStatsNamed('N1');
      {$ENDIF}
      if ((i and $FF) = 0) and ((lTotals.PostsTotal and $FF) = 0) then
        Sleep(0);
    end;
  finally
    fDone.SetEvent;
  end;
end;

{ TTestMetricsConcurrent }

procedure TTestMetricsConcurrent.TotalsReadWhilePostingAndCreatingTopics; //FI:C103 Test scenario keeps thread handles/events explicit for teardown safety.
const
  cPostThreads = 4;
  cPostsPerThread = 25000;
  cCreateNamedTopics = 250;
  cReadIterations = 3000;
var
  lBus: ImaxBus;
  lStart, lReaderDone, lCreateDone: TEvent;
  lPostDone: array of TEvent;
  lPostThreads: array of TMetricPostThread;
  lReader: TMetricReadThread;
  lCreator: TMetricNamedTopicCreateThread;
  lSub: ImaxSubscription;
  lExpected: UInt64;
  lTotals: TmaxTopicStats;
  lTypedStats: TmaxTopicStats;
  i: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lReader := nil;
  lCreator := nil;

  {$IFDEF max_FPC}
  lSub := lBus.Subscribe<TMetricEvent>(
    procedure(const aValue: TMetricEvent)
    begin
    end,
    TmaxDelivery.Posting);
  {$ELSE}
  lSub := maxBusObj(lBus).Subscribe<TMetricEvent>(
    procedure(const aValue: TMetricEvent)
    begin
    end,
    TmaxDelivery.Posting);
  {$ENDIF}

  lStart := TEvent.Create(nil, True, False, '');
  lReaderDone := TEvent.Create(nil, True, False, '');
  lCreateDone := TEvent.Create(nil, True, False, '');
  try
    SetLength(lPostDone, cPostThreads);
    SetLength(lPostThreads, cPostThreads);
    for i := 0 to cPostThreads - 1 do
    begin
      lPostDone[i] := TEvent.Create(nil, True, False, '');
      lPostThreads[i] := TMetricPostThread.Create(lBus, lStart, lPostDone[i], cPostsPerThread);
      lPostThreads[i].Start;
    end;

    lReader := TMetricReadThread.Create(lBus, lStart, lReaderDone, cReadIterations);
    lReader.Start;

    lCreator := TMetricNamedTopicCreateThread.Create(lBus, lStart, lCreateDone, cCreateNamedTopics);
    lCreator.Start;

    lStart.SetEvent;

    for i := 0 to High(lPostDone) do
      Check(lPostDone[i].WaitFor(10000) = wrSignaled, 'post thread timed out');
    Check(lCreateDone.WaitFor(10000) = wrSignaled, 'creator thread timed out');
    Check(lReaderDone.WaitFor(10000) = wrSignaled, 'reader thread timed out');

    lExpected := UInt64(cPostThreads) * UInt64(cPostsPerThread);
    {$IFDEF max_FPC}
    lTypedStats := (lBus as ImaxBusMetrics).GetStatsFor<TMetricEvent>;
    lTotals := (lBus as ImaxBusMetrics).GetTotals;
    {$ELSE}
    lTypedStats := maxBusObj(lBus).GetStatsFor<TMetricEvent>;
    lTotals := maxBusObj(lBus).GetTotals;
    {$ENDIF}

    Check(lTypedStats.PostsTotal >= lExpected, 'typed PostsTotal mismatch');
    Check(lTypedStats.DeliveredTotal >= lExpected, 'typed DeliveredTotal mismatch');
    Check(lTypedStats.ExceptionsTotal = 0, 'typed ExceptionsTotal mismatch');
    Check(lTotals.PostsTotal >= lExpected, 'totals PostsTotal mismatch');
    Check(lTotals.DeliveredTotal >= lExpected, 'totals DeliveredTotal mismatch');
  finally
    if lStart <> nil then
      lStart.SetEvent; // fail-safe: unblock worker threads on early failures
    if lCreator <> nil then
      lCreator.WaitFor;
    if lReader <> nil then
      lReader.WaitFor;
    for i := 0 to High(lPostThreads) do
      if lPostThreads[i] <> nil then
        lPostThreads[i].WaitFor;

    if lCreator <> nil then
      lCreator.Free;
    if lReader <> nil then
      lReader.Free;
    for i := 0 to High(lPostThreads) do
      if lPostThreads[i] <> nil then
        lPostThreads[i].Free;
    for i := 0 to High(lPostDone) do
      if lPostDone[i] <> nil then
        lPostDone[i].Free;
    lSub := nil;
    lCreateDone.Free;
    lReaderDone.Free;
    lStart.Free;
  end;
end;

procedure TTestMetricsConcurrent.StatsReadsAreSafeDuringTopicPublish; //FI:C103 Test scenario keeps queue, metrics, and thread state explicit for race coverage.
const
  cTopicCount = 300;
  cReadIterations = 4000;
var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lQueues: ImaxBusQueues;
  lMetrics: ImaxBusMetrics;
  lPolicy: TmaxQueuePolicy;
  lStart: TEvent;
  lWriter: TThread;
  lReader: TThread;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lQueues := lBus as ImaxBusQueues;
  lMetrics := lBus as ImaxBusMetrics;

  lPolicy.MaxDepth := 8;
  lPolicy.Overflow := TmaxOverflow.DropNewest;
  lPolicy.DeadlineUs := 0;

  lStart := TEvent.Create(nil, True, False, '');
  lWriter := nil;
  lReader := nil;
  try
    lWriter := TThread.CreateAnonymousThread(
      procedure
      var
        i: integer;
        lName: string;
      begin
        if lStart.WaitFor(5000) <> wrSignaled then
          Exit;
        for i := 1 to cTopicCount do
        begin
          lName := 'metrics_race_' + IntToStr(i);
          lQueues.SetPolicyNamed(lName, lPolicy);
          lBusObj.PostNamed(lName);
        end;
      end);
    lWriter.FreeOnTerminate := False;

    lReader := TThread.CreateAnonymousThread(
      procedure
      var
        i: integer;
      begin
        if lStart.WaitFor(5000) <> wrSignaled then
          Exit;
        for i := 1 to cReadIterations do
        begin
          lMetrics.GetTotals;
          lMetrics.GetStatsNamed('metrics_race_' + IntToStr((i mod cTopicCount) + 1));
          lBusObj.GetStatsFor<TMetricEvent>;
        end;
      end);
    lReader.FreeOnTerminate := False;

    lWriter.Start;
    lReader.Start;
    lStart.SetEvent;
    lWriter.WaitFor;
    lReader.WaitFor;

    if lWriter.FatalException <> nil then
    begin
      if lWriter.FatalException is Exception then
        Check(False, 'Writer failed: ' + Exception(lWriter.FatalException).ClassName + ': ' + Exception(lWriter.FatalException).Message)
      else
        Check(False, 'Writer failed with non-Exception fatal error');
    end;

    if lReader.FatalException <> nil then
    begin
      if lReader.FatalException is Exception then
        Check(False, 'Reader failed: ' + Exception(lReader.FatalException).ClassName + ': ' + Exception(lReader.FatalException).Message)
      else
        Check(False, 'Reader failed with non-Exception fatal error');
    end;
  finally
    lStart.SetEvent;
    if lWriter <> nil then
      lWriter.Free;
    if lReader <> nil then
      lReader.Free;
    lStart.Free;
  end;
end;

procedure TTestFuzz.RandomDeliveryNoDeadlock;
const
  cTHREADS = 4;
  POSTS_PER_THREAD = 50;
var
  lBus: ImaxBus;
  lSubs: array[0..3] of ImaxSubscription;
  lThreads: array of TPostBurstThread;
  lDelivered: integer;
  i: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    TInterlocked.Increment(lDelivered);
  end;
  {$ENDIF}
begin
  Randomize;
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  lDelivered := 0;
  for i := Low(lSubs) to High(lSubs) do
  begin
    {$IFDEF max_FPC}
    lSubs[i] := lBus.Subscribe<integer>(@Handler, TmaxDelivery(random(Ord(High(TmaxDelivery)) + 1)));
    {$ELSE}
    lSubs[i] := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        TInterlocked.Increment(lDelivered);
      end,
      TmaxDelivery(random(Ord(High(TmaxDelivery)) + 1)));
    {$ENDIF}
  end;
  SetLength(lThreads, cTHREADS);
  for i := 0 to cTHREADS - 1 do
  begin
    lThreads[i] := TPostBurstThread.Create(lBus, POSTS_PER_THREAD);
    lThreads[i].start;
  end;
  for i := 0 to cTHREADS - 1 do
  begin
    lThreads[i].WaitFor;
    lThreads[i].Free;
  end;
  Sleep(500);
  CheckEquals(cTHREADS * POSTS_PER_THREAD * length(lSubs), lDelivered);
end;

{ TTestAsyncExceptions }

procedure TTestAsyncExceptions.InlineMainOnMainThreadRaisesAndForwardsHookForTyped;
var
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lError: string;
  lSub: ImaxSubscription;
  lTopic: string;
  lTypeName: string;
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lError := '';
  lTopic := '';
  lTypeName := GetTypeName(TypeInfo(integer));
  try
    maxSetAsyncErrorHandler(
      procedure(const aTopic: string; const aE: Exception)
      begin
        lTopic := aTopic;
        lError := aE.Message;
        lErrorEvent.SetEvent;
      end);

    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        raise Exception.Create('typed main boom');
      end,
      TmaxDelivery.Main);

    try
      maxBusObj(lBus).Post<integer>(7);
      Check(False, 'Expected EmaxDispatchError for inline Main typed post');
    except
      on lEx: EmaxDispatchError do
      begin
        CheckEquals(1, lEx.Inner.Count);
        CheckEquals(1, Length(lEx.Details));
        CheckEquals('typed main boom', lEx.Details[0].ExceptionMessage);
        CheckEquals(lTypeName, lEx.Details[0].Topic);
        CheckEquals(Integer(TmaxDelivery.Main), Integer(lEx.Details[0].Delivery));
      end;
    end;

    Check(lErrorEvent.WaitFor(1000) = wrSignaled, 'Inline Main typed hook not invoked');
    CheckEquals(lTypeName, lTopic);
    CheckEquals('typed main boom', lError);
  finally
    maxSetAsyncErrorHandler(nil);
    lSub := nil;
    lBus.Clear;
    lErrorEvent.Free;
  end;
end;

procedure TTestAsyncExceptions.DegradeToPostingRaisesAndForwardsHookForNamed;
var
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lError: string;
  lSub: ImaxSubscription;
  lThread: TNamedDispatchCaptureThread;
  lTopic: string;
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lError := '';
  lTopic := '';
  try
    maxSetAsyncErrorHandler(
      procedure(const aTopic: string; const aE: Exception)
      begin
        lTopic := aTopic;
        lError := aE.Message;
        lErrorEvent.SetEvent;
      end);

    lSub := lBus.SubscribeNamed('inline.main.named',
      procedure
      begin
        raise Exception.Create('named main boom');
      end,
      TmaxDelivery.Main);

    lThread := TNamedDispatchCaptureThread.Create(lBus, 'inline.main.named');
    try
      lThread.Start;
      lThread.WaitFor;
      CheckEquals('EmaxDispatchError', lThread.fRaisedClass);
      CheckEquals('named main boom', lThread.fRaisedMessage);
      CheckEquals(UpperCase('inline.main.named'), lThread.fRaisedTopic);
      CheckEquals(Integer(TmaxDelivery.Main), lThread.fDelivery);
    finally
      lThread.Free;
    end;

    Check(lErrorEvent.WaitFor(1000) = wrSignaled, 'Named Main hook not invoked');
    CheckEquals(UpperCase('inline.main.named'), lTopic);
    CheckEquals('named main boom', lError);
  finally
    maxSetAsyncErrorHandler(nil);
    lSub := nil;
    lBus.Clear;
    lErrorEvent.Free;
  end;
end;

procedure TTestAsyncExceptions.InlineBackgroundOnWorkerThreadRaisesAndForwardsHookForGuid;
var
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lError: string;
  lSub: ImaxSubscription;
  lThread: TGuidDispatchCaptureThread;
  lTopic: string;
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lError := '';
  lTopic := '';
  try
    maxSetAsyncErrorHandler(
      procedure(const aTopic: string; const aE: Exception)
      begin
        lTopic := aTopic;
        lError := aE.Message;
        lErrorEvent.SetEvent;
      end);

    lSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if aValue = nil then
          Exit;
        raise Exception.Create('guid bg boom');
      end,
      TmaxDelivery.Background);

    lThread := TGuidDispatchCaptureThread.Create(lBus, 9);
    try
      lThread.Start;
      lThread.WaitFor;
      CheckEquals('EmaxDispatchError', lThread.fRaisedClass);
      CheckEquals('guid bg boom', lThread.fRaisedMessage);
      Check(lThread.fRaisedTopic <> '', 'Expected a guid-topic detail key');
      CheckEquals(Integer(TmaxDelivery.Background), lThread.fDelivery);
    finally
      lThread.Free;
    end;

    Check(lErrorEvent.WaitFor(1000) = wrSignaled, 'Guid Background hook not invoked');
    Check(lTopic <> '', 'Expected guid async hook topic');
    CheckEquals('guid bg boom', lError);
  finally
    maxSetAsyncErrorHandler(nil);
    lSub := nil;
    lBus.Clear;
    lErrorEvent.Free;
  end;
end;

procedure TTestAsyncExceptions.InlineSchedulerPostNamedAsyncForwardsError;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lErrorEvent: TEvent;
  lTopic: string;
  lError: string;
begin
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lTopic := '';
  lError := '';
  try
    lBus := maxBus;
    lBus.Clear;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    maxSetAsyncScheduler(TInlineScheduler.Create);
    maxSetAsyncErrorHandler(
      procedure(const aTopic: string; const aE: Exception)
      begin
        lTopic := aTopic;
        lError := aE.Message;
        lErrorEvent.SetEvent;
      end);

    lBus.SubscribeNamed('inline.async.post',
      procedure
      begin
        raise Exception.Create('inline post boom');
      end,
      TmaxDelivery.Async);
    lBus.PostNamed('inline.async.post');

    Check(lErrorEvent.WaitFor(1000) = wrSignaled, 'Async error hook not invoked');
    Check(SameText('inline.async.post', lTopic));
    CheckEquals('inline post boom', lError);
  finally
    maxSetAsyncErrorHandler(nil);
    maxSetAsyncScheduler(lPrevScheduler);
    lErrorEvent.Free;
  end;
end;

procedure TTestAsyncExceptions.InlineSchedulerTryPostNamedAsyncForwardsError;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lErrorEvent: TEvent;
  lTopic: string;
  lError: string;
begin
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lTopic := '';
  lError := '';
  try
    lBus := maxBus;
    lBus.Clear;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    maxSetAsyncScheduler(TInlineScheduler.Create);
    maxSetAsyncErrorHandler(
      procedure(const aTopic: string; const aE: Exception)
      begin
        lTopic := aTopic;
        lError := aE.Message;
        lErrorEvent.SetEvent;
      end);

    lBus.SubscribeNamed('inline.async.try',
      procedure
      begin
        raise Exception.Create('inline try boom');
      end,
      TmaxDelivery.Async);
    Check(lBus.TryPostNamed('inline.async.try'));

    Check(lErrorEvent.WaitFor(1000) = wrSignaled, 'Async error hook not invoked');
    Check(SameText('inline.async.try', lTopic));
    CheckEquals('inline try boom', lError);
  finally
    maxSetAsyncErrorHandler(nil);
    maxSetAsyncScheduler(lPrevScheduler);
    lErrorEvent.Free;
  end;
end;

procedure TTestStress.OneMillionPosts;
const
  cTOPICS = 10;
  cPOSTS = 1000000;
  cModeByTopic: array[0..cTOPICS - 1] of TmaxDelivery = (
    TmaxDelivery.Posting,
    TmaxDelivery.Posting,
    TmaxDelivery.Posting,
    TmaxDelivery.Async,
    TmaxDelivery.Async,
    TmaxDelivery.Async,
    TmaxDelivery.Background,
    TmaxDelivery.Background,
    TmaxDelivery.Main,
    TmaxDelivery.Main
  );
var
  lBus: ImaxBus;
  lPrevSched: IEventNexusScheduler;
  lNames: array[0..cTOPICS - 1] of TmaxString;
  lSubs: array[0..cTOPICS - 1] of ImaxSubscription;
  lHits: integer;
  i: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    if aValue = -1 then
      Exit;
    TInterlocked.Increment(lHits);
  end;
  {$ENDIF}
begin
  lPrevSched := maxGetAsyncScheduler;
  maxSetAsyncScheduler(TInlineScheduler.Create);
  try
    lBus := maxBus;
    lBus.Clear;
    lHits := 0;

    for i := 0 to cTOPICS - 1 do
      lNames[i] := TmaxString('stress' + IntToStr(i));

    for i := 0 to cTOPICS - 1 do
    begin
      {$IFDEF max_FPC}
      lSubs[i] := lBus.SubscribeNamedOf<integer>(lNames[i], @Handler, cModeByTopic[i]);
      {$ELSE}
      lSubs[i] := maxBusObj(lBus).SubscribeNamedOf<integer>(lNames[i],
        procedure(const aValue: integer)
        begin
          if aValue = -1 then
            Exit;
          TInterlocked.Increment(lHits);
        end,
        cModeByTopic[i]);
      {$ENDIF}
    end;

    for i := 1 to cPOSTS do
    begin
      {$IFDEF max_FPC}
      lBus.PostNamedOf<integer>(lNames[i mod cTOPICS], i);
      {$ELSE}
      maxBusObj(lBus).PostNamedOf<integer>(lNames[i mod cTOPICS], i);
      {$ENDIF}
    end;

    CheckEquals(cPOSTS, lHits);
  finally
    for i := 0 to cTOPICS - 1 do
      lSubs[i] := nil;
    maxSetAsyncScheduler(lPrevSched);
  end;
end;

procedure TTestStress.StressSuiteSwitchRunsSuccessfully;
var
  lExitCode: Cardinal;
begin
  lExitCode := RunProcessAndGetExitCode(ParamStr(0), '--stress-suite');
  CheckEquals(0, Integer(lExitCode),
    Format('Stress suite switch reported exit code %d', [lExitCode]));
end;

{ TIntEvent }

constructor TIntEvent.Create(aValue: integer);
begin
  inherited Create;
  fVal := aValue;
end;

function TIntEvent.GetValue: integer;
begin
  Result := fVal;
end;

{ TPostResultGuidEvent }

constructor TPostResultGuidEvent.Create(aValue: integer);
begin
  inherited Create;
  fVal := aValue;
end;

function TPostResultGuidEvent.GetValue: integer;
begin
  Result := fVal;
end;

{ TQueueMetricsGuidEvent }

constructor TQueueMetricsGuidEvent.Create(aValue: integer);
begin
  inherited Create;
  fVal := aValue;
end;

function TQueueMetricsGuidEvent.GetValue: integer;
begin
  Result := fVal;
end;

{ TQueuePresetGuidEvent }

constructor TQueuePresetGuidEvent.Create(aValue: integer);
begin
  inherited Create;
  fVal := aValue;
end;

function TQueuePresetGuidEvent.GetValue: integer;
begin
  Result := fVal;
end;

procedure TTestGuidTopics.GuidPublishDelivers;
var
  lBus: ImaxBus;
  lGot: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    lGot := aEvt.GetValue;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lGot := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeGuidOf<IIntEvent>(@Handler);
  {$ELSE}
  maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      lGot := aEvt.GetValue;
    end);
  {$ENDIF}
  maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(5));
  Sleep(10);
  CheckEquals(5, lGot);
end;

procedure TTestGuidTopics.StickyGuidDeliversLast;
var
  lBus: ImaxBus;
  lGot: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    lGot := aEvt.GetValue;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_FPC}
  lBus.EnableSticky<IIntEvent>(True);
  lBus.PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  {$ELSE}
  maxBusObj(lBus).EnableSticky<IIntEvent>(True);
  maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  {$ENDIF}
  lGot := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeGuidOf<IIntEvent>(@Handler);
  {$ELSE}
  maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      lGot := aEvt.GetValue;
    end);
  {$ENDIF}
  Sleep(10);
  CheckEquals(7, lGot);
  {$IFDEF max_FPC}
  lBus.EnableSticky<IIntEvent>(False);
  {$ELSE}
  maxBusObj(lBus).EnableSticky<IIntEvent>(False);
  {$ENDIF}
end;

procedure TTestGuidTopics.CoalesceGuidDeliversLatest;
var
  lBus: ImaxBus;
  {$IFDEF max_FPC}
  lValues: specialize TList<integer>;
  {$ELSE}
  lValues: TList<integer>;
  {$ENDIF}
  lLock: TCriticalSection;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    lLock.Enter;
    try
      lValues.Add(aEvt.GetValue);
      Inc(lCount);
    finally
      lLock.Leave;
    end;
  end;

  function KeyOf(const aEvt: IIntEvent): TmaxString;
  begin
    Result := 'k';
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  {$IFDEF max_FPC}
  lValues := specialize TList<integer>.Create;
  {$ELSE}
  lValues := TList<integer>.Create;
  {$ENDIF}
  try
    lCount := 0;
    {$IFDEF max_FPC}
    (lBus as ImaxBusAdvanced).EnableCoalesceGuidOf<IIntEvent>(@KeyOf, 0);
    lBus.SubscribeGuidOf<IIntEvent>(@Handler);
    {$ELSE}
    maxBusObj(lBus).EnableCoalesceGuidOf<IIntEvent>(
      function(const aEvt: IIntEvent): TmaxString
      begin
        Result := 'k';
      end,
      10000);
    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aEvt: IIntEvent)
      begin
        lLock.Enter;
        try
          lValues.Add(aEvt.GetValue);
          Inc(lCount);
        finally
          lLock.Leave;
        end;
      end);
    {$ENDIF}
    PostGuidValues(lBus, [1, 2]);
    Sleep(25);
    AssertLockedIntegerState(lLock, lValues, 1, 2);
  finally
    {$IFDEF max_FPC}
    (lBus as ImaxBusAdvanced).EnableCoalesceGuidOf<IIntEvent>(nil);
    {$ELSE}
    maxBusObj(lBus).EnableCoalesceGuidOf<IIntEvent>(nil);
    {$ENDIF}
    lValues.Free;
    lLock.Free;
  end;
end;

procedure TTestGuidTopics.QueuePolicyAndMetricsGuid;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lMetrics: ImaxBusMetrics;
  lPolicy: TmaxQueuePolicy;
  t: TThread;
  ok: boolean;
  lCount: integer;
  lStats: TmaxTopicStats;
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropNewest;
  lPolicy.DeadlineUs := 0;
  maxBusObj(lQueues).SetPolicyGuidOf<IQueueMetricsGuidEvent>(lPolicy);
  lCount := 0;
  maxBusObj(lBus).SubscribeGuidOf<IQueueMetricsGuidEvent>(
    procedure(const aEvt: IQueueMetricsGuidEvent)
    begin
      Sleep(100);
      Inc(lCount);
    end);
  t := TThread.CreateAnonymousThread(
    procedure
    begin
      maxBusObj(lBus).PostGuidOf<IQueueMetricsGuidEvent>(TQueueMetricsGuidEvent.Create(1));
    end);
  t.FreeOnTerminate := False;
  try
    t.start;
    Sleep(10);
    ok := maxBusObj(lBus).TryPostGuidOf<IQueueMetricsGuidEvent>(TQueueMetricsGuidEvent.Create(2));
    Check(ok);
    ok := maxBusObj(lBus).TryPostGuidOf<IQueueMetricsGuidEvent>(TQueueMetricsGuidEvent.Create(3));
    Check(not ok);
    t.WaitFor;
    CheckEquals(2, lCount);
    lMetrics := lBus as ImaxBusMetrics;
    lStats := maxBusObj(lMetrics).GetStatsGuidOf<IQueueMetricsGuidEvent>;
    CheckEquals(3, lStats.PostsTotal);
    CheckEquals(2, lStats.DeliveredTotal);
    CheckEquals(1, lStats.DroppedTotal);
  finally
    t.Free;
  end;
end;

procedure TTestMainThreadPolicy.StrictRaisesOffMain;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  t: TMainPolicyPostThread;
  lHandled: boolean;
  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    lHandled := True;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.Strict);
  lHandled := False;
  try
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@Handler, TmaxDelivery.Main);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lHandled := True;
      end,
      TmaxDelivery.Main);
    {$ENDIF}
    t := TMainPolicyPostThread.Create(lBus, 1);
    try
      t.start;
      t.WaitFor;
      Check(t.fRaised);
      CheckEquals('EmaxMainThreadRequired', t.fRaisedClass);
      Check(not lHandled);
    finally
      t.Free;
    end;
  finally
    lSub := nil;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  end;
end;

procedure TTestMainThreadPolicy.DegradeToPostingRunsInline;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  t: TMainPolicyPostThread;
  lDone: TEvent;
  lHandledThreadId: TThreadID;
  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    lHandledThreadId := TThread.CurrentThread.ThreadID;
    lDone.SetEvent;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
  lHandledThreadId := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@Handler, TmaxDelivery.Main);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lHandledThreadId := TThread.CurrentThread.ThreadID;
        lDone.SetEvent;
      end,
      TmaxDelivery.Main);
    {$ENDIF}
    t := TMainPolicyPostThread.Create(lBus, 1);
    try
      t.start;
      Check(lDone.WaitFor(2000) = wrSignaled);
      Check(not t.fRaised);
      CheckEquals(t.fThreadId, lHandledThreadId);
      t.WaitFor;
    finally
      t.Free;
    end;
  finally
    lSub := nil;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    lDone.Free;
  end;
end;

procedure TTestMainThreadPolicy.DegradeToAsyncRunsOffPostingThread;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  t: TMainPolicyPostThread;
  lDone: TEvent;
  lHandledThreadId: TThreadID;
  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    lHandledThreadId := TThread.CurrentThread.ThreadID;
    lDone.SetEvent;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToAsync);
  lHandledThreadId := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@Handler, TmaxDelivery.Main);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lHandledThreadId := TThread.CurrentThread.ThreadID;
        lDone.SetEvent;
      end,
      TmaxDelivery.Main);
    {$ENDIF}
    t := TMainPolicyPostThread.Create(lBus, 1);
    try
      t.start;
      t.WaitFor;
      Check(not t.fRaised);
      Check(lDone.WaitFor(2000) = wrSignaled);
      Check(t.fThreadId <> lHandledThreadId);
    finally
      t.Free;
    end;
  finally
    lSub := nil;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    lDone.Free;
  end;
end;

procedure TTestMainThreadPolicy.ClearDoesNotRebindMainThreadIdentity;
var
  lBus: ImaxBus;
  lSubBeforeClear: ImaxSubscription;
  lSubAfterClear: ImaxSubscription;
  lCleared: TEvent;
  lGoPost: TEvent;
  lWorker: TThread;
  lRaisedBefore: boolean;
  lRaisedAfter: boolean;
  lRaisedClassBefore: string;
  lRaisedClassAfter: string;
  lGoSignaled: boolean;
  lHandled: boolean;
begin
  lBus := maxBus;
  lBus.Clear;
  maxSetMainThreadPolicy(TmaxMainThreadPolicy.Strict);
  lSubBeforeClear := nil;
  lSubAfterClear := nil;
  lWorker := nil;
  lRaisedBefore := False;
  lRaisedAfter := False;
  lRaisedClassBefore := '';
  lRaisedClassAfter := '';
  lGoSignaled := False;
  lHandled := False;
  lCleared := TEvent.Create(nil, True, False, '');
  lGoPost := TEvent.Create(nil, True, False, '');
  try
    lWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          maxBusObj(lBus).Post<integer>(1);
        except
          on lException: Exception do
          begin
            lRaisedBefore := True;
            lRaisedClassBefore := lException.ClassName;
          end;
        end;

        lBus.Clear;
        lCleared.SetEvent;
        lGoSignaled := lGoPost.WaitFor(5000) = wrSignaled;
        try
          maxBusObj(lBus).Post<integer>(2);
        except
          on lException: Exception do
          begin
            lRaisedAfter := True;
            lRaisedClassAfter := lException.ClassName;
          end;
        end;
      end);
    lWorker.FreeOnTerminate := False;

    lSubBeforeClear := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lHandled := True;
      end,
      TmaxDelivery.Main);

    lWorker.Start;
    Check(lCleared.WaitFor(5000) = wrSignaled, 'worker clear timed out');

    // Re-subscribe after worker Clear so posting still needs Main dispatch validation.
    lSubBeforeClear := nil;
    lSubAfterClear := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lHandled := True;
      end,
      TmaxDelivery.Main);

    // Verify we really have an active Main subscription after Clear.
    lHandled := False;
    maxBusObj(lBus).Post<integer>(99);
    Check(lHandled, 'Expected active Main subscription after worker Clear');
    lHandled := False;

    lGoPost.SetEvent;
    lWorker.WaitFor;

    Check(lGoSignaled, 'Worker did not receive post-go signal');
    CheckEquals(Ord(lRaisedBefore), Ord(lRaisedAfter), 'Clear must not change worker/main-thread classification');
    if lRaisedBefore then
    begin
      CheckEquals('EmaxMainThreadRequired', lRaisedClassBefore);
      CheckEquals('EmaxMainThreadRequired', lRaisedClassAfter);
    end;
    if lRaisedAfter then
      Check(not lHandled, 'Main handler must not execute on worker thread in Strict mode');
  finally
    if lWorker <> nil then
      lWorker.Free;
    lSubAfterClear := nil;
    lSubBeforeClear := nil;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    lGoPost.Free;
    lCleared.Free;
  end;
end;

procedure TTestHighWaterReset.ResetsAfterDraining;
var
  lBus: ImaxBus;
  lName: TmaxString;
  lStarted: TEvent;
  lRelease: TEvent;
  lHighEvent: TEvent;
  lResetEvent: TEvent;
  lSeenHigh: integer;
  lSeenReset: integer;
  lSub: ImaxSubscription;
  t: TNamedPostThread;
  lMetricPrefix: string;
  i: integer;

  {$IFDEF max_FPC}
  procedure Sample(const aName: string; const aStats: TmaxTopicStats);
  begin
    if Copy(aName, 1, Length(lMetricPrefix)) <> lMetricPrefix then
      Exit;
    if (lSeenHigh = 0) and (aStats.CurrentQueueDepth > 10000) then
    begin
      TInterlocked.Exchange(lSeenHigh, 1);
      lHighEvent.SetEvent;
    end;
    if (lSeenHigh <> 0) and (lSeenReset = 0) and (aStats.CurrentQueueDepth <= 5000) then
    begin
      TInterlocked.Exchange(lSeenReset, 1);
      lResetEvent.SetEvent;
    end;
  end;

  procedure Handler(const aValue: integer);
  begin
    if aValue = 1 then
    begin
      lStarted.SetEvent;
      lRelease.WaitFor(5000);
      Exit;
    end;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'highwater';
  lMetricPrefix := 'HIGHWATER:';
  lSeenHigh := 0;
  lSeenReset := 0;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lHighEvent := TEvent.Create(nil, True, False, '');
  lResetEvent := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    maxSetMetricCallback(@Sample);
    {$ELSE}
    maxSetMetricCallback(
      procedure(const aName: string; const aStats: TmaxTopicStats)
      begin
        if Copy(aName, 1, Length(lMetricPrefix)) <> lMetricPrefix then
          Exit;
        if (lSeenHigh = 0) and (aStats.CurrentQueueDepth > 10000) then
        begin
          TInterlocked.Exchange(lSeenHigh, 1);
          lHighEvent.SetEvent;
        end;
        if (lSeenHigh <> 0) and (lSeenReset = 0) and (aStats.CurrentQueueDepth <= 5000) then
        begin
          TInterlocked.Exchange(lSeenReset, 1);
          lResetEvent.SetEvent;
        end;
      end);
    {$ENDIF}

    {$IFDEF max_FPC}
    lSub := lBus.SubscribeNamedOf<integer>(lName, @Handler, TmaxDelivery.Posting);
    {$ELSE}
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
          Exit;
        end;
      end,
      TmaxDelivery.Posting);
    {$ENDIF}

    t := TNamedPostThread.Create(lBus, lName, 1);
    try
      t.start;
      Check(lStarted.WaitFor(2000) = wrSignaled);

      for i := 2 to 12050 do
        {$IFDEF max_FPC}
        lBus.TryPostNamedOf<integer>(lName, i);
        {$ELSE}
        maxBusObj(lBus).TryPostNamedOf<integer>(lName, i);
        {$ENDIF}

      Check(lHighEvent.WaitFor(2000) = wrSignaled);
      lRelease.SetEvent;
      Check(lResetEvent.WaitFor(5000) = wrSignaled);

      t.WaitFor;
    finally
      t.Free;
    end;
  finally
    maxSetMetricCallback(nil);
    lSub := nil;
    lResetEvent.Free;
    lHighEvent.Free;
    lRelease.Free;
    lStarted.Free;
  end;
end;

{$IFDEF max_DELPHI}
procedure TTestAutoSubscribe.RegistersTypedNamedAndInherited;
var
  lTarget: TAutoSubDerived;
  lBus: ImaxBus;
  lBusObj: TmaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lTarget := TAutoSubDerived.Create;
  try
    AutoSubscribe(lTarget);
    lBusObj.Post<integer>(7);
    lBusObj.PostNamed('ping');
    lBusObj.PostNamedOf<integer>('data', 88);
    CheckEquals(1, lTarget.IntHits);
    CheckEquals(7, lTarget.LastInt);
    CheckEquals(1, lTarget.PingHits);
    CheckEquals(1, lTarget.DataHits);
    CheckEquals(88, lTarget.LastData);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestAutoSubscribe.AutoUnsubscribeClearsHandlers;
var
  lTarget: TAutoSubDerived;
  lBus: ImaxBus;
  lBusObj: TmaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lTarget := TAutoSubDerived.Create;
  try
    AutoSubscribe(lTarget);
    AutoUnsubscribe(lTarget);
    lTarget.IntHits := 0;
    lTarget.LastInt := 0;
    lTarget.PingHits := 0;
    lTarget.DataHits := 0;
    lTarget.LastData := 0;
    lBusObj.Post<integer>(3);
    lBusObj.PostNamed('ping');
    lBusObj.PostNamedOf<integer>('data', 12);
    CheckEquals(0, lTarget.IntHits);
    CheckEquals(0, lTarget.PingHits);
    CheckEquals(0, lTarget.DataHits);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestAutoSubscribe.UnsubscribeAllForClearsAutoSubscriptions;
var
  lTarget: TAutoSubDerived;
  lBus: ImaxBus;
  lBusObj: TmaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  lBusObj := maxBusObj(lBus);
  lTarget := TAutoSubDerived.Create;
  try
    AutoSubscribe(lTarget);

    lBusObj.Post<integer>(7);
    lBusObj.PostNamed('ping');
    lBusObj.PostNamedOf<integer>('data', 88);
    CheckEquals(1, lTarget.IntHits);
    CheckEquals(1, lTarget.PingHits);
    CheckEquals(1, lTarget.DataHits);

    lBus.UnsubscribeAllFor(lTarget);
    lBusObj.Post<integer>(7);
    lBusObj.PostNamed('ping');
    lBusObj.PostNamedOf<integer>('data', 88);
    CheckEquals(1, lTarget.IntHits);
    CheckEquals(1, lTarget.PingHits);
    CheckEquals(1, lTarget.DataHits);

    AutoUnsubscribe(lTarget);
    lTarget.IntHits := 0;
    lTarget.PingHits := 0;
    lTarget.DataHits := 0;
    AutoSubscribe(lTarget);

    lBusObj.Post<integer>(7);
    lBusObj.PostNamed('ping');
    lBusObj.PostNamedOf<integer>('data', 88);
    CheckEquals(1, lTarget.IntHits);
    CheckEquals(1, lTarget.PingHits);
    CheckEquals(1, lTarget.DataHits);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestAutoSubscribe.InvalidAttributedFormsRaise;
var
  lAbstract: TAbstractAutoSub;
  lInvalid: TObject;
  lRaised: boolean;
begin
  lAbstract := nil;
  try
    maxBus.Clear;

    lInvalid := TBadAutoSub.Create;
    try
      lRaised := False;
      try
        AutoSubscribe(lInvalid);
      except
        on E: EmaxInvalidSubscription do
          lRaised := True;
      end;
      Check(lRaised, 'Expected multi-parameter attributed method to raise EmaxInvalidSubscription');
    finally
      AutoUnsubscribe(lInvalid);
      lInvalid.Free;
    end;

    lInvalid := TBadAutoSubClassMethod.Create;
    try
      lRaised := False;
      try
        AutoSubscribe(lInvalid);
      except
        on E: EmaxInvalidSubscription do
          lRaised := True;
      end;
      Check(lRaised, 'Expected attributed class method to raise EmaxInvalidSubscription');
    finally
      AutoUnsubscribe(lInvalid);
      lInvalid.Free;
    end;

    lInvalid := TBadAutoSubCtor.Create;
    try
      lRaised := False;
      try
        AutoSubscribe(lInvalid);
      except
        on E: EmaxInvalidSubscription do
          lRaised := True;
      end;
      Check(lRaised, 'Expected attributed constructor to raise EmaxInvalidSubscription');
    finally
      AutoUnsubscribe(lInvalid);
      lInvalid.Free;
    end;

    lInvalid := TBadAutoSubDtor.Create;
    try
      lRaised := False;
      try
        AutoSubscribe(lInvalid);
      except
        on E: EmaxInvalidSubscription do
          lRaised := True;
      end;
      Check(lRaised, 'Expected attributed destructor to raise EmaxInvalidSubscription');
    finally
      AutoUnsubscribe(lInvalid);
      lInvalid.Free;
    end;

    lInvalid := TRepeatedAutoSub.Create;
    try
      lRaised := False;
      try
        AutoSubscribe(lInvalid);
      except
        on E: EmaxInvalidSubscription do
          lRaised := True;
      end;
      Check(lRaised, 'Expected repeated maxSubscribe attributes to raise EmaxInvalidSubscription');
    finally
      AutoUnsubscribe(lInvalid);
      lInvalid.Free;
    end;

    lAbstract := TAbstractAutoSub(TAbstractAutoSub.NewInstance);
    lRaised := False;
    try
      AutoSubscribe(lAbstract);
    except
      on E: EmaxInvalidSubscription do
        lRaised := True;
    end;
    Check(lRaised, 'Expected abstract attributed method to raise EmaxInvalidSubscription');
  finally
    AutoUnsubscribe(lAbstract);
    if lAbstract <> nil then
      lAbstract.FreeInstance;
    maxBus.Clear;
  end;
end;

procedure TTestAutoSubscribe.NamedNoArgBindsCorrectMethod;
var
  lBusObj: TmaxBus;
  lTarget: TAutoSubNamedNoArg;
begin
  lBusObj := maxBusObj;
  lBusObj.Clear;
  lTarget := TAutoSubNamedNoArg.Create;
  try
    AutoSubscribe(lTarget);

    lBusObj.PostNamed('first');
    lBusObj.PostNamed('second');
    lBusObj.PostNamed('first');

    CheckEquals(2, lTarget.FirstHits);
    CheckEquals(1, lTarget.SecondHits);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBusObj.Clear;
  end;
end;

procedure TTestAutoSubscribe.GuidOneParamBindsAndUnsubscribes;
var
  lBusObj: TmaxBus;
  lTarget: TAutoSubGuid;
begin
  lBusObj := maxBusObj;
  lBusObj.Clear;
  lTarget := TAutoSubGuid.Create;
  try
    AutoSubscribe(lTarget);

    lBusObj.PostGuidOf<IIntEvent>(TIntEvent.Create(42));
    CheckEquals(1, lTarget.GuidHits);
    CheckEquals(42, lTarget.LastGuidValue);

    AutoUnsubscribe(lTarget);
    lBusObj.PostGuidOf<IIntEvent>(TIntEvent.Create(99));
    CheckEquals(1, lTarget.GuidHits);
    CheckEquals(42, lTarget.LastGuidValue);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBusObj.Clear;
  end;
end;
{$ENDIF}

{ TPostThread }

constructor TPostThread.Create(const aBus: ImaxBus; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fValue := aValue;
end;

procedure TPostThread.Execute;
begin
  {$IFDEF max_FPC}
  fBus.TryPost<integer>(fValue);
  {$ELSE}
  maxBusObj(fBus).TryPost<integer>(fValue);
  {$ENDIF}
end;

{ TMainPolicyPostThread }

constructor TMainPolicyPostThread.Create(const aBus: ImaxBus; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fValue := aValue;
  fThreadId := 0;
  fRaised := False;
  fRaisedClass := '';
end;

procedure TMainPolicyPostThread.Execute;
begin
  fThreadId := TThread.CurrentThread.ThreadID;
  try
    {$IFDEF max_FPC}
    fBus.Post<integer>(fValue);
    {$ELSE}
    maxBusObj(fBus).Post<integer>(fValue);
    {$ENDIF}
  except
    on E: Exception do
    begin
      fRaised := True;
      fRaisedClass := E.ClassName;
    end;
  end;
end;

{ TNamedDispatchCaptureThread }

constructor TNamedDispatchCaptureThread.Create(const aBus: ImaxBus; const aTopicName: TmaxString);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fDelivery := -1;
  fRaisedClass := '';
  fRaisedMessage := '';
  fRaisedTopic := '';
  fTopicName := aTopicName;
end;

procedure TNamedDispatchCaptureThread.Execute;
begin
  try
    fBus.PostNamed(fTopicName);
  except
    on lEx: EmaxDispatchError do
    begin
      fRaisedClass := lEx.ClassName;
      if Length(lEx.Details) > 0 then
      begin
        fRaisedMessage := lEx.Details[0].ExceptionMessage;
        fRaisedTopic := lEx.Details[0].Topic;
        fDelivery := Integer(lEx.Details[0].Delivery);
      end;
    end;
  end;
end;

{ TGuidDispatchCaptureThread }

constructor TGuidDispatchCaptureThread.Create(const aBus: ImaxBus; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fDelivery := -1;
  fRaisedClass := '';
  fRaisedMessage := '';
  fRaisedTopic := '';
  fValue := aValue;
end;

procedure TGuidDispatchCaptureThread.Execute;
begin
  try
    maxBusObj(fBus).PostGuidOf<IIntEvent>(TIntEvent.Create(fValue));
  except
    on lEx: EmaxDispatchError do
    begin
      fRaisedClass := lEx.ClassName;
      if Length(lEx.Details) > 0 then
      begin
        fRaisedMessage := lEx.Details[0].ExceptionMessage;
        fRaisedTopic := lEx.Details[0].Topic;
        fDelivery := Integer(lEx.Details[0].Delivery);
      end;
    end;
  end;
end;

procedure TTestMetrics.CountsPostsAndDelivered;
var
  lBus: ImaxBus;
  lMetrics: ImaxBusMetrics;
  lStats: TmaxTopicStats;
  lGot: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    lGot := aValue;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lGot := 0;
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      lGot := aValue;
    end);
  {$ENDIF}
  maxBusObj(lBus).Post<integer>(1);
  lMetrics := lBus as ImaxBusMetrics;
  lStats := maxBusObj(lMetrics).GetStatsFor<integer>;
  CheckEquals(1, lStats.PostsTotal);
  CheckEquals(1, lStats.DeliveredTotal);
  CheckEquals(0, lStats.DroppedTotal);
  CheckEquals(1, lGot);
end;

procedure TTestMetrics.CountsDropped;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
  lThread: TPostThread;
  lStats: TmaxTopicStats;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropNewest;
  lPolicy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  {$ELSE}
  maxBusObj(lQueues).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  lCount := 0;
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(lCount);
    end);
  {$ENDIF}
  lThread := TPostThread.Create(lBus, 1);
  try
    lThread.start;
    Sleep(10);
    {$IFDEF max_FPC}
    Check(lBus.TryPost<integer>(2));
    Check(not lBus.TryPost<integer>(3));
    {$ELSE}
    Check(maxBusObj(lBus).TryPost<integer>(2));
    Check(not maxBusObj(lBus).TryPost<integer>(3));
    {$ENDIF}
    lThread.WaitFor;
  finally
    lThread.Free;
  end;
  {$IFDEF max_FPC}
  lStats := (lBus as ImaxBusMetrics).GetStatsFor<integer>;
  {$ELSE}
  lStats := maxBusObj(lBus as ImaxBusMetrics).GetStatsFor<integer>;
  {$ENDIF}
  CheckEquals(3, lStats.PostsTotal);
  CheckEquals(2, lStats.DeliveredTotal);
  CheckEquals(1, lStats.DroppedTotal);
end;

procedure TTestMetrics.CountsExceptions;
var
  lBus: ImaxBus;
  lMetrics: ImaxBusMetrics;
  lStats: TmaxTopicStats;

  {$IFDEF max_FPC}
  procedure Failer(const aValue: integer);
  begin
    raise Exception.Create('boom');
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Failer);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('boom');
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    lBus.Post<integer>(1);
    {$ELSE}
    maxBusObj(lBus).Post<integer>(1);
    {$ENDIF}
  except
    on EmaxDispatchError do ;
  end;
  lMetrics := lBus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  lStats := lMetrics.GetStatsFor<integer>;
  {$ELSE}
  lStats := maxBusObj(lMetrics).GetStatsFor<integer>;
  {$ENDIF}
  CheckEquals(1, lStats.ExceptionsTotal);
end;

procedure TTestMetricsThrottling.ThrottlesMetricCallback;
var
  lBus: ImaxBus;
  lName: TmaxString;
  lSub: ImaxSubscription;
  lHits: integer;

  {$IFDEF max_FPC}
  procedure Sample(const aName: string; const aStats: TmaxTopicStats);
  begin
    if Copy(aName, 1, 9) <> 'THROTTLE:' then
      Exit;
    TInterlocked.Increment(lHits);
  end;

  procedure Handler(const aValue: integer);
  begin
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'throttle';
  lSub := nil;
  lHits := 0;

  maxSetMetricSampleInterval(60000);
  try
    {$IFDEF max_FPC}
    maxSetMetricCallback(@Sample);
    lSub := lBus.SubscribeNamedOf<integer>(lName, @Handler, TmaxDelivery.Posting);
    lBus.PostNamedOf<integer>(lName, 1);
    lBus.PostNamedOf<integer>(lName, 2);
    lBus.PostNamedOf<integer>(lName, 3);
    {$ELSE}
    maxSetMetricCallback(
      procedure(const aName: string; const aStats: TmaxTopicStats)
      begin
        if Copy(aName, 1, 9) <> 'THROTTLE:' then
          Exit;
        TInterlocked.Increment(lHits);
      end);
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 1);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 2);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 3);
    {$ENDIF}

    CheckEquals(1, lHits);
    maxSetMetricSampleInterval(0);

    {$IFDEF max_FPC}
    lBus.PostNamedOf<integer>(lName, 4);
    {$ELSE}
    maxBusObj(lBus).PostNamedOf<integer>(lName, 4);
    {$ENDIF}
    Check(lHits >= 3);
  finally
    maxSetMetricCallback(nil);
    maxSetMetricSampleInterval(1000);
    lSub := nil;
  end;
end;

procedure TTestMetricsCallbackTotals.MetricCallbackReceivesSnapshots;
var
  lBus: ImaxBus;
  lTypedName: string;
  lNamedTopic: TmaxString;
  lNamedMetric: string;
  lGuidMetric: string;
  lTypedSeen: boolean;
  lNamedSeen: boolean;
  lGuidSeen: boolean;
  lTypedStats: TmaxTopicStats;
  lNamedStats: TmaxTopicStats;
  lGuidStats: TmaxTopicStats;
  lSubTyped: ImaxSubscription;
  lSubNamed: ImaxSubscription;
  lSubGuid: ImaxSubscription;
  lEvt: TMetricEvent;

  {$IFDEF max_FPC}
  procedure Sample(const aName: string; const aStats: TmaxTopicStats);
  begin
    if SameText(aName, lTypedName) then
    begin
      lTypedSeen := True;
      lTypedStats := aStats;
      Exit;
    end;
    if SameText(aName, lNamedMetric) then
    begin
      lNamedSeen := True;
      lNamedStats := aStats;
      Exit;
    end;
    if SameText(aName, lGuidMetric) then
    begin
      lGuidSeen := True;
      lGuidStats := aStats;
      Exit;
    end;
  end;

  procedure HandleTyped(const aValue: TMetricEvent);
  begin
    if aValue.Value = -1 then
      Exit;
  end;

  procedure HandleNamed;
  begin
  end;

  procedure HandleGuid(const aValue: IIntEvent);
  begin
    if aValue = nil then
      Exit;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lTypedName := GetTypeName(TypeInfo(TMetricEvent));
  lNamedTopic := 'metrics_named';
  lNamedMetric := UpperCase(UnicodeString(lNamedTopic));
  lGuidMetric := GuidToString(GetTypeData(TypeInfo(IIntEvent))^.Guid);
  lTypedSeen := False;
  lNamedSeen := False;
  lGuidSeen := False;
  lTypedStats := Default(TmaxTopicStats);
  lNamedStats := Default(TmaxTopicStats);
  lGuidStats := Default(TmaxTopicStats);
  lSubTyped := nil;
  lSubNamed := nil;
  lSubGuid := nil;

  maxSetMetricSampleInterval(0);
  try
    {$IFDEF max_FPC}
    maxSetMetricCallback(@Sample);
    {$ELSE}
    maxSetMetricCallback(
      procedure(const aName: string; const aStats: TmaxTopicStats)
      begin
        if SameText(aName, lTypedName) then
        begin
          lTypedSeen := True;
          lTypedStats := aStats;
          Exit;
        end;
        if SameText(aName, lNamedMetric) then
        begin
          lNamedSeen := True;
          lNamedStats := aStats;
          Exit;
        end;
        if SameText(aName, lGuidMetric) then
        begin
          lGuidSeen := True;
          lGuidStats := aStats;
          Exit;
        end;
      end);
    {$ENDIF}

    {$IFDEF max_FPC}
    lSubTyped := lBus.Subscribe<TMetricEvent>(@HandleTyped, TmaxDelivery.Posting);
    lSubNamed := lBus.SubscribeNamed(lNamedTopic, @HandleNamed, TmaxDelivery.Posting);
    lSubGuid := lBus.SubscribeGuidOf<IIntEvent>(@HandleGuid, TmaxDelivery.Posting);
    lEvt := Default(TMetricEvent);
    lEvt.Value := 1;
    lBus.Post<TMetricEvent>(lEvt);
    lBus.PostNamed(lNamedTopic);
    lBus.PostGuidOf<IIntEvent>(TIntEvent.Create(1));
    {$ELSE}
    lSubTyped := maxBusObj(lBus).Subscribe<TMetricEvent>(
      procedure(const aValue: TMetricEvent)
      begin
        if aValue.Value = -1 then
          Exit;
      end,
      TmaxDelivery.Posting);
    lSubNamed := lBus.SubscribeNamed(lNamedTopic,
      procedure
      begin
      end,
      TmaxDelivery.Posting);
    lSubGuid := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if aValue = nil then
          Exit;
      end,
      TmaxDelivery.Posting);
    lEvt := Default(TMetricEvent);
    lEvt.Value := 1;
    maxBusObj(lBus).Post<TMetricEvent>(lEvt);
    lBus.PostNamed(lNamedTopic);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(1));
    {$ENDIF}

    Check(lTypedSeen);
    Check(lNamedSeen);
    Check(lGuidSeen);
    Check(lTypedStats.PostsTotal >= 1);
    Check(lTypedStats.DeliveredTotal >= 1);
    Check(lNamedStats.PostsTotal >= 1);
    Check(lNamedStats.DeliveredTotal >= 1);
    Check(lGuidStats.PostsTotal >= 1);
    Check(lGuidStats.DeliveredTotal >= 1);
  finally
    maxSetMetricCallback(nil);
    maxSetMetricSampleInterval(1000);
    lSubGuid := nil;
    lSubNamed := nil;
    lSubTyped := nil;
  end;
end;

procedure TTestMetricsCallbackTotals.GetTotalsAggregates;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lMetrics: ImaxBusMetrics;
  lPolicy: TmaxQueuePolicy;
  lName: TmaxString;
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  lSubGuid: ImaxSubscription;
  lSubTyped: ImaxSubscription;
  lNamedStats: TmaxTopicStats;
  lTypedStats: TmaxTopicStats;
  lGuidStats: TmaxTopicStats;
  lTotals: TmaxTopicStats;
  lExpected: TmaxTopicStats;
  t: TNamedPostThread;
  ok: boolean;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Inc(lCount);
    if aValue = 1 then
    begin
      lStarted.SetEvent;
      lRelease.WaitFor(5000);
    end;
  end;

  procedure Failer(const aValue: TMetricEvent);
  begin
    if aValue.Value = -1 then
      Exit;
    raise Exception.Create('boom');
  end;

  procedure GuidHandler(const aValue: IIntEvent);
  begin
    if aValue = nil then
      Exit;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lMetrics := lBus as ImaxBusMetrics;
  lName := 'totals';
  lCount := 0;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lSub := nil;
  lSubGuid := nil;
  lSubTyped := nil;
  t := nil;
  try
    lPolicy.MaxDepth := 1;
    lPolicy.Overflow := DropNewest;
    lPolicy.DeadlineUs := 0;
    lQueues.SetPolicyNamed(lName, lPolicy);

    {$IFDEF max_FPC}
    lSub := lBus.SubscribeNamedOf<integer>(lName, @Handler, TmaxDelivery.Posting);
    {$ELSE}
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
        Inc(lCount);
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);
    {$ENDIF}

    t := TNamedPostThread.Create(lBus, lName, 1);
    t.Start;
    Check(lStarted.WaitFor(2000) = wrSignaled);

    {$IFDEF max_FPC}
    ok := lBus.TryPostNamedOf<integer>(lName, 2);
    {$ELSE}
    ok := maxBusObj(lBus).TryPostNamedOf<integer>(lName, 2);
    {$ENDIF}
    Check(ok);
    {$IFDEF max_FPC}
    ok := lBus.TryPostNamedOf<integer>(lName, 3);
    {$ELSE}
    ok := maxBusObj(lBus).TryPostNamedOf<integer>(lName, 3);
    {$ENDIF}
    Check(not ok);

    lRelease.SetEvent;
    t.WaitFor;
    CheckEquals(2, lCount);

    {$IFDEF max_FPC}
    lSubTyped := lBus.Subscribe<TMetricEvent>(@Failer, TmaxDelivery.Posting);
    {$ELSE}
    lSubTyped := maxBusObj(lBus).Subscribe<TMetricEvent>(
      procedure(const aValue: TMetricEvent)
      begin
        if aValue.Value = -1 then
          Exit;
        raise Exception.Create('boom');
      end,
      TmaxDelivery.Posting);
    {$ENDIF}
    try
      {$IFDEF max_FPC}
      lBus.Post<TMetricEvent>(Default(TMetricEvent));
      {$ELSE}
      maxBusObj(lBus).Post<TMetricEvent>(Default(TMetricEvent));
      {$ENDIF}
    except
      on EmaxDispatchError do ;
    end;

    {$IFDEF max_FPC}
    lSubGuid := lBus.SubscribeGuidOf<IIntEvent>(@GuidHandler, TmaxDelivery.Posting);
    lBus.PostGuidOf<IIntEvent>(TIntEvent.Create(10));
    {$ELSE}
    lSubGuid := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if aValue = nil then
          Exit;
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(10));
    {$ENDIF}

    lNamedStats := lMetrics.GetStatsNamed(lName);
    {$IFDEF max_FPC}
    lTypedStats := lMetrics.GetStatsFor<TMetricEvent>;
    lGuidStats := lMetrics.GetStatsGuidOf<IIntEvent>;
    {$ELSE}
    lTypedStats := maxBusObj(lMetrics).GetStatsFor<TMetricEvent>;
    lGuidStats := maxBusObj(lMetrics).GetStatsGuidOf<IIntEvent>;
    {$ENDIF}
    lTotals := lMetrics.GetTotals;

    lExpected := Default(TmaxTopicStats);
    Inc(lExpected.PostsTotal, lNamedStats.PostsTotal);
    Inc(lExpected.PostsTotal, lTypedStats.PostsTotal);
    Inc(lExpected.PostsTotal, lGuidStats.PostsTotal);
    Inc(lExpected.DeliveredTotal, lNamedStats.DeliveredTotal);
    Inc(lExpected.DeliveredTotal, lTypedStats.DeliveredTotal);
    Inc(lExpected.DeliveredTotal, lGuidStats.DeliveredTotal);
    Inc(lExpected.DroppedTotal, lNamedStats.DroppedTotal);
    Inc(lExpected.DroppedTotal, lTypedStats.DroppedTotal);
    Inc(lExpected.DroppedTotal, lGuidStats.DroppedTotal);
    Inc(lExpected.ExceptionsTotal, lNamedStats.ExceptionsTotal);
    Inc(lExpected.ExceptionsTotal, lTypedStats.ExceptionsTotal);
    Inc(lExpected.ExceptionsTotal, lGuidStats.ExceptionsTotal);
    lExpected.CurrentQueueDepth := lNamedStats.CurrentQueueDepth + lTypedStats.CurrentQueueDepth + lGuidStats.CurrentQueueDepth;
    lExpected.MaxQueueDepth := lNamedStats.MaxQueueDepth;
    if lTypedStats.MaxQueueDepth > lExpected.MaxQueueDepth then
      lExpected.MaxQueueDepth := lTypedStats.MaxQueueDepth;
    if lGuidStats.MaxQueueDepth > lExpected.MaxQueueDepth then
      lExpected.MaxQueueDepth := lGuidStats.MaxQueueDepth;

    CheckEquals(lExpected.PostsTotal, lTotals.PostsTotal);
    CheckEquals(lExpected.DeliveredTotal, lTotals.DeliveredTotal);
    CheckEquals(lExpected.DroppedTotal, lTotals.DroppedTotal);
    CheckEquals(lExpected.ExceptionsTotal, lTotals.ExceptionsTotal);
    CheckEquals(lExpected.CurrentQueueDepth, lTotals.CurrentQueueDepth);
    Check(lTotals.MaxQueueDepth >= lExpected.MaxQueueDepth);
  finally
    lSubGuid := nil;
    lSubTyped := nil;
    lSub := nil;
    if t <> nil then
      t.Free;
    lRelease.Free;
    lStarted.Free;
  end;
end;

{ TNamedPostThread }

constructor TNamedPostThread.Create(const aBus: ImaxBus; const aName: TmaxString; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fName := aName;
  fValue := aValue;
end;

procedure TNamedPostThread.Execute;
begin
  {$IFDEF max_FPC}
  fBus.TryPostNamedOf<integer>(fName, fValue);
  {$ELSE}
  maxBusObj(fBus).TryPostNamedOf<integer>(fName, fValue);
  {$ENDIF}
end;

{ TPresetNamedPostThread }

constructor TPresetNamedPostThread.Create(const aBus: ImaxBus; const aName: TmaxString; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fName := aName;
  fValue := aValue;
end;

procedure TPresetNamedPostThread.Execute;
begin
  {$IFDEF max_FPC}
  fBus.TryPostNamedOf<TPresetEvent>(fName, MakePresetEvent(fValue));
  {$ELSE}
  maxBusObj(fBus).TryPostNamedOf<TPresetEvent>(fName, MakePresetEvent(fValue));
  {$ENDIF}
end;

{ TGuidPostThread }

constructor TGuidPostThread.Create(const aBus: ImaxBus; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fValue := aValue;
end;

procedure TGuidPostThread.Execute;
var
  lEvt: IIntEvent;
begin
  lEvt := TIntEvent.Create(fValue);
  {$IFDEF max_FPC}
  fBus.PostGuidOf<IIntEvent>(lEvt);
  {$ELSE}
  maxBusObj(fBus).PostGuidOf<IIntEvent>(lEvt);
  {$ENDIF}
end;

procedure TTestNamedTopics.StickyAndCoalesceNamed;
var
  lBus: ImaxBus;
  lCount: integer;
  lName: TmaxString;
  lValues: array of integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'named.sticky.coalesce';
  try
    (lBus as ImaxBusAdvanced).EnableStickyNamed(lName, True);
    maxBusObj(lBus).EnableCoalesceNamedOf<integer>(lName,
      function(const aValue: integer): TmaxString
      begin
        if aValue mod 2 = 0 then
          Result := 'even'
        else
          Result := 'odd';
      end);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 10);
    lCount := 0;
    maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
        SetLength(lValues, lCount + 1);
        lValues[lCount] := aValue;
        Inc(lCount);
      end);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 1);
    maxBusObj(lBus).PostNamedOf<integer>(lName, 3);
    Sleep(50);
    CheckEquals(2, lCount);
    CheckEquals(10, lValues[0]);
    CheckEquals(3, lValues[1]);
  finally
    maxBusObj(lBus).EnableCoalesceNamedOf<integer>(lName, nil);
    (lBus as ImaxBusAdvanced).EnableStickyNamed(lName, False);
  end;
end;

procedure TTestNamedTopics.QueuePolicyAndMetricsNamed;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lMetrics: ImaxBusMetrics;
  lPolicy: TmaxQueuePolicy;
  lStats: TmaxTopicStats;
  lName: TmaxString;
  t: TNamedPostThread;
  ok: boolean;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'named.queue.metrics';
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropNewest;
  lPolicy.DeadlineUs := 0;
  lQueues.SetPolicyNamed(lName, lPolicy);
  lCount := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeNamedOf<integer>(lName, @Handler);
  {$ELSE}
  maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(lCount);
    end);
  {$ENDIF}
  t := TNamedPostThread.Create(lBus, lName, 1);
  try
    t.start;
    Sleep(10);
    {$IFDEF max_FPC}
    ok := lBus.TryPostNamedOf<integer>(lName, 2);
    {$ELSE}
    ok := maxBusObj(lBus).TryPostNamedOf<integer>(lName, 2);
    {$ENDIF}
    {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DeadlineDrops', 'TryPost(2)=' + BoolToStr(ok, True)); {$ENDIF}
    Check(ok);
    {$IFDEF max_FPC}
    ok := lBus.TryPostNamedOf<integer>(lName, 3);
    {$ELSE}
    ok := maxBusObj(lBus).TryPostNamedOf<integer>(lName, 3);
    {$ENDIF}
    {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DeadlineDrops', 'TryPost(3)=' + BoolToStr(ok, True)); {$ENDIF}
    Check(not ok);
    t.WaitFor;
    CheckEquals(2, lCount);
    lMetrics := lBus as ImaxBusMetrics;
    lStats := lMetrics.GetStatsNamed(lName);
    CheckEquals(3, lStats.PostsTotal);
    CheckEquals(2, lStats.DeliveredTotal);
    CheckEquals(1, lStats.DroppedTotal);
  finally
    t.Free;
  end;
end;

procedure TTestNamedTopics.TryPostNamedNoTopicReturnsTrueWithoutCounters;
var
  lBus: ImaxBus;
  lMetrics: ImaxBusMetrics;
  lStats: TmaxTopicStats;
begin
  lBus := maxBus;
  lBus.Clear;
  lMetrics := lBus as ImaxBusMetrics;

  Check(lBus.TryPostNamed('__trypost_named_missing__'));
  lStats := lMetrics.GetTotals;
  CheckEquals(0, lStats.PostsTotal);
  CheckEquals(0, lStats.DeliveredTotal);
  CheckEquals(0, lStats.DroppedTotal);
  CheckEquals(0, lStats.ExceptionsTotal);
end;

procedure TTestNamedTopics.TryPostNamedDeliversWhenSubscriberExists;
var
  lBus: ImaxBus;
  lMetrics: ImaxBusMetrics;
  lSub: ImaxSubscription;
  lStats: TmaxTopicStats;
  lName: TmaxString;
  lDelivered: integer;

  {$IFDEF max_FPC}
  procedure Handler;
  begin
    Inc(lDelivered);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'trypost.named.deliver';
  lMetrics := lBus as ImaxBusMetrics;
  lSub := nil;
  lDelivered := 0;
  try
    {$IFDEF max_FPC}
    lSub := lBus.SubscribeNamed(lName, @Handler, TmaxDelivery.Posting);
    {$ELSE}
    lSub := lBus.SubscribeNamed(lName,
      procedure
      begin
        Inc(lDelivered);
      end,
      TmaxDelivery.Posting);
    {$ENDIF}

    Check(lBus.TryPostNamed(lName));
    CheckEquals(1, lDelivered);
    lStats := lMetrics.GetStatsNamed(lName);
    CheckEquals(1, lStats.PostsTotal);
    CheckEquals(1, lStats.DeliveredTotal);
    CheckEquals(0, lStats.DroppedTotal);
  finally
    lSub := nil;
  end;
end;

procedure TTestNamedTopics.TryPostNamedDropNewestDrops;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lProbe: TNamedQueueBlockProbe;
  lStats: TmaxTopicStats;
const
  cName = 'trypost.named.dropnewest';
begin
  lBus := maxBus;
  lBus.Clear;
  lSub := nil;
  lProbe := nil;
  try
    SetupNamedQueuePressure(lBus, cName, TmaxOverflow.DropNewest, 0, lSub, lProbe);
    StartNamedPostThread(lBus, cName);
    Check(lProbe.fStarted.WaitFor(2000) = wrSignaled);
    Check(lBus.TryPostNamed(cName));
    Check(not lBus.TryPostNamed(cName));
    lProbe.fRelease.SetEvent;
    WaitForNamedHits(lProbe, 1, 5000);
    Sleep(150);
    lStats := (lBus as ImaxBusMetrics).GetStatsNamed(cName);
    Check(lStats.PostsTotal >= 3);
    Check(lStats.DroppedTotal >= 1);
  finally
    lSub := nil;
    lProbe.Free;
  end;
end;

procedure TTestNamedTopics.TryPostNamedDropOldestDropsQueuedOldest;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lProbe: TNamedQueueBlockProbe;
  lStats: TmaxTopicStats;
const
  cName = 'trypost.named.dropoldest';
begin
  lBus := maxBus;
  lBus.Clear;
  lSub := nil;
  lProbe := nil;
  try
    SetupNamedQueuePressure(lBus, cName, TmaxOverflow.DropOldest, 0, lSub, lProbe);
    StartNamedPostThread(lBus, cName);
    Check(lProbe.fStarted.WaitFor(2000) = wrSignaled);
    Check(lBus.TryPostNamed(cName));
    Check(lBus.TryPostNamed(cName));
    lProbe.fRelease.SetEvent;
    WaitForNamedHits(lProbe, 1, 5000);
    Sleep(150);
    lStats := (lBus as ImaxBusMetrics).GetStatsNamed(cName);
    Check(lStats.PostsTotal >= 3);
    Check(lStats.DroppedTotal >= 1);
  finally
    lSub := nil;
    lProbe.Free;
  end;
end;

procedure TTestNamedTopics.TryPostNamedBlockWaits;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lProbe: TNamedQueueBlockProbe;
  lStats: TmaxTopicStats;
const
  cName = 'trypost.named.block';
begin
  lBus := maxBus;
  lBus.Clear;
  lSub := nil;
  lProbe := nil;
  try
    SetupNamedQueuePressure(lBus, cName, TmaxOverflow.Block, 0, lSub, lProbe);
    StartNamedPostThread(lBus, cName);
    Check(lProbe.fStarted.WaitFor(2000) = wrSignaled);
    Check(lBus.TryPostNamed(cName));
    Check(lBus.TryPostNamed(cName));
    lProbe.fRelease.SetEvent;
    WaitForNamedHits(lProbe, 3, 5000);
    lStats := (lBus as ImaxBusMetrics).GetStatsNamed(cName);
    CheckEquals(3, lStats.PostsTotal);
    CheckEquals(3, lStats.DeliveredTotal);
    CheckEquals(0, lStats.DroppedTotal);
  finally
    lSub := nil;
    lProbe.Free;
  end;
end;

procedure TTestNamedTopics.TryPostNamedDeadlineDrops;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lProbe: TNamedQueueBlockProbe;
  lStats: TmaxTopicStats;
  lStart: UInt64;
const
  cName = 'trypost.named.deadline';
begin
  lBus := maxBus;
  lBus.Clear;
  lSub := nil;
  lProbe := nil;
  try
    SetupNamedQueuePressure(lBus, cName, TmaxOverflow.Deadline, 50000, lSub, lProbe);
    StartNamedPostThread(lBus, cName);
    Check(lProbe.fStarted.WaitFor(2000) = wrSignaled);
    Check(lBus.TryPostNamed(cName));
    lStart := GetTickCount64;
    Check(not lBus.TryPostNamed(cName));
    Check(GetTickCount64 - lStart >= 40, 'Deadline overflow should wait before rejecting');
    lProbe.fRelease.SetEvent;
    WaitForNamedHits(lProbe, 1, 5000);
    Sleep(250);
    lStats := (lBus as ImaxBusMetrics).GetStatsNamed(cName);
    Check(lStats.PostsTotal >= 3);
    Check(lStats.DroppedTotal >= 1);
  finally
    lSub := nil;
    lProbe.Free;
  end;
end;

{ TTestQueuePolicy }

procedure TTestQueuePolicy.DropNewestDrops;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  lDelivered: array of integer;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(lDelivered, lCount + 1);
    lDelivered[lCount] := aValue;
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropNewest;
  lPolicy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  {$ELSE}
  maxBusObj(lQueues).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(lDelivered, lCount + 1);
      lDelivered[lCount] := aValue;
      Inc(lCount);
    end);
  {$ENDIF}
  t := TPostThread.Create(lBus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(2);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  {$IFDEF max_DELPHI}
  LogLine('TTestQueuePolicy.DropOldestRemoves', 'Delivered count=' + IntToStr(lCount));
  if lCount > 0 then LogLine('TTestQueuePolicy.DropOldestRemoves', 'Delivered[0]=' + IntToStr(lDelivered[0]));
  if lCount > 1 then LogLine('TTestQueuePolicy.DropOldestRemoves', 'Delivered[1]=' + IntToStr(lDelivered[1]));
  {$ENDIF}
  CheckEquals(2, lCount);
  CheckEquals(1, lDelivered[0]);
  CheckEquals(2, lDelivered[1]);
  t.Free;
end;

procedure TTestQueuePolicy.DropOldestRemoves;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  lDelivered: array of integer;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(lDelivered, lCount + 1);
    lDelivered[lCount] := aValue;
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  {$ELSE}
  maxBusObj(lQueues).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(lDelivered, lCount + 1);
      lDelivered[lCount] := aValue;
      Inc(lCount);
    end);
  {$ENDIF}
  t := TPostThread.Create(lBus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(2);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(3);
  {$ENDIF}
  Check(ok);
  t.WaitFor;
  CheckEquals(2, lCount);
  CheckEquals(1, lDelivered[0]);  // Active item finished
  CheckEquals(3, lDelivered[1]);  // Newest item (2 was dropped)
  t.Free;
end;

procedure TTestQueuePolicy.BlockWaits;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  lDelivered: array of integer;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(lDelivered, lCount + 1);
    lDelivered[lCount] := aValue;
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := Block;
  lPolicy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  {$ELSE}
  maxBusObj(lQueues).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(lDelivered, lCount + 1);
      lDelivered[lCount] := aValue;
      Inc(lCount);
    end);
  {$ENDIF}
  t := TPostThread.Create(lBus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(2);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(3);
  {$ENDIF}
  Check(ok);
  t.WaitFor;
  Sleep(150);
  CheckEquals(3, lCount);
  CheckEquals(1, lDelivered[0]);
  CheckEquals(2, lDelivered[1]);
  CheckEquals(3, lDelivered[2]);
  t.Free;
end;

procedure TTestQueuePolicy.DeadlineDrops;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  lDelivered: array of integer;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(200);
    SetLength(lDelivered, lCount + 1);
    lDelivered[lCount] := aValue;
    Inc(lCount);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := Deadline;
  lPolicy.DeadlineUs := 50000;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  {$ELSE}
  maxBusObj(lQueues).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(200);
      SetLength(lDelivered, lCount + 1);
      lDelivered[lCount] := aValue;
      Inc(lCount);
    end);
  {$ENDIF}
  t := TPostThread.Create(lBus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(2);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := maxBusObj(lBus).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  Sleep(250);
  {$IFDEF max_DELPHI}
  LogLine('TTestQueuePolicy.DeadlineDrops', 'Delivered count=' + IntToStr(lCount));
  if lCount > 0 then LogLine('TTestQueuePolicy.DeadlineDrops', 'Delivered[0]=' + IntToStr(lDelivered[0]));
  {$ENDIF}
  CheckEquals(1, lCount);
  CheckEquals(1, lDelivered[0]);
  t.Free;
end;

{ TTestQueuePolicyPresets }

procedure TTestQueuePolicyPresets.AssertNamedOfDropNewestPolicy(const aBus: ImaxBus; const aName: TmaxString);
var
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  lThread: TNamedPostThread;
  lDelivered: array of integer;
  lCount: integer;
begin
  lSub := nil;
  lCount := 0;
  SetLength(lDelivered, 0);
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(aBus).SubscribeNamedOf<integer>(aName,
      procedure(const aValue: integer)
      begin
        SetLength(lDelivered, lCount + 1);
        lDelivered[lCount] := aValue;
        Inc(lCount);
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TNamedPostThread.Create(aBus, aName, 1);
    try
      lThread.Start;
      Check(lStarted.WaitFor(2000) = wrSignaled);
      Check(maxBusObj(aBus).TryPostNamedOf<integer>(aName, 2));
      Check(maxBusObj(aBus).TryPostNamedOf<integer>(aName, 3));
      Check(not maxBusObj(aBus).TryPostNamedOf<integer>(aName, 4));
      lRelease.SetEvent;
      lThread.WaitFor;
    finally
      lThread.Free;
    end;

    CheckEquals(3, lCount);
    CheckEquals(1, lDelivered[0]);
    CheckEquals(2, lDelivered[1]);
    CheckEquals(3, lDelivered[2]);
  finally
    lSub := nil;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestQueuePolicyPresets.AssertNamedOfStatePolicy(const aBus: ImaxBus; const aName: TmaxString);
var
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  lThread: TNamedPostThread;
  lDelivered: array of integer;
  lCount: integer;
  i: integer;
begin
  lSub := nil;
  lCount := 0;
  SetLength(lDelivered, 0);
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(aBus).SubscribeNamedOf<integer>(aName,
      procedure(const aValue: integer)
      begin
        SetLength(lDelivered, lCount + 1);
        lDelivered[lCount] := aValue;
        Inc(lCount);
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TNamedPostThread.Create(aBus, aName, 1);
    try
      lThread.Start;
      Check(lStarted.WaitFor(2000) = wrSignaled);

      for i := 2 to 300 do
        Check(maxBusObj(aBus).TryPostNamedOf<integer>(aName, i));

      lRelease.SetEvent;
      lThread.WaitFor;
    finally
      lThread.Free;
    end;

    CheckEquals(257, lCount);
    CheckEquals(1, lDelivered[0]);
    CheckEquals(45, lDelivered[1]);
    CheckEquals(300, lDelivered[256]);
  finally
    lSub := nil;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestQueuePolicyPresets.AssertNamedOfUnboundedPresetEventPolicy(const aBus: ImaxBus; const aName: TmaxString);
var
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  lThread: TPresetNamedPostThread;
  lCount: integer;
  i: integer;
begin
  lSub := nil;
  lCount := 0;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(aBus).SubscribeNamedOf<TPresetEvent>(aName,
      procedure(const aValue: TPresetEvent)
      begin
        Inc(lCount);
        if aValue.Value = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TPresetNamedPostThread.Create(aBus, aName, 1);
    try
      lThread.Start;
      Check(lStarted.WaitFor(2000) = wrSignaled);

      for i := 2 to 300 do
        Check(maxBusObj(aBus).TryPostNamedOf<TPresetEvent>(aName, MakePresetEvent(i)));

      lRelease.SetEvent;
      lThread.WaitFor;
    finally
      lThread.Free;
    end;

    CheckEquals(300, lCount);
  finally
    lSub := nil;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestQueuePolicyPresets.TypedPresetAffectsGetPolicy;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;

  maxSetQueuePresetForType(TypeInfo(TPresetEvent), TmaxQueuePreset.State);
  try
    {$IFDEF max_FPC}
    lPolicy := lQueues.GetPolicyFor<TPresetEvent>;
    {$ELSE}
    lPolicy := maxBusObj(lQueues).GetPolicyFor<TPresetEvent>;
    {$ENDIF}
    CheckEquals(256, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(TmaxOverflow.DropOldest));
    Check(lPolicy.DeadlineUs = 0);
  finally
    maxSetQueuePresetForType(TypeInfo(TPresetEvent), TmaxQueuePreset.Unspecified);
  end;
end;

procedure TTestQueuePolicyPresets.NamedStatePresetUsesDropOldest;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lName: TmaxString;
  lPolicy: TmaxQueuePolicy;
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  t: TNamedPostThread;
  lDelivered: array of integer;
  lCount: integer;
  i: integer;
  ok: boolean;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    SetLength(lDelivered, lCount + 1);
    lDelivered[lCount] := aValue;
    Inc(lCount);
    if aValue = 1 then
    begin
      lStarted.SetEvent;
      lRelease.WaitFor(5000);
    end;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lName := 'statepreset';
  lSub := nil;
  lCount := 0;
  SetLength(lDelivered, 0);

  maxSetQueuePresetNamed(string(lName), TmaxQueuePreset.State);
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    lSub := lBus.SubscribeNamedOf<integer>(lName, @Handler, TmaxDelivery.Posting);
    {$ELSE}
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
        SetLength(lDelivered, lCount + 1);
        lDelivered[lCount] := aValue;
        Inc(lCount);
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);
    {$ENDIF}

    lPolicy := lQueues.GetPolicyNamed(string(lName));
    CheckEquals(256, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(TmaxOverflow.DropOldest));

    t := TNamedPostThread.Create(lBus, lName, 1);
    try
      t.Start;
      Check(lStarted.WaitFor(2000) = wrSignaled);

      for i := 2 to 300 do
      begin
        {$IFDEF max_FPC}
        ok := lBus.TryPostNamedOf<integer>(lName, i);
        {$ELSE}
        ok := maxBusObj(lBus).TryPostNamedOf<integer>(lName, i);
        {$ENDIF}
        Check(ok);
      end;

      lRelease.SetEvent;
      t.WaitFor;
    finally
      t.Free;
    end;

    CheckEquals(257, lCount);
    CheckEquals(1, lDelivered[0]);
    CheckEquals(45, lDelivered[1]);
    CheckEquals(300, lDelivered[256]);
  finally
    maxSetQueuePresetNamed(string(lName), TmaxQueuePreset.Unspecified);
    lSub := nil;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestQueuePolicyPresets.NamedOfTypePresetFallbackUsesState;
const
  cName = 'statepreset.namedof.typefallback';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.State);
  AssertNamedOfStatePolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedOfNamePresetOverridesTypePreset;
const
  cName = 'statepreset.namedof.nameoverride';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.ControlPlane);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.State);
  AssertNamedOfStatePolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedOfExplicitPolicyOverridesPresets;
const
  cName = 'statepreset.namedof.explicit';
var
  lBus: ImaxBus;
  lExplicit: TmaxQueuePolicy;
begin
  lBus := CreateIsolatedBus;
  lExplicit := BuildQueuePolicy(2, TmaxOverflow.DropNewest, 0);
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.ControlPlane);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.State);
  maxBusObj(lBus).SetPolicyNamed(cName, lExplicit);
  AssertNamedOfDropNewestPolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedOfRemovingNamePresetFallsBackToTypePreset;
const
  cName = 'statepreset.namedof.removenamepreset';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.State);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.ControlPlane);
  maxBusObj(lBus).SubscribeNamedOf<integer>(cName,
    procedure(const aValue: integer)
    begin
      if aValue = 0 then
        Exit;
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.Unspecified);
  AssertNamedOfStatePolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedOfRemovingNamePresetFallsBackPerType;
const
  cName = 'statepreset.namedof.sharedname';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.State);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.State);
  maxBusObj(lBus).SubscribeNamedOf<integer>(cName,
    procedure(const aValue: integer)
    begin
      if aValue = 0 then
        Exit;
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).SubscribeNamedOf<TPresetEvent>(cName,
    procedure(const aValue: TPresetEvent)
    begin
      if aValue.Value = 0 then
        Exit;
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).SetQueuePresetNamed(cName, TmaxQueuePreset.Unspecified);
  AssertNamedOfStatePolicy(lBus, cName);
  AssertNamedOfUnboundedPresetEventPolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedOfTypePresetUpdateReappliesToExistingImplicitTopic;
const
  cName = 'statepreset.namedof.reapply';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SubscribeNamedOf<integer>(cName,
    procedure(const aValue: integer)
    begin
      if aValue = 0 then
        Exit;
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.State);
  AssertNamedOfStatePolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.ClearPreservesNamedOfTypePresetFallback;
const
  cName = 'statepreset.namedof.clearfallback';
var
  lBus: ImaxBus;
begin
  lBus := CreateIsolatedBus;
  maxBusObj(lBus).SetQueuePresetForType(TypeInfo(integer), TmaxQueuePreset.State);
  maxBusObj(lBus).SubscribeNamedOf<integer>(cName,
    procedure(const aValue: integer)
    begin
      if aValue = 0 then
        Exit;
    end,
    TmaxDelivery.Posting);
  lBus.Clear;
  AssertNamedOfStatePolicy(lBus, cName);
end;

procedure TTestQueuePolicyPresets.NamedPresetsReturnDefaultPolicy;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;

  maxSetQueuePresetNamed('actionpreset', TmaxQueuePreset.Action);
  maxSetQueuePresetNamed('ctrlpreset', TmaxQueuePreset.ControlPlane);
  try
    lPolicy := lQueues.GetPolicyNamed('actionpreset');
    CheckEquals(1024, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(TmaxOverflow.Deadline));
    Check(lPolicy.DeadlineUs = 2000);

    lPolicy := lQueues.GetPolicyNamed('ctrlpreset');
    CheckEquals(1, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(TmaxOverflow.Block));
    Check(lPolicy.DeadlineUs = 0);
  finally
    maxSetQueuePresetNamed('actionpreset', TmaxQueuePreset.Unspecified);
    maxSetQueuePresetNamed('ctrlpreset', TmaxQueuePreset.Unspecified);
  end;
end;

procedure TTestQueuePolicyPresets.GuidPresetAffectsGetPolicy;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lGuid: TGuid;
  lPolicy: TmaxQueuePolicy;
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lGuid := GetTypeData(TypeInfo(IQueuePresetGuidEvent))^.Guid;

  maxSetQueuePresetGuid(lGuid, TmaxQueuePreset.ControlPlane);
  try
    {$IFDEF max_FPC}
    lPolicy := lQueues.GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ELSE}
    lPolicy := maxBusObj(lQueues).GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ENDIF}
    CheckEquals(1, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(TmaxOverflow.Block));
    Check(lPolicy.DeadlineUs = 0);
  finally
    maxSetQueuePresetGuid(lGuid, TmaxQueuePreset.Unspecified);
  end;
end;

procedure TTestQueuePolicyPresets.GuidExplicitPolicyBeatsPreset;
var
  lBus: ImaxBus;
  lQueues: ImaxBusQueues;
  lGuid: TGuid;
  lExplicit: TmaxQueuePolicy;
  lPolicy: TmaxQueuePolicy;
begin
  lBus := maxBus;
  lBus.Clear;
  lQueues := lBus as ImaxBusQueues;
  lGuid := GetTypeData(TypeInfo(IQueuePresetGuidEvent))^.Guid;
  lExplicit.MaxDepth := 7;
  lExplicit.Overflow := TmaxOverflow.DropNewest;
  lExplicit.DeadlineUs := 1234;

  maxSetQueuePresetGuid(lGuid, TmaxQueuePreset.ControlPlane);
  try
    {$IFDEF max_FPC}
    lQueues.SetPolicyGuidOf<IQueuePresetGuidEvent>(lExplicit);
    lPolicy := lQueues.GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ELSE}
    maxBusObj(lQueues).SetPolicyGuidOf<IQueuePresetGuidEvent>(lExplicit);
    lPolicy := maxBusObj(lQueues).GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ENDIF}
    CheckEquals(lExplicit.MaxDepth, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(lExplicit.Overflow));
    CheckEquals(lExplicit.DeadlineUs, lPolicy.DeadlineUs);

    maxSetQueuePresetGuid(lGuid, TmaxQueuePreset.State);
    {$IFDEF max_FPC}
    lPolicy := lQueues.GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ELSE}
    lPolicy := maxBusObj(lQueues).GetPolicyGuidOf<IQueuePresetGuidEvent>;
    {$ENDIF}
    CheckEquals(lExplicit.MaxDepth, lPolicy.MaxDepth);
    Check(Ord(lPolicy.Overflow) = Ord(lExplicit.Overflow));
    CheckEquals(lExplicit.DeadlineUs, lPolicy.DeadlineUs);
  finally
    maxSetQueuePresetGuid(lGuid, TmaxQueuePreset.Unspecified);
  end;
end;

{ TTestSticky }

procedure TTestSticky.LateSubscriberGetsLastEvent;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<integer>;

  procedure Handler(const aValue: integer);
  begin
    lValues.Add(aValue);
  end;
  {$ELSE}
  lValues: TList<integer>;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_DELPHI}
  maxBusObj(lBus).EnableSticky<integer>(True);
  {$ELSE}
  lBus.EnableSticky<integer>(True);
  {$ENDIF}
  try
    {$IFDEF max_DELPHI}
    maxBusObj(lBus).Post<integer>(42);
    {$ELSE}
    lBus.Post<integer>(42);
    {$ENDIF}
    {$IFDEF max_FPC}
    lValues := specialize TList<integer>.Create;
    lSub := lBus.Subscribe<integer>(@Handler);
    {$ELSE}
    lValues := TList<integer>.Create;
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end);
    {$ENDIF}
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(42, lValues[0]);
      {$IFDEF max_DELPHI}
      maxBusObj(lBus).Post<integer>(43);
      {$ELSE}
      lBus.Post<integer>(43);
      {$ENDIF}
      CheckEquals(2, lValues.Count);
      CheckEquals(43, lValues[1]);
    finally
      lValues.Free;
    end;
  finally
    {$IFDEF max_DELPHI}
    maxBusObj(lBus).EnableSticky<integer>(False);
    {$ELSE}
    lBus.EnableSticky<integer>(False);
    {$ENDIF}
  end;
end;

{ TTestSubscribeOrdering }

procedure TTestSubscribeOrdering.PreservesOrderAndHandlesChurn;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<integer>;

  procedure Handler(const aValue: integer);
  begin
    lValues.Add(aValue);
  end;
  {$ELSE}
  lValues: TList<integer>;
  {$ENDIF}
  i: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_FPC}
  lValues := specialize TList<integer>.Create;
  lSub := lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  lValues := TList<integer>.Create;
  lSub := maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      lValues.Add(aValue);
    end);
  {$ENDIF}
  try
    for i := 1 to 5 do
      {$IFDEF max_FPC}
      lBus.Post<integer>(i);
    {$ELSE}
      maxBusObj(lBus).Post<integer>(i);
    {$ENDIF}
    CheckEquals(5, lValues.Count);
    for i := 1 to 5 do
      CheckEquals(i, lValues[i - 1]);
    lSub.Unsubscribe;
    lValues.Clear;
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@Handler);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end);
    {$ENDIF}
    for i := 6 to 10 do
      {$IFDEF max_FPC}
      lBus.Post<integer>(i);
    {$ELSE}
      maxBusObj(lBus).Post<integer>(i);
    {$ENDIF}
    CheckEquals(5, lValues.Count);
    for i := 0 to 4 do
      CheckEquals(6 + i, lValues[i]);
  finally
    lValues.Free;
  end;
end;

{ TTarget }

procedure TTarget.Handle(const aValue: integer);
begin
  fLastValue := aValue;
  Inc(fCount);
end;

procedure TTestUnsubscribeAll.RemovesAllHandlers;
var
  lBus: ImaxBus;
  lTgt: TTarget;
  lSub1, lSub2: ImaxSubscription;
begin
  lBus := maxBus;
  lTgt := TTarget.Create;
  try
    {$IFDEF max_FPC}
    lSub1 := lBus.Subscribe<integer>(@lTgt.Handle);
    lSub2 := lBus.Subscribe<integer>(@lTgt.Handle);
    {$ELSE}
    lSub1 := maxBusObj(lBus).Subscribe<integer>(lTgt.Handle);
    lSub2 := maxBusObj(lBus).Subscribe<integer>(lTgt.Handle);
    {$ENDIF}
    lBus.UnsubscribeAllFor(lTgt);
    {$IFDEF max_FPC}
    lBus.Post<integer>(1);
    {$ELSE}
    maxBusObj(lBus).Post<integer>(1);
    {$ENDIF}
    CheckEquals(0, lTgt.Count);
    Check(not lSub1.IsActive);
    Check(not lSub2.IsActive);
  finally
    lTgt.Free;
  end;
end;

procedure TTestSticky.ClearPreservesStickyConfig;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<integer>;

  procedure Handler(const aValue: integer);
  begin
    lValues.Add(aValue);
  end;
  {$ELSE}
  lValues: TList<integer>;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_DELPHI}
  maxBusObj(lBus).EnableSticky<integer>(True);
  {$ELSE}
  lBus.EnableSticky<integer>(True);
  {$ENDIF}
  try
    {$IFDEF max_DELPHI}
    maxBusObj(lBus).Post<integer>(1);
    {$ELSE}
    lBus.Post<integer>(1);
    {$ENDIF}

    lBus.Clear;

    {$IFDEF max_DELPHI}
    maxBusObj(lBus).Post<integer>(2);
    {$ELSE}
    lBus.Post<integer>(2);
    {$ENDIF}

    {$IFDEF max_FPC}
    lValues := specialize TList<integer>.Create;
    lSub := lBus.Subscribe<integer>(@Handler);
    {$ELSE}
    lValues := TList<integer>.Create;
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end);
    {$ENDIF}
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(2, lValues[0]);
    finally
      lValues.Free;
    end;
  finally
    {$IFDEF max_DELPHI}
    maxBusObj(lBus).EnableSticky<integer>(False);
    {$ELSE}
    lBus.EnableSticky<integer>(False);
    {$ENDIF}
    lSub := nil;
  end;
end;

procedure TTestSticky.TryPostStickyFirstCountsPost;
var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lStats: TmaxTopicStats;
begin
  lBus := maxBus;
  lBusObj := maxBusObj(lBus);
  lBus.Clear;
  lBusObj.EnableSticky<integer>(True);
  try
    Check(lBusObj.TryPost<integer>(123), 'TryPost should succeed');
    lStats := lBusObj.GetStatsFor<integer>;
    CheckEquals(1, lStats.PostsTotal);
    CheckEquals(0, lStats.DeliveredTotal);
  finally
    lBusObj.EnableSticky<integer>(False);
    lBus.Clear;
  end;
end;

{ TWeakTargetProbe }

procedure TWeakTargetProbe.OnInt(const aValue: integer);
begin
  LastInt := aValue;
  Inc(HitsInt);
end;

procedure TWeakTargetProbe.OnIntf(const aValue: IIntEvent);
begin
  LastIntfWasNil := aValue = nil;
  Inc(HitsIntf);
end;

{ TTestWeakTargets }

procedure TTestWeakTargets.SkipsFreedTargetTyped;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsInt := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@lProbe.OnInt);
    lBus.Post<integer>(1);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(lProbe.OnInt);
    maxBusObj(lBus).Post<integer>(1);
    {$ENDIF}
    CheckEquals(1, TWeakTargetProbe.HitsInt);

    lProbe.Free;
    lProbe := nil;

    {$IFDEF max_FPC}
    lBus.Post<integer>(2);
    {$ELSE}
    maxBusObj(lBus).Post<integer>(2);
    {$ENDIF}

    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(not lSub.IsActive);
  finally
    if lProbe <> nil then
      lProbe.Free;
  end;
end;

procedure TTestWeakTargets.SkipsFreedTargetNamedOf;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsInt := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    {$IFDEF max_FPC}
    lSub := lBus.SubscribeNamedOf<integer>('weak', @lProbe.OnInt);
    lBus.PostNamedOf<integer>('weak', 1);
    {$ELSE}
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>('weak', lProbe.OnInt);
    maxBusObj(lBus).PostNamedOf<integer>('weak', 1);
    {$ENDIF}
    CheckEquals(1, TWeakTargetProbe.HitsInt);

    lProbe.Free;
    lProbe := nil;

    {$IFDEF max_FPC}
    lBus.PostNamedOf<integer>('weak', 2);
    {$ELSE}
    maxBusObj(lBus).PostNamedOf<integer>('weak', 2);
    {$ENDIF}

    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(not lSub.IsActive);
  finally
    if lProbe <> nil then
      lProbe.Free;
  end;
end;

procedure TTestWeakTargets.SkipsFreedTargetGuidOf;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
  lEvt: IIntEvent;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsIntf := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    {$IFDEF max_FPC}
    lSub := lBus.SubscribeGuidOf<IIntEvent>(@lProbe.OnIntf);
    lEvt := TIntEvent.Create(1);
    lBus.PostGuidOf<IIntEvent>(lEvt);
    {$ELSE}
    lSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(lProbe.OnIntf);
    lEvt := TIntEvent.Create(1);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(lEvt);
    {$ENDIF}
    CheckEquals(1, TWeakTargetProbe.HitsIntf);

    lProbe.Free;
    lProbe := nil;

    {$IFDEF max_FPC}
    lEvt := TIntEvent.Create(2);
    lBus.PostGuidOf<IIntEvent>(lEvt);
    {$ELSE}
    lEvt := TIntEvent.Create(2);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(lEvt);
    {$ENDIF}

    CheckEquals(1, TWeakTargetProbe.HitsIntf);
    Check(not lSub.IsActive);
  finally
    if lProbe <> nil then
      lProbe.Free;
  end;
end;

{ TTestStrongTargets }

procedure TTestStrongTargets.UnsubscribeAllForRemovesTypedStrong;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsInt := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    lSub := maxBusObj(lBus).SubscribeStrong<integer>(lProbe.OnInt, TmaxDelivery.Posting);
    maxBusObj(lBus).Post<integer>(1);
    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(lSub.IsActive);

    lBus.UnsubscribeAllFor(lProbe);
    maxBusObj(lBus).Post<integer>(2);

    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(not lSub.IsActive);
  finally
    lProbe.Free;
  end;
end;

procedure TTestStrongTargets.UnsubscribeAllForRemovesNamedStrong;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsInt := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    lSub := maxBusObj(lBus).SubscribeNamedOfStrong<integer>('strong.named', lProbe.OnInt, TmaxDelivery.Posting);
    maxBusObj(lBus).PostNamedOf<integer>('strong.named', 1);
    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(lSub.IsActive);

    lBus.UnsubscribeAllFor(lProbe);
    maxBusObj(lBus).PostNamedOf<integer>('strong.named', 2);

    CheckEquals(1, TWeakTargetProbe.HitsInt);
    Check(not lSub.IsActive);
  finally
    lProbe.Free;
  end;
end;

procedure TTestStrongTargets.UnsubscribeAllForRemovesGuidStrong;
var
  lBus: ImaxBus;
  lProbe: TWeakTargetProbe;
  lSub: ImaxSubscription;
  lEvt: IIntEvent;
begin
  lBus := maxBus;
  lBus.Clear;

  TWeakTargetProbe.HitsIntf := 0;
  lProbe := TWeakTargetProbe.Create;
  try
    lSub := maxBusObj(lBus).SubscribeGuidOfStrong<IIntEvent>(lProbe.OnIntf, TmaxDelivery.Posting);
    lEvt := TIntEvent.Create(1);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(lEvt);
    CheckEquals(1, TWeakTargetProbe.HitsIntf);
    Check(lSub.IsActive);

    lBus.UnsubscribeAllFor(lProbe);
    lEvt := TIntEvent.Create(2);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(lEvt);

    CheckEquals(1, TWeakTargetProbe.HitsIntf);
    Check(not lSub.IsActive);
  finally
    lProbe.Free;
  end;
end;

{ TTestWeakTargetABA }

procedure TTestWeakTargetABA.PreventsQueuedABARedirect;
var
  lBus: ImaxBus;
  lStarted: TEvent;
  lRelease: TEvent;
  lOldPtr: Pointer;
  lOld, lNew: TABATarget;
  lSub: ImaxSubscription;
  lDummy: ImaxSubscription;
  t: TPostThread;
  ok: boolean;
begin
  lBus := maxBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lOld := nil;
  lNew := nil;
  lSub := nil;
  lDummy := nil;
  t := nil;
  try
    lOld := TABATarget.Create;
    lOld.fStarted := lStarted;
    lOld.fRelease := lRelease;
    lOld.fHits := 0;
    lOldPtr := Pointer(lOld);

    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@lOld.OnInt, TmaxDelivery.Posting);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(lOld.OnInt, TmaxDelivery.Posting);
    {$ENDIF}

    t := TPostThread.Create(lBus, 1);
    t.Start;
    Check(lStarted.WaitFor(2000) = wrSignaled);

    {$IFDEF max_FPC}
    ok := lBus.TryPost<integer>(2);
    {$ELSE}
    ok := maxBusObj(lBus).TryPost<integer>(2);
    {$ENDIF}
    Check(ok);

    lOld.Free;
    lOld := nil;

    lNew := TABATarget.Create;
    Check(Pointer(lNew) = lOldPtr);

    // Re-observe the reused pointer (simulate a new instance legitimately becoming a live target).
    {$IFDEF max_FPC}
    lDummy := lBus.Subscribe<TABAEvent>(@lNew.OnABA, TmaxDelivery.Posting);
    {$ELSE}
    lDummy := maxBusObj(lBus).Subscribe<TABAEvent>(lNew.OnABA, TmaxDelivery.Posting);
    {$ENDIF}

    lRelease.SetEvent;
    t.WaitFor;

    CheckEquals(0, lNew.fHits);
    Check(not lSub.IsActive);
  finally
    lDummy := nil;
    lSub := nil;
    if t <> nil then
      t.Free;
    if lOld <> nil then
      lOld.Free;
    if lNew <> nil then
      lNew.Free;
    TABATarget.CleanupReuse;
    lRelease.Free;
    lStarted.Free;
  end;
end;

{ TTestSubscriptionTokens }

procedure TTestSubscriptionTokens.TokenReleaseAutoUnsubscribes;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHits: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: TMetricEvent);
  begin
    Inc(lHits);
    if aValue.Value = -1 then
      Exit;
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lSub := nil;
  lHits := 0;

  {$IFDEF max_FPC}
  lSub := lBus.Subscribe<TMetricEvent>(@Handler, TmaxDelivery.Posting);
  lBus.Post<TMetricEvent>(Default(TMetricEvent));
  {$ELSE}
  lSub := maxBusObj(lBus).Subscribe<TMetricEvent>(
    procedure(const aValue: TMetricEvent)
    begin
      Inc(lHits);
      if aValue.Value = -1 then
        Exit;
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).Post<TMetricEvent>(Default(TMetricEvent));
  {$ENDIF}
  CheckEquals(1, lHits);

  lSub := nil;

  {$IFDEF max_FPC}
  lBus.Post<TMetricEvent>(Default(TMetricEvent));
  {$ELSE}
  maxBusObj(lBus).Post<TMetricEvent>(Default(TMetricEvent));
  {$ENDIF}
  CheckEquals(1, lHits);
end;

procedure TTestSubscriptionTokens.QueuedBeforeCancelSkipsExecution;
var
  lBus: ImaxBus;
  lProbe: TQueueBlockProbe;
  lStarted: TEvent;
  lRelease: TEvent;
  lSub: ImaxSubscription;
  t: TPostThread;
  ok: boolean;
begin
  lBus := maxBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lProbe := TQueueBlockProbe.Create;
  lSub := nil;
  t := nil;
  try
    lProbe.fStarted := lStarted;
    lProbe.fRelease := lRelease;
    lProbe.fHits := 0;

    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@lProbe.OnInt, TmaxDelivery.Posting);
    {$ELSE}
    lSub := maxBusObj(lBus).Subscribe<integer>(lProbe.OnInt, TmaxDelivery.Posting);
    {$ENDIF}

    t := TPostThread.Create(lBus, 1);
    t.Start;
    Check(lStarted.WaitFor(2000) = wrSignaled);

    {$IFDEF max_FPC}
    ok := lBus.TryPost<integer>(2);
    {$ELSE}
    ok := maxBusObj(lBus).TryPost<integer>(2);
    {$ENDIF}
    Check(ok);

    lSub.Unsubscribe;

    lRelease.SetEvent;
    t.WaitFor;
    CheckEquals(1, lProbe.fHits);
  finally
    lSub := nil;
    if t <> nil then
      t.Free;
    lProbe.Free;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestSubscriptionTokens.ClearInvalidatesOldHandlesWithoutCrossUnsubscribe;
var
  lBus: ImaxBus;
  lOldSub: ImaxSubscription;
  lNewSub: ImaxSubscription;
  lHits: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Inc(lHits);
  end;
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lOldSub := nil;
  lNewSub := nil;
  lHits := 0;
  try
    {$IFDEF max_FPC}
    lOldSub := lBus.Subscribe<integer>(@Handler, TmaxDelivery.Posting);
    {$ELSE}
    lOldSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
      end,
      TmaxDelivery.Posting);
    {$ENDIF}
    PostIntegerValue(lBus, 1);
    CheckEquals(1, lHits);

    lBus.Clear;

    {$IFDEF max_FPC}
    lNewSub := lBus.Subscribe<integer>(@Handler, TmaxDelivery.Posting);
    {$ELSE}
    lNewSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
      end,
      TmaxDelivery.Posting);
    {$ENDIF}
    Check(lNewSub.IsActive);

    lOldSub.Unsubscribe;
    Check(lNewSub.IsActive, 'Old handle must not affect post-Clear subscription');

    PostIntegerValue(lBus, 2);
    CheckEquals(2, lHits, 'New subscription must still receive after old handle unsubscribe');

    lNewSub.Unsubscribe;

    PostIntegerValue(lBus, 3);
    CheckEquals(2, lHits);
  finally
    lNewSub := nil;
    lOldSub := nil;
  end;
end;

procedure TTestSubscriptionTokens.ClearInFlightAsyncNamedKeepsNewSubscriptionActive;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lProbe: TAsyncClearProbe;
  lOldSub: ImaxSubscription;
  lNewSub: ImaxSubscription;
begin
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
  lBus := maxBus;
  lBus.Clear;
  lProbe := TAsyncClearProbe.Create;
  lOldSub := nil;
  lNewSub := nil;
  try
    lOldSub := lBus.SubscribeNamed('clear.named.async', lProbe.OnOldNamed, TmaxDelivery.Async);
    lBus.PostNamed('clear.named.async');
    Check(lProbe.fStarted.WaitFor(5000) = wrSignaled);

    lBus.Clear;
    lNewSub := lBus.SubscribeNamed('clear.named.async', lProbe.OnNewNamed, TmaxDelivery.Async);
    lOldSub.Unsubscribe;
    Check(lNewSub.IsActive, 'Old named handle must be inert after Clear');

    lProbe.fRelease.SetEvent;
    Check(lProbe.fFinished.WaitFor(5000) = wrSignaled);
    lBus.PostNamed('clear.named.async');
    Check(lProbe.fDone.WaitFor(5000) = wrSignaled);
    CheckEquals(1, lProbe.fOldHits);
    CheckEquals(1, lProbe.fNewHits);
  finally
    lNewSub := nil;
    lOldSub := nil;
    lProbe.Free;
    maxSetAsyncScheduler(lPrevScheduler);
  end;
end;

procedure TTestSubscriptionTokens.ClearInFlightAsyncGuidKeepsNewSubscriptionActive;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lProbe: TAsyncClearProbe;
  lOldSub: ImaxSubscription;
  lNewSub: ImaxSubscription;
begin
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
  lBus := maxBus;
  lBus.Clear;
  lProbe := TAsyncClearProbe.Create;
  lOldSub := nil;
  lNewSub := nil;
  try
    lOldSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(lProbe.OnOldGuid, TmaxDelivery.Async);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(11));
    Check(lProbe.fStarted.WaitFor(5000) = wrSignaled);

    lBus.Clear;
    lNewSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(lProbe.OnNewGuid, TmaxDelivery.Async);
    lOldSub.Unsubscribe;
    Check(lNewSub.IsActive, 'Old guid handle must be inert after Clear');

    lProbe.fRelease.SetEvent;
    Check(lProbe.fFinished.WaitFor(5000) = wrSignaled);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(22));
    Check(lProbe.fDone.WaitFor(5000) = wrSignaled);
    CheckEquals(1, lProbe.fOldHits);
    CheckEquals(1, lProbe.fNewHits);
  finally
    lNewSub := nil;
    lOldSub := nil;
    lProbe.Free;
    maxSetAsyncScheduler(lPrevScheduler);
  end;
end;

{ TTestPostResult }

procedure TTestPostResult.NoTopicReturnsNoTopic;
var
  lBus: ImaxBus;
  lGuidEvt: IPostResultGuidEvent;
  lEvt: TPostResultNoTopicEvent;
begin
  lBus := maxBus;
  lBus.Clear;
  lGuidEvt := TPostResultGuidEvent.Create(1);
  lEvt.Value := 42;

  CheckEquals(Integer(TmaxPostResult.NoTopic), Integer(maxBusObj(lBus).PostResult<TPostResultNoTopicEvent>(lEvt)));
  CheckEquals(Integer(TmaxPostResult.NoTopic), Integer(maxBusObj(lBus).PostResultNamed('__postresult_missing_named__')));
  CheckEquals(Integer(TmaxPostResult.NoTopic), Integer(maxBusObj(lBus).PostResultNamedOf<TPostResultNoTopicEvent>('__postresult_missing_named__', lEvt)));
  CheckEquals(Integer(TmaxPostResult.NoTopic), Integer(maxBusObj(lBus).PostResultGuidOf<IPostResultGuidEvent>(lGuidEvt)));
end;

procedure TTestPostResult.DropNewestReturnsDropped;
var
  lBus: ImaxBus;
  lPolicy: TmaxQueuePolicy;
  lStarted: TEvent;
  lRelease: TEvent;
  lThread: TThread;
  lPostResult: TmaxPostResult;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy.MaxDepth := 1;
    lPolicy.Overflow := TmaxOverflow.DropNewest;
    lPolicy.DeadlineUs := 0;
    maxBusObj(lBus).SetPolicyFor<integer>(lPolicy);

    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResult<integer>(1);
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'First dispatch did not start');
    maxBusObj(lBus).PostResult<integer>(2); // fills single queued slot
    lPostResult := maxBusObj(lBus).PostResult<integer>(3);
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lPostResult));
  finally
    lRelease.SetEvent;
    if lThread <> nil then
    begin
      lThread.WaitFor;
      lThread.Free;
    end;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.NamedOfDropNewestReturnsDropped;
var
  lBus: ImaxBus;
  lPolicy: TmaxQueuePolicy;
  lStarted: TEvent;
  lRelease: TEvent;
  lThread: TThread;
  lPostResult: TmaxPostResult;
  lName: string;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lName := 'postresult.named.drop';
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy.MaxDepth := 1;
    lPolicy.Overflow := TmaxOverflow.DropNewest;
    lPolicy.DeadlineUs := 0;
    maxBusObj(lBus).SetPolicyNamed(lName, lPolicy);

    maxBusObj(lBus).SubscribeNamedOf<integer>(lName,
      procedure(const aValue: integer)
      begin
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResultNamedOf<integer>(lName, 1);
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'First named-of dispatch did not start');
    maxBusObj(lBus).PostResultNamedOf<integer>(lName, 2); // fills single queued slot
    lPostResult := maxBusObj(lBus).PostResultNamedOf<integer>(lName, 3);
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lPostResult));
  finally
    lRelease.SetEvent;
    if lThread <> nil then
    begin
      lThread.WaitFor;
      lThread.Free;
    end;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.CoalescedReturnsCoalesced;
var
  lBus: ImaxBus;
  lEvt: TKeyed;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
    function(const aValue: TKeyed): TmaxString
    begin
      Result := aValue.Key;
    end,
    10000);
  try
    maxBusObj(lBus).Subscribe<TKeyed>(
      procedure(const aValue: TKeyed)
      begin
        if aValue.Value = -1 then
          Exit;
      end,
      TmaxDelivery.Posting);

    lEvt.Key := 'A';
    lEvt.Value := 1;
    CheckEquals(Integer(TmaxPostResult.Coalesced), Integer(maxBusObj(lBus).PostResult<TKeyed>(lEvt)));
    lEvt.Value := 2;
    CheckEquals(Integer(TmaxPostResult.Coalesced), Integer(maxBusObj(lBus).PostResult<TKeyed>(lEvt)));
  finally
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(nil);
  end;
end;

procedure TTestPostResult.AcceptedReturnsInlineOrQueued;
var
  lBus: ImaxBus;
  lPolicy: TmaxQueuePolicy;
  lStarted: TEvent;
  lRelease: TEvent;
  lThread: TThread;
  lInlineResult: TmaxPostResult;
  lQueuedResult: TmaxPostResult;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;

  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      if aValue = -1 then
        Exit;
    end,
    TmaxDelivery.Posting);
  lInlineResult := maxBusObj(lBus).PostResult<integer>(11);
  CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lInlineResult));

  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy := BuildQueuePolicy(2, TmaxOverflow.DropNewest, 0);
    maxBusObj(lBus).SetPolicyFor<integer>(lPolicy);

    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResult<integer>(1);
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'First dispatch did not start');
    lQueuedResult := maxBusObj(lBus).PostResult<integer>(22);
    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lQueuedResult));
  finally
    ReleaseAndJoinThread(lRelease, lThread);
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.GuidOfQueuePressureReturnsQueuedThenDropped;
var
  lBus: ImaxBus;
  lPolicy: TmaxQueuePolicy;
  lStarted: TEvent;
  lRelease: TEvent;
  lThread: TThread;
  lQueuedResult: TmaxPostResult;
  lDroppedResult: TmaxPostResult;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy.MaxDepth := 1;
    lPolicy.Overflow := TmaxOverflow.DropNewest;
    lPolicy.DeadlineUs := 0;
    maxBusObj(lBus).SetPolicyGuidOf<IIntEvent>(lPolicy);

    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if (aValue <> nil) and (aValue.GetValue = 1) then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(1));
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'First guid dispatch did not start');
    lQueuedResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(2));
    lDroppedResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(3));
    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lQueuedResult));
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lDroppedResult));
  finally
    lRelease.SetEvent;
    if lThread <> nil then
    begin
      lThread.WaitFor;
      lThread.Free;
    end;
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.GuidOfAcceptedReturnsInline;
var
  lBus: ImaxBus;
  lResult: TmaxPostResult;
  lHits: integer;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lHits := 0;

  maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
    procedure(const aValue: IIntEvent)
    begin
      if aValue <> nil then
      begin
        Inc(lHits);
      end;
    end,
    TmaxDelivery.Posting);

  lResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(17));
  CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lResult));
  CheckEquals(1, lHits);
end;

procedure TTestPostResult.ClearPreservesTypedExplicitPolicy;
var
  lBus: ImaxBus;
  lDroppedResult: TmaxPostResult;
  lPolicy: TmaxQueuePolicy;
  lQueuedResult: TmaxPostResult;
  lRelease: TEvent;
  lStarted: TEvent;
  lThread: TThread;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy := BuildQueuePolicy(1, TmaxOverflow.DropNewest, 0);
    maxBusObj(lBus).SetPolicyFor<integer>(lPolicy);

    lBus.Clear;

    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue = 1 then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResult<integer>(1);
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'Typed clear-preserved dispatch did not start');
    lQueuedResult := maxBusObj(lBus).PostResult<integer>(2);
    lDroppedResult := maxBusObj(lBus).PostResult<integer>(3);
    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lQueuedResult));
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lDroppedResult));
  finally
    ReleaseAndJoinThread(lRelease, lThread);
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.ClearPreservesNamedExplicitPolicy;
const
  cName = 'clear.policy.named';
var
  lBus: ImaxBus;
  lDroppedResult: TmaxPostResult;
  lPolicy: TmaxQueuePolicy;
  lQueuedResult: TmaxPostResult;
  lRelease: TEvent;
  lStarted: TEvent;
  lThread: TThread;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy := BuildQueuePolicy(1, TmaxOverflow.DropNewest, 0);
    maxBusObj(lBus).SetPolicyNamed(cName, lPolicy);

    lBus.Clear;

    lBus.SubscribeNamed(cName,
      procedure
      begin
        lStarted.SetEvent;
        lRelease.WaitFor(5000);
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResultNamed(cName);
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'Named clear-preserved dispatch did not start');
    lQueuedResult := maxBusObj(lBus).PostResultNamed(cName);
    lDroppedResult := maxBusObj(lBus).PostResultNamed(cName);
    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lQueuedResult));
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lDroppedResult));
  finally
    ReleaseAndJoinThread(lRelease, lThread);
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.ClearPreservesGuidExplicitPolicy;
var
  lBus: ImaxBus;
  lDroppedResult: TmaxPostResult;
  lPolicy: TmaxQueuePolicy;
  lQueuedResult: TmaxPostResult;
  lRelease: TEvent;
  lStarted: TEvent;
  lThread: TThread;
begin
  lBus := CreateIsolatedBus;
  lBus.Clear;
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lThread := nil;
  try
    lPolicy := BuildQueuePolicy(1, TmaxOverflow.DropNewest, 0);
    maxBusObj(lBus).SetPolicyGuidOf<IIntEvent>(lPolicy);

    lBus.Clear;

    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if (aValue <> nil) and (aValue.GetValue = 1) then
        begin
          lStarted.SetEvent;
          lRelease.WaitFor(5000);
        end;
      end,
      TmaxDelivery.Posting);

    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(1));
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;

    Check(lStarted.WaitFor(2000) = wrSignaled, 'Guid clear-preserved dispatch did not start');
    lQueuedResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(2));
    lDroppedResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(3));
    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lQueuedResult));
    CheckEquals(Integer(TmaxPostResult.Dropped), Integer(lDroppedResult));
  finally
    ReleaseAndJoinThread(lRelease, lThread);
    lRelease.Free;
    lStarted.Free;
  end;
end;

procedure TTestPostResult.PostResultTypedAutoSubscribeIsNotNoTopic;
var
  lBus: ImaxBus;
  lPostResult: TmaxPostResult;
  lTarget: TAutoSubDerived;
begin
  lBus := maxBus;
  lBus.Clear;
  lTarget := TAutoSubDerived.Create;
  try
    AutoSubscribe(lTarget);
    lPostResult := maxBusObj(lBus).PostResult<integer>(7);
    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lTarget.IntHits);
    CheckEquals(7, lTarget.LastInt);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultNamedOfAutoSubscribeIsNotNoTopic;
var
  lBus: ImaxBus;
  lPostResult: TmaxPostResult;
  lTarget: TAutoSubDerived;
begin
  lBus := maxBus;
  lBus.Clear;
  lTarget := TAutoSubDerived.Create;
  try
    AutoSubscribe(lTarget);
    lPostResult := maxBusObj(lBus).PostResultNamedOf<integer>('data', 88);
    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lTarget.DataHits);
    CheckEquals(88, lTarget.LastData);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultGuidOfAutoSubscribeIsNotNoTopic;
var
  lBus: ImaxBus;
  lPostResult: TmaxPostResult;
  lTarget: TAutoSubGuid;
begin
  lBus := maxBus;
  lBus.Clear;
  lTarget := TAutoSubGuid.Create;
  try
    AutoSubscribe(lTarget);
    lPostResult := maxBusObj(lBus).PostResultGuidOf<IIntEvent>(TIntEvent.Create(42));
    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lTarget.GuidHits);
    CheckEquals(42, lTarget.LastGuidValue);
  finally
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultTypedAutoSubscribeAsyncReturnsQueued;
var
  lBus: ImaxBus;
  lPostResult: TmaxPostResult;
  lPrevScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lTarget: TAutoSubDeferred;
begin
  lBus := maxBus;
  lBus.Clear;
  lPrevScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lTarget := TAutoSubDeferred.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    AutoSubscribe(lTarget);

    lPostResult := maxBusObj(lBus).PostResult<integer>(17);

    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lTarget.IntHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lTarget.IntHits);
    CheckEquals(17, lTarget.LastInt);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    maxSetAsyncScheduler(lPrevScheduler);
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultNamedOfAutoSubscribeBackgroundReturnsQueued;
var
  lBus: ImaxBus;
  lPostResult: TmaxPostResult;
  lPrevScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lTarget: TAutoSubDeferred;
begin
  lBus := maxBus;
  lBus.Clear;
  lPrevScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lTarget := TAutoSubDeferred.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    AutoSubscribe(lTarget);

    lPostResult := maxBusObj(lBus).PostResultNamedOf<integer>('data.defer', 88);

    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lTarget.DataHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lTarget.DataHits);
    CheckEquals(88, lTarget.LastData);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    maxSetAsyncScheduler(lPrevScheduler);
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultGuidOfAutoSubscribeMainReturnsQueued;
var
  lPostResult: TmaxPostResult;
  lPrevScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lTarget: TAutoSubDeferred;
begin
  maxBus.Clear;
  lPrevScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lTarget := TAutoSubDeferred.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToAsync);
    AutoSubscribe(lTarget);

    lPostResult := PostGuidResultOffMain(maxBus, TIntEvent.Create(42));

    CheckEquals(Integer(TmaxPostResult.Queued), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lTarget.GuidHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lTarget.GuidHits);
    CheckEquals(42, lTarget.LastGuidValue);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    AutoUnsubscribe(lTarget);
    lTarget.Free;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    maxSetAsyncScheduler(lPrevScheduler);
    maxBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultTypedAsyncSubscriberReportsInline;
var
  lBus: ImaxBus;
  lHits: integer;
  lPostResult: TmaxPostResult;
  lScheduler: TReverseScheduler;
begin
  lScheduler := TReverseScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lHits := 0;
  try
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue <> 0 then
          Inc(lHits);
      end,
      TmaxDelivery.Async);

    lPostResult := maxBusObj(lBus).PostResult<integer>(21);

    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lHits);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultNamedOfBackgroundSubscriberReportsInline;
const
  cName = 'postresult.named.background.inline';
var
  lBus: ImaxBus;
  lHits: integer;
  lPostResult: TmaxPostResult;
  lScheduler: TReverseScheduler;
begin
  lScheduler := TReverseScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lHits := 0;
  try
    maxBusObj(lBus).SubscribeNamedOf<integer>(cName,
      procedure(const aValue: integer)
      begin
        if aValue <> 0 then
          Inc(lHits);
      end,
      TmaxDelivery.Background);

    lPostResult := maxBusObj(lBus).PostResultNamedOf<integer>(cName, 22);

    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lHits);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    lBus.Clear;
  end;
end;

procedure TTestPostResult.PostResultGuidOfMainSubscriberReportsInline;
var
  lBus: ImaxBus;
  lHits: integer;
  lPostResult: TmaxPostResult;
  lScheduler: TReverseScheduler;
begin
  lScheduler := TReverseScheduler.Create;
  lBus := TmaxBus.Create(lScheduler);
  lHits := 0;
  try
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToAsync);
    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if aValue <> nil then
          Inc(lHits);
      end,
      TmaxDelivery.Main);

    lPostResult := PostGuidResultOffMain(lBus, TIntEvent.Create(23));

    CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lPostResult));
    CheckEquals(1, lScheduler.AsyncCount);
    CheckEquals(0, lHits);

    lScheduler.DrainAsyncReverse;

    CheckEquals(1, lHits);
  finally
    lScheduler.DrainAsyncReverse;
    lScheduler.DrainMainReverse;
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    lBus.Clear;
  end;
end;

{ TTestDispatchErrorDetails }

procedure TTestDispatchErrorDetails.AssertSingleCoalescedDetail(const aTopicName: string;
  const aDetails: TArray<TmaxDispatchErrorDetail>);
begin
  CheckEquals(1, Length(aDetails));
  CheckEquals('Exception', aDetails[0].ExceptionClassName);
  CheckEquals('coalesced-detail', aDetails[0].ExceptionMessage);
  CheckEquals(aTopicName, aDetails[0].Topic);
  CheckEquals(Integer(TmaxDelivery.Posting), Integer(aDetails[0].Delivery));
  Check(aDetails[0].SubscriberToken > 0);
  CheckEquals(Integer(TmaxDispatchSubscriberKind.Exact), Integer(aDetails[0].SubscriberKind));
  CheckEquals(0, aDetails[0].SubscriberIndex);
end;

procedure TTestDispatchErrorDetails.IncludesSubscriberMetadataForPost;
var
  lBus: ImaxBus;
  lTypeName: string;
begin
  lBus := maxBus;
  lBus.Clear;
  lTypeName := GetTypeName(TypeInfo(integer));

  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('detail-first');
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('detail-second');
    end,
    TmaxDelivery.Posting);

  try
    maxBusObj(lBus).Post<integer>(7);
    Check(False, 'Expected EmaxDispatchError');
  except
    on lEx: EmaxDispatchError do
    begin
      CheckEquals(2, lEx.Inner.Count);
      CheckEquals(2, Length(lEx.Details));

      CheckEquals('Exception', lEx.Details[0].ExceptionClassName);
      CheckEquals('detail-first', lEx.Details[0].ExceptionMessage);
      CheckEquals(lTypeName, lEx.Details[0].Topic);
      CheckEquals(Integer(TmaxDelivery.Posting), Integer(lEx.Details[0].Delivery));
      Check(lEx.Details[0].SubscriberToken > 0);
      CheckEquals(Integer(TmaxDispatchSubscriberKind.Exact), Integer(lEx.Details[0].SubscriberKind));
      CheckEquals(0, lEx.Details[0].SubscriberIndex);

      CheckEquals('Exception', lEx.Details[1].ExceptionClassName);
      CheckEquals('detail-second', lEx.Details[1].ExceptionMessage);
      CheckEquals(lTypeName, lEx.Details[1].Topic);
      CheckEquals(Integer(TmaxDelivery.Posting), Integer(lEx.Details[1].Delivery));
      Check(lEx.Details[1].SubscriberToken > 0);
      CheckEquals(Integer(TmaxDispatchSubscriberKind.Exact), Integer(lEx.Details[1].SubscriberKind));
      CheckEquals(1, lEx.Details[1].SubscriberIndex);
    end;
  end;
end;

procedure TTestDispatchErrorDetails.IncludesMetadataForCoalescedAsyncHook;
type
  TCoalescedCapture = record
    TopicName: string;
    WasDispatchError: boolean;
    InnerCount: integer;
    Details: TArray<TmaxDispatchErrorDetail>;
  end;
var
  lBus: ImaxBus;
  lEvent: TKeyed;
  lPrevScheduler: IEventNexusScheduler;
  lSignal: TEvent;
  lCaptured: TCoalescedCapture;
begin
  lBus := maxBus;
  lBus.Clear;
  lSignal := TEvent.Create(nil, True, False, '');
  lPrevScheduler := maxGetAsyncScheduler;
  lCaptured := Default(TCoalescedCapture);
  maxSetAsyncScheduler(TInlineScheduler.Create);
  maxSetAsyncErrorHandler(
    procedure(const aTopic: string; const aE: Exception)
    begin
      lCaptured.TopicName := aTopic;
      lCaptured.WasDispatchError := aE is EmaxDispatchError;
      if lCaptured.WasDispatchError then
      begin
        lCaptured.InnerCount := EmaxDispatchError(aE).Inner.Count;
        lCaptured.Details := Copy(EmaxDispatchError(aE).Details);
      end;
      lSignal.SetEvent;
    end);
  maxBusObj(lBus).EnableCoalesceOf<TKeyed>(
    function(const aValue: TKeyed): TmaxString
    begin
      Result := aValue.Key;
    end,
    0);
  try
    maxBusObj(lBus).Subscribe<TKeyed>(
      procedure(const aValue: TKeyed)
      begin
        raise Exception.Create('coalesced-detail');
      end,
      TmaxDelivery.Posting);

    lEvent.Key := 'K';
    lEvent.Value := 10;
    maxBusObj(lBus).Post<TKeyed>(lEvent);

    Check(lSignal.WaitFor(2000) = wrSignaled, 'Async error hook was not called');
    Check(lCaptured.WasDispatchError, 'Expected EmaxDispatchError from coalesced path');
    CheckEquals(1, lCaptured.InnerCount);
    CheckEquals(GetTypeName(TypeInfo(TKeyed)), lCaptured.TopicName);
    AssertSingleCoalescedDetail(lCaptured.TopicName, lCaptured.Details);
  finally
    maxBusObj(lBus).EnableCoalesceOf<TKeyed>(nil);
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSignal.Free;
  end;
end;

procedure TTestDispatchErrorDetails.WildcardSubscriberFailuresExposeWildcardMetadata;
var
  lBus: ImaxBus;
begin
  lBus := maxBus;
  lBus.Clear;

  maxBusObj(lBus).SubscribeNamedWildcard('detail.*',
    procedure
    begin
      raise Exception.Create('wildcard-detail');
    end,
    TmaxDelivery.Posting);

  try
    lBus.PostNamed('detail.alpha');
    Check(False, 'Expected EmaxDispatchError');
  except
    on lEx: EmaxDispatchError do
    begin
      CheckEquals(1, lEx.Inner.Count);
      CheckEquals(1, Length(lEx.Details));
      CheckEquals('Exception', lEx.Details[0].ExceptionClassName);
      CheckEquals('wildcard-detail', lEx.Details[0].ExceptionMessage);
      CheckEquals(UpperCase('detail.alpha'), lEx.Details[0].Topic);
      CheckEquals(Integer(TmaxDelivery.Posting), Integer(lEx.Details[0].Delivery));
      Check(lEx.Details[0].SubscriberToken > 0);
      CheckEquals(Integer(TmaxDispatchSubscriberKind.Wildcard), Integer(lEx.Details[0].SubscriberKind));
      CheckEquals(0, lEx.Details[0].SubscriberIndex);
    end;
  end;
end;

{ TTestTracingHooks }

procedure TTestTracingHooks.EmitsEnqueueInvokeStartAndEnd;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lEvents: TArray<TmaxDispatchTrace>;
  lIdx: integer;
  lEnqueueIdx: integer;
  lStartIdx: integer;
  lEndIdx: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lPrevScheduler := maxGetAsyncScheduler;
  lEvents := nil;
  maxSetAsyncScheduler(TInlineScheduler.Create);
  maxSetDispatchTrace(
    procedure(const aTrace: TmaxDispatchTrace)
    var
      lCount: integer;
    begin
      lCount := Length(lEvents);
      SetLength(lEvents, lCount + 1);
      lEvents[lCount] := aTrace;
    end);
  try
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue = -1 then
          Exit;
      end,
      TmaxDelivery.Async);
    maxBusObj(lBus).Post<integer>(5);
    lEnqueueIdx := -1;
    lStartIdx := -1;
    lEndIdx := -1;
    for lIdx := 0 to High(lEvents) do
    begin
      if (lEnqueueIdx = -1) and (lEvents[lIdx].Kind = TmaxTraceKind.TraceEnqueue) then
        lEnqueueIdx := lIdx;
      if (lStartIdx = -1) and (lEvents[lIdx].Kind = TmaxTraceKind.TraceInvokeStart) then
        lStartIdx := lIdx;
      if (lEndIdx = -1) and (lEvents[lIdx].Kind = TmaxTraceKind.TraceInvokeEnd) then
        lEndIdx := lIdx;
    end;
    Check(lEnqueueIdx >= 0, 'Missing TraceEnqueue event');
    Check(lStartIdx >= 0, 'Missing TraceInvokeStart event');
    Check(lEndIdx >= 0, 'Missing TraceInvokeEnd event');
    Check(lStartIdx > lEnqueueIdx, 'InvokeStart should happen after enqueue');
    Check(lEndIdx > lStartIdx, 'InvokeEnd should happen after InvokeStart');
    CheckEquals(GetTypeName(TypeInfo(integer)), lEvents[lEnqueueIdx].Topic);
    CheckEquals(Integer(TmaxDelivery.Posting), Integer(lEvents[lEnqueueIdx].Delivery));
    CheckEquals(GetTypeName(TypeInfo(integer)), lEvents[lStartIdx].Topic);
    CheckEquals(Integer(TmaxDelivery.Async), Integer(lEvents[lStartIdx].Delivery));
    Check(lEvents[lEndIdx].DurationUs >= 0);
  finally
    maxSetDispatchTrace(nil);
    maxSetAsyncScheduler(lPrevScheduler);
  end;
end;

procedure TTestTracingHooks.EmitsInvokeError;
var
  lBus: ImaxBus;
  lPrevScheduler: IEventNexusScheduler;
  lEvents: TArray<TmaxDispatchTrace>;
  lIdx: integer;
  lErrorIdx: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lPrevScheduler := maxGetAsyncScheduler;
  lEvents := nil;
  maxSetAsyncScheduler(TInlineScheduler.Create);
  maxSetDispatchTrace(
    procedure(const aTrace: TmaxDispatchTrace)
    var
      lCount: integer;
    begin
      lCount := Length(lEvents);
      SetLength(lEvents, lCount + 1);
      lEvents[lCount] := aTrace;
    end);
  try
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        raise Exception.Create('trace-error');
      end,
      TmaxDelivery.Async);
    maxBusObj(lBus).Post<integer>(9);

    lErrorIdx := -1;
    for lIdx := 0 to High(lEvents) do
      if lEvents[lIdx].Kind = TmaxTraceKind.TraceInvokeError then
      begin
        lErrorIdx := lIdx;
        Break;
      end;

    Check(lErrorIdx >= 0, 'Missing TraceInvokeError event');
    CheckEquals(GetTypeName(TypeInfo(integer)), lEvents[lErrorIdx].Topic);
    CheckEquals(Integer(TmaxDelivery.Async), Integer(lEvents[lErrorIdx].Delivery));
    CheckEquals('Exception', lEvents[lErrorIdx].ExceptionClassName);
    CheckEquals('trace-error', lEvents[lErrorIdx].ExceptionMessage);
    Check(lEvents[lErrorIdx].DurationUs >= 0);
  finally
    maxSetDispatchTrace(nil);
    maxSetAsyncScheduler(lPrevScheduler);
  end;
end;

procedure TTestTracingHooks.DisabledTraceProducesNoCallbacks;
var
  lBus: ImaxBus;
  lTraceCalls: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lTraceCalls := 0;
  maxSetDispatchTrace(
    procedure(const aTrace: TmaxDispatchTrace)
    begin
      Inc(lTraceCalls);
      if aTrace.DurationUs = -1 then
        Exit;
    end);
  maxSetDispatchTrace(nil);
  try
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        if aValue = -1 then
          Exit;
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).Post<integer>(1);
    CheckEquals(0, lTraceCalls);
  finally
    maxSetDispatchTrace(nil);
  end;
end;

{ TTestBulkDispatch }

procedure TTestBulkDispatch.TypedBulkPreservesOrder;
var
  lBus: ImaxBus;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lValues := TList<integer>.Create;
  try
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostMany<integer>([1, 2, 3, 4]);
    CheckEquals(4, lValues.Count);
    CheckEquals(1, lValues[0]);
    CheckEquals(2, lValues[1]);
    CheckEquals(3, lValues[2]);
    CheckEquals(4, lValues[3]);
  finally
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.NamedOfBulkPreservesOrder;
var
  lBus: ImaxBus;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lValues := TList<integer>.Create;
  try
    maxBusObj(lBus).SubscribeNamedOf<integer>('bulk.named',
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostManyNamedOf<integer>('bulk.named', [7, 8, 9]);
    CheckEquals(3, lValues.Count);
    CheckEquals(7, lValues[0]);
    CheckEquals(8, lValues[1]);
    CheckEquals(9, lValues[2]);
  finally
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.GuidOfBulkPreservesOrder;
var
  lBus: ImaxBus;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lValues := TList<integer>.Create;
  try
    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        lValues.Add(aValue.GetValue);
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).PostManyGuidOf<IIntEvent>([
      IIntEvent(TIntEvent.Create(5)),
      IIntEvent(TIntEvent.Create(6))
    ]);
    CheckEquals(2, lValues.Count);
    CheckEquals(5, lValues[0]);
    CheckEquals(6, lValues[1]);
  finally
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.BulkAggregatesAcrossItems;
var
  lBus: ImaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('bulk-first');
    end,
    TmaxDelivery.Posting);
  maxBusObj(lBus).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('bulk-second');
    end,
    TmaxDelivery.Posting);
  try
    maxBusObj(lBus).PostMany<integer>([10, 20]);
    Check(False, 'Expected EmaxDispatchError from bulk post');
  except
    on lEx: EmaxDispatchError do
    begin
      CheckEquals(4, lEx.Inner.Count);
      CheckEquals(4, Length(lEx.Details));
      CheckEquals('bulk-first', lEx.Inner[0].Message);
      CheckEquals('bulk-second', lEx.Inner[1].Message);
      CheckEquals('bulk-first', lEx.Inner[2].Message);
      CheckEquals('bulk-second', lEx.Inner[3].Message);
    end;
  end;
end;

procedure TTestBulkDispatch.TypedAsyncPostsPreserveOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lPreviousScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Async);
    maxBusObj(lBus).Post<integer>(1);
    maxBusObj(lBus).Post<integer>(2);
    maxBusObj(lBus).Post<integer>(3);
    CheckEquals(1, lScheduler.AsyncCount, 'Same-topic async posts should expose only one runnable batch at a time');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(1, lValues[0]);
    CheckEquals(2, lValues[1]);
    CheckEquals(3, lValues[2]);
  finally
    maxSetAsyncScheduler(lPreviousScheduler);
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.NamedOfMainPostsPreserveOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lDone: TEvent;
  lPreviousScheduler: IEventNexusScheduler;
  lRaisedMessage: string;
  lScheduler: TReverseScheduler;
  lThread: TThread;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lDone := TEvent.Create(nil, True, False, '');
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToAsync);
    maxBusObj(lBus).SubscribeNamedOf<integer>('post.ordered.main',
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Main);
    lRaisedMessage := '';
    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          maxBusObj(lBus).PostNamedOf<integer>('post.ordered.main', 4);
          maxBusObj(lBus).PostNamedOf<integer>('post.ordered.main', 5);
          maxBusObj(lBus).PostNamedOf<integer>('post.ordered.main', 6);
        except
          on e: Exception do
            lRaisedMessage := e.ClassName + ': ' + e.Message;
        end;
        lDone.SetEvent;
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;
    Check(lDone.WaitFor(1000) = wrSignaled, 'Timed out waiting for off-main named posts');
    lThread.WaitFor;
    lThread.Free;
    CheckEquals('', lRaisedMessage);
    CheckEquals(1, lScheduler.AsyncCount, 'Main delivery posts should serialize same-topic batches before scheduler dequeue');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(4, lValues[0]);
    CheckEquals(5, lValues[1]);
    CheckEquals(6, lValues[2]);
  finally
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    maxSetAsyncScheduler(lPreviousScheduler);
    lDone.Free;
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.GuidOfBackgroundPostsPreserveOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lPreviousScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        lValues.Add(aValue.GetValue);
      end,
      TmaxDelivery.Background);
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(7));
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(8));
    maxBusObj(lBus).PostGuidOf<IIntEvent>(TIntEvent.Create(9));
    CheckEquals(1, lScheduler.AsyncCount, 'Background delivery posts should preserve same-topic order without scheduler FIFO');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(7, lValues[0]);
    CheckEquals(8, lValues[1]);
    CheckEquals(9, lValues[2]);
  finally
    maxSetAsyncScheduler(lPreviousScheduler);
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.TypedAsyncBulkPreservesOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lPreviousScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Async);
    maxBusObj(lBus).PostMany<integer>([1, 2, 3]);
    CheckEquals(1, lScheduler.AsyncCount, 'Same-topic async bulk should expose only one runnable batch at a time');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(1, lValues[0]);
    CheckEquals(2, lValues[1]);
    CheckEquals(3, lValues[2]);
  finally
    maxSetAsyncScheduler(lPreviousScheduler);
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.NamedOfMainBulkPreservesOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lDone: TEvent;
  lPreviousScheduler: IEventNexusScheduler;
  lRaisedMessage: string;
  lScheduler: TReverseScheduler;
  lThread: TThread;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lDone := TEvent.Create(nil, True, False, '');
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToAsync);
    maxBusObj(lBus).SubscribeNamedOf<integer>('bulk.ordered.main',
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end,
      TmaxDelivery.Main);
    lRaisedMessage := '';
    lThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          maxBusObj(lBus).PostManyNamedOf<integer>('bulk.ordered.main', [4, 5, 6]);
        except
          on e: Exception do
            lRaisedMessage := e.ClassName + ': ' + e.Message;
        end;
        lDone.SetEvent;
      end);
    lThread.FreeOnTerminate := False;
    lThread.Start;
    Check(lDone.WaitFor(1000) = wrSignaled, 'Timed out waiting for off-main named bulk post');
    lThread.WaitFor;
    lThread.Free;
    CheckEquals('', lRaisedMessage);
    CheckEquals(1, lScheduler.AsyncCount, 'Main delivery in console mode should serialize same-topic batches before scheduler dequeue');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(4, lValues[0]);
    CheckEquals(5, lValues[1]);
    CheckEquals(6, lValues[2]);
  finally
    maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
    maxSetAsyncScheduler(lPreviousScheduler);
    lDone.Free;
    lValues.Free;
  end;
end;

procedure TTestBulkDispatch.GuidOfBackgroundBulkPreservesOrderAgainstReorderingScheduler;
var
  lBus: ImaxBus;
  lPreviousScheduler: IEventNexusScheduler;
  lScheduler: TReverseScheduler;
  lValues: TList<integer>;
begin
  lBus := maxBus;
  lBus.Clear;
  lPreviousScheduler := maxGetAsyncScheduler;
  lScheduler := TReverseScheduler.Create;
  lValues := TList<integer>.Create;
  try
    maxSetAsyncScheduler(lScheduler);
    maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        lValues.Add(aValue.GetValue);
      end,
      TmaxDelivery.Background);
    maxBusObj(lBus).PostManyGuidOf<IIntEvent>([
      IIntEvent(TIntEvent.Create(7)),
      IIntEvent(TIntEvent.Create(8)),
      IIntEvent(TIntEvent.Create(9))
    ]);
    CheckEquals(1, lScheduler.AsyncCount, 'Background delivery should preserve same-topic order without relying on scheduler FIFO');
    lScheduler.DrainAsyncReverse;
    CheckEquals(3, lValues.Count);
    CheckEquals(7, lValues[0]);
    CheckEquals(8, lValues[1]);
    CheckEquals(9, lValues[2]);
  finally
    maxSetAsyncScheduler(lPreviousScheduler);
    lValues.Free;
  end;
end;

{ TTestWildcardNamed }

procedure TTestWildcardNamed.AssertInvalidWildcardPattern(const aPattern: string; const aMessage: string);
var
  lBus: ImaxBus;
  lRaised: boolean;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lRaised := False;
  lSub := nil;
  try
    lSub := maxBusObj(lBus).SubscribeNamedWildcard(aPattern,
      procedure
      begin
      end,
      TmaxDelivery.Posting);
  except
    on EmaxInvalidSubscription do
      lRaised := True;
  end;
  Check(lRaised, aMessage);
  lSub := nil;
end;

procedure TTestWildcardNamed.PrefixAndGlobalWildcardMatch;
var
  lBus: ImaxBus;
  lExactHits: integer;
  lPrefixHits: integer;
  lGlobalHits: integer;
  lOrder: TList<string>;
begin
  lBus := maxBus;
  lBus.Clear;
  lExactHits := 0;
  lPrefixHits := 0;
  lGlobalHits := 0;
  lOrder := TList<string>.Create;
  try
    maxBusObj(lBus).SubscribeNamed('order.created',
      procedure
      begin
        Inc(lExactHits);
        lOrder.Add('exact');
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).SubscribeNamedWildcard('order.*',
      procedure
      begin
        Inc(lPrefixHits);
        lOrder.Add('prefix');
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).SubscribeNamedWildcard('*',
      procedure
      begin
        Inc(lGlobalHits);
        lOrder.Add('global');
      end,
      TmaxDelivery.Posting);

    maxBusObj(lBus).PostNamed('order.created');
    maxBusObj(lBus).PostNamed('order.updated');
    maxBusObj(lBus).PostNamed('user.created');

    CheckEquals(1, lExactHits);
    CheckEquals(2, lPrefixHits);
    CheckEquals(3, lGlobalHits);
    CheckEquals(6, lOrder.Count);
    CheckEquals('exact', lOrder[0]);
    CheckEquals('prefix', lOrder[1]);
    CheckEquals('global', lOrder[2]);
    CheckEquals('prefix', lOrder[3]);
    CheckEquals('global', lOrder[4]);
    CheckEquals('global', lOrder[5]);
  finally
    lOrder.Free;
  end;
end;

procedure TTestWildcardNamed.InvalidWildcardPatternsAreRejected;
var
  lBus: ImaxBus;
begin
  lBus := maxBus;
  lBus.Clear;
  AssertInvalidWildcardPattern('', 'Empty wildcard pattern should be rejected');
  AssertInvalidWildcardPattern('room', 'Pattern without trailing * should be rejected');
  AssertInvalidWildcardPattern('room.*.detail*', 'Pattern with more than one * should be rejected');
  AssertInvalidWildcardPattern('**', 'Double-star wildcard pattern should be rejected');
end;

procedure TTestWildcardNamed.LongerPrefixWildcardPrecedenceWins;
var
  lBus: ImaxBus;
  lOrder: TList<string>;
begin
  lBus := maxBus;
  lBus.Clear;
  lOrder := TList<string>.Create;
  try
    maxBusObj(lBus).SubscribeNamedWildcard('room.*',
      procedure
      begin
        lOrder.Add('short');
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).SubscribeNamedWildcard('room.kitchen.*',
      procedure
      begin
        lOrder.Add('long');
      end,
      TmaxDelivery.Posting);

    maxBusObj(lBus).PostNamed('room.kitchen.42');
    CheckEquals(2, lOrder.Count);
    CheckEquals('long', lOrder[0]);
    CheckEquals('short', lOrder[1]);
  finally
    lOrder.Free;
  end;
end;

procedure TTestWildcardNamed.UnsubscribeStopsWildcardDelivery;
var
  lBus: ImaxBus;
  lHits: integer;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  lSub := maxBusObj(lBus).SubscribeNamedWildcard('room.*',
    procedure
    begin
      Inc(lHits);
    end,
    TmaxDelivery.Posting);

  maxBusObj(lBus).PostNamed('room.1');
  lSub.Unsubscribe;
  maxBusObj(lBus).PostNamed('room.2');
  CheckEquals(1, lHits);
end;

procedure TTestWildcardNamed.WildcardDispatchesWithoutPrecreatedNamedTopic;
var
  lBus: ImaxBus;
  lHits: integer;
  lResult: TmaxPostResult;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  maxBusObj(lBus).SubscribeNamedWildcard('dynamic.*',
    procedure
    begin
      Inc(lHits);
    end,
    TmaxDelivery.Posting);

  lResult := maxBusObj(lBus).PostResultNamed('dynamic.alpha');
  CheckEquals(Integer(TmaxPostResult.DispatchedInline), Integer(lResult));
  CheckEquals(1, lHits);
end;

procedure TTestWildcardNamed.SamePrefixLengthUsesSubscriptionOrder;
var
  lBus: ImaxBus;
  lOrder: TList<string>;
begin
  lBus := maxBus;
  lBus.Clear;
  lOrder := TList<string>.Create;
  try
    maxBusObj(lBus).SubscribeNamedWildcard('room.*',
      procedure
      begin
        lOrder.Add('first');
      end,
      TmaxDelivery.Posting);
    maxBusObj(lBus).SubscribeNamedWildcard('room.*',
      procedure
      begin
        lOrder.Add('second');
      end,
      TmaxDelivery.Posting);

    maxBusObj(lBus).PostNamed('room.42');
    CheckEquals(2, lOrder.Count);
    CheckEquals('first', lOrder[0]);
    CheckEquals('second', lOrder[1]);
  finally
    lOrder.Free;
  end;
end;

{ TTestDelayedPosting }

procedure TTestDelayedPosting.NamedDelayedPostWaitsBeforeDelivery;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lStartMs: UInt64;
  lElapsedMs: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := lBus.SubscribeNamed('delayed.named',
      procedure
      begin
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);
    lStartMs := GetTickCount64;
    lHandle := lBus.PostDelayedNamed('delayed.named', 120);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(40) = wrTimeout, 'Delayed post fired too early');
    Check(lDone.WaitFor(600) = wrSignaled, 'Delayed post did not fire');
    lElapsedMs := integer(GetTickCount64 - lStartMs);
    Check(lElapsedMs >= 80, Format('Delayed post fired too quickly (%dms)', [lElapsedMs]));
    Check(not lHandle.IsPending);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.NamedOfDelayedPostWaitsBeforeDelivery;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lStartMs: UInt64;
  lElapsedMs: integer;
  lReceived: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  lReceived := 0;
  try
    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>('delayed.namedof',
      procedure(const aValue: integer)
      begin
        lReceived := aValue;
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);
    lStartMs := GetTickCount64;
    lHandle := maxBusObj(lBus).PostDelayedNamedOf<integer>('delayed.namedof', 73, 120);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(40) = wrTimeout, 'Delayed named-of post fired too early');
    Check(lDone.WaitFor(600) = wrSignaled, 'Delayed named-of post did not fire');
    lElapsedMs := integer(GetTickCount64 - lStartMs);
    Check(lElapsedMs >= 80, Format('Delayed named-of post fired too quickly (%dms)', [lElapsedMs]));
    CheckEquals(73, lReceived);
    Check(not lHandle.IsPending);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.GuidDelayedPostWaitsBeforeDelivery;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lStartMs: UInt64;
  lElapsedMs: integer;
  lReceived: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  lReceived := 0;
  try
    lSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        if aValue <> nil then
        begin
          lReceived := aValue.GetValue;
        end;
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);
    lStartMs := GetTickCount64;
    lHandle := maxBusObj(lBus).PostDelayedGuidOf<IIntEvent>(TIntEvent.Create(91), 120);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(40) = wrTimeout, 'Delayed guid post fired too early');
    Check(lDone.WaitFor(600) = wrSignaled, 'Delayed guid post did not fire');
    lElapsedMs := integer(GetTickCount64 - lStartMs);
    Check(lElapsedMs >= 80, Format('Delayed guid post fired too quickly (%dms)', [lElapsedMs]));
    CheckEquals(91, lReceived);
    Check(not lHandle.IsPending);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.CancelPreventsTypedDelayedDelivery;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lHits: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);
    lHandle := maxBusObj(lBus).PostDelayed<integer>(42, 120);
    Check(lHandle <> nil);
    Check(lHandle.Cancel, 'Cancel should succeed while pending');
    Check(not lHandle.Cancel, 'Second cancel should report already consumed');
    Check(not lHandle.IsPending);
    Check(lDone.WaitFor(250) = wrTimeout, 'Canceled delayed post should not dispatch');
    CheckEquals(0, lHits);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.CancelNearDeadlineHasConsistentOutcome;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lDone: TEvent;
  lHandle: ImaxDelayedPost;
  lCanceled: boolean;
  lHits: integer;
  i: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);
    for i := 1 to 8 do
    begin
      lDone.ResetEvent;
      lHandle := maxBusObj(lBus).PostDelayed<integer>(i, 25);
      Check(lHandle <> nil);
      Sleep(20);
      lCanceled := lHandle.Cancel;
      if lCanceled then
      begin
        Check(lDone.WaitFor(120) = wrTimeout, 'Canceled near-deadline post should not dispatch');
      end else begin
        Check(lDone.WaitFor(250) = wrSignaled, 'Non-canceled near-deadline post should dispatch');
      end;
      Check(not lHandle.IsPending, 'Handle should not remain pending after cancel/fire boundary');
      Check(not lHandle.Cancel, 'Second cancel should be idempotent false');
    end;
    Check(lHits >= 0);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.ClearDropsPendingDelayedPosts;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lHits: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := lBus.SubscribeNamed('delayed.clear',
      procedure
      begin
        Inc(lHits);
      end,
      TmaxDelivery.Posting);
    lHandle := lBus.PostDelayedNamed('delayed.clear', 100);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);

    lBus.Clear;

    lSub := lBus.SubscribeNamed('delayed.clear',
      procedure
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    Check(lDone.WaitFor(250) = wrTimeout, 'Delayed post scheduled before Clear should be dropped');
    CheckEquals(0, lHits);
    Check(not lHandle.IsPending);
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.ZeroDelayDispatchesAndUpdatesMetrics;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lHits: integer;
  lStats: TmaxTopicStats;
begin
  lBus := maxBus;
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    lHandle := maxBusObj(lBus).PostDelayed<integer>(7, 0);
    Check(lHandle <> nil);
    Check(lDone.WaitFor(1000) = wrSignaled, 'Zero-delay post was not delivered');
    CheckEquals(1, lHits);

    lStats := maxBusObj(lBus).GetStatsFor<integer>;
    Check(lStats.PostsTotal >= 1, 'Expected PostsTotal increment for delayed post');
    Check(lStats.DeliveredTotal >= 1, 'Expected DeliveredTotal increment for delayed post');
    Check(not lHandle.IsPending);
    Check(not lHandle.Cancel, 'Cancel should fail after delayed post has already dispatched');
    lSub := nil;
  finally
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.LargeDelayRemainsPendingUntilCanceled;
const
  cLongDelayMs = 30000;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lHits: integer;
  lPrevScheduler: IEventNexusScheduler;
begin
  lBus := maxBus;
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(THoldDelayedScheduler.Create);
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := lBus.SubscribeNamed('delayed.long',
      procedure
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    lHandle := lBus.PostDelayedNamed('delayed.long', cLongDelayMs);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(200) = wrTimeout, 'Large-delay post fired unexpectedly early');
    CheckEquals(0, lHits);

    Check(lHandle.Cancel, 'Cancel should succeed for a still-pending large-delay post');
    Check(not lHandle.IsPending);
    Check(lDone.WaitFor(200) = wrTimeout, 'Canceled large-delay post should remain canceled');
    CheckEquals(0, lHits);
    lSub := nil;
  finally
    maxSetAsyncScheduler(lPrevScheduler);
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.TypedLargeDelayRemainsPendingUntilCanceled;
const
  cLongDelayMs = 30000;
var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
  lHandle: ImaxDelayedPost;
  lDone: TEvent;
  lHits: integer;
  lPrevScheduler: IEventNexusScheduler;
begin
  lBus := maxBus;
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(THoldDelayedScheduler.Create);
  lBus.Clear;
  lHits := 0;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    lHandle := maxBusObj(lBus).PostDelayed<integer>(77, cLongDelayMs);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(200) = wrTimeout, 'Large-delay typed post fired unexpectedly early');
    CheckEquals(0, lHits);

    Check(lHandle.Cancel, 'Cancel should succeed for pending typed delayed post');
    Check(not lHandle.IsPending);
    Check(not lHandle.Cancel);
    Check(lDone.WaitFor(200) = wrTimeout, 'Canceled typed delayed post should remain canceled');
    CheckEquals(0, lHits);
    lSub := nil;
  finally
    maxSetAsyncScheduler(lPrevScheduler);
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.TypedDelayedFailureWithoutAsyncHookStaysSilent;
const
  cDelayMs = 25;
var
  lBus: ImaxBus;
  lDone: TEvent;
  lHandle: ImaxDelayedPost;
  lHits: integer;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lDone := TEvent.Create(nil, True, False, '');
  lPrevScheduler := maxGetAsyncScheduler;
  lHits := 0;
  try
    lBus.Clear;
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    maxSetAsyncErrorHandler(nil);

    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Inc(lHits);
        lDone.SetEvent;
        raise Exception.Create('typed delayed silent boom');
      end,
      TmaxDelivery.Posting);

    try
      lHandle := maxBusObj(lBus).PostDelayed<integer>(17, cDelayMs);
    except
      on e: Exception do
        raise Exception.Create('PostDelayed should not synchronously re-raise delayed failures without a hook: ' + e.Message);
    end;

    Check(lHandle <> nil);
    Check(lDone.WaitFor(2000) = wrSignaled, 'Typed delayed failure without hook should still execute the delayed post');
    CheckEquals(1, lHits);
    Check(not lHandle.IsPending, 'Delayed handle should not remain pending after the failing delayed post runs');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.TypedDelayedFailureForwardsAsyncHook;
const
  cDelayMs = 25;
var
  lCapture: TAsyncErrorCapture;
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
  lTypeName: string;
begin
  lBus := maxBus;
  lCapture := TAsyncErrorCapture.Create;
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lTypeName := GetTypeName(TypeInfo(integer));
  try
    lBus.Clear;
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    InstallAsyncErrorCapture(lCapture, lErrorEvent);

    lSub := maxBusObj(lBus).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        raise Exception.Create('typed delayed boom');
      end,
      TmaxDelivery.Posting);

    Check(maxBusObj(lBus).PostDelayed<integer>(17, cDelayMs) <> nil);
    Check(lErrorEvent.WaitFor(2000) = wrSignaled, 'Typed delayed failure did not reach the async error hook');
    AssertDelayedHookCapture(lCapture, lTypeName, 'typed delayed boom');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lCapture.Free;
    lErrorEvent.Free;
  end;
end;

procedure TTestDelayedPosting.NamedDelayedFailureForwardsAsyncHook;
const
  cDelayMs = 25;
var
  lCapture: TAsyncErrorCapture;
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lCapture := TAsyncErrorCapture.Create;
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  try
    lBus.Clear;
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    InstallAsyncErrorCapture(lCapture, lErrorEvent);

    lSub := lBus.SubscribeNamed('delayed.error.named',
      procedure
      begin
        raise Exception.Create('named delayed boom');
      end,
      TmaxDelivery.Posting);

    Check(lBus.PostDelayedNamed('delayed.error.named', cDelayMs) <> nil);
    Check(lErrorEvent.WaitFor(2000) = wrSignaled, 'Named delayed failure did not reach the async error hook');
    AssertDelayedHookCapture(lCapture, UpperCase('delayed.error.named'), 'named delayed boom');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lCapture.Free;
    lErrorEvent.Free;
  end;
end;

procedure TTestDelayedPosting.NamedOfDelayedFailureForwardsAsyncHook;
const
  cDelayMs = 25;
var
  lCapture: TAsyncErrorCapture;
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lCapture := TAsyncErrorCapture.Create;
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  try
    lBus.Clear;
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    InstallAsyncErrorCapture(lCapture, lErrorEvent);

    lSub := maxBusObj(lBus).SubscribeNamedOf<integer>('delayed.error.namedof',
      procedure(const aValue: integer)
      begin
        raise Exception.Create('namedof delayed boom');
      end,
      TmaxDelivery.Posting);

    Check(maxBusObj(lBus).PostDelayedNamedOf<integer>('delayed.error.namedof', 29, cDelayMs) <> nil);
    Check(lErrorEvent.WaitFor(2000) = wrSignaled, 'Named-of delayed failure did not reach the async error hook');
    AssertDelayedHookCapture(lCapture, UpperCase('delayed.error.namedof') + ':' + GetTypeName(TypeInfo(integer)),
      'namedof delayed boom');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lCapture.Free;
    lErrorEvent.Free;
  end;
end;

procedure TTestDelayedPosting.GuidDelayedFailureForwardsAsyncHook;
const
  cDelayMs = 25;
var
  lCapture: TAsyncErrorCapture;
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lExpectedTopic: string;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lCapture := TAsyncErrorCapture.Create;
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  lExpectedTopic := GuidToString(GetTypeData(TypeInfo(IIntEvent))^.Guid);
  try
    lBus.Clear;
    maxSetAsyncScheduler(TmaxRawThreadScheduler.Create);
    InstallAsyncErrorCapture(lCapture, lErrorEvent);

    lSub := maxBusObj(lBus).SubscribeGuidOf<IIntEvent>(
      procedure(const aValue: IIntEvent)
      begin
        raise Exception.Create('guid delayed boom');
      end,
      TmaxDelivery.Posting);

    Check(maxBusObj(lBus).PostDelayedGuidOf<IIntEvent>(TIntEvent.Create(41), cDelayMs) <> nil);
    Check(lErrorEvent.WaitFor(2000) = wrSignaled, 'Guid delayed failure did not reach the async error hook');
    AssertDelayedHookCapture(lCapture, lExpectedTopic, 'guid delayed boom');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lCapture.Free;
    lErrorEvent.Free;
  end;
end;

procedure TTestDelayedPosting.SchedulerFailureDelayedNamedForwardsAsyncHook;
const
  cDelayMs = 40;
var
  lCapture: TAsyncErrorCapture;
  lBus: ImaxBus;
  lErrorEvent: TEvent;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lCapture := TAsyncErrorCapture.Create;
  lPrevScheduler := maxGetAsyncScheduler;
  lErrorEvent := TEvent.Create(nil, True, False, '');
  try
    lBus.Clear;
    maxSetAsyncScheduler(TRaiseDelayedScheduler.Create);
    InstallAsyncErrorCapture(lCapture, lErrorEvent);

    lSub := lBus.SubscribeNamed('delayed.error.fallback',
      procedure
      begin
        raise Exception.Create('fallback delayed boom');
      end,
      TmaxDelivery.Posting);

    Check(lBus.PostDelayedNamed('delayed.error.fallback', cDelayMs) <> nil);
    Check(lErrorEvent.WaitFor(2000) = wrSignaled, 'Fallback delayed failure did not reach the async error hook');
    AssertDelayedHookCapture(lCapture, UpperCase('delayed.error.fallback'), 'fallback delayed boom');
  finally
    RestoreAsyncSchedulerState(lPrevScheduler);
    lSub := nil;
    lBus.Clear;
    lCapture.Free;
    lErrorEvent.Free;
  end;
end;

procedure TTestDelayedPosting.SchedulerFailureStillWaitsBeforeNamedDelivery;
const
  cDelayMs = 150;
var
  lBus: ImaxBus;
  lDone: TEvent;
  lHandle: ImaxDelayedPost;
  lHits: integer;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(TRaiseDelayedScheduler.Create);
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  lHits := 0;
  try
    lSub := lBus.SubscribeNamed('delayed.fail.named',
      procedure
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    lHandle := lBus.PostDelayedNamed('delayed.fail.named', cDelayMs);
    Check(lHandle <> nil);
    Check(lHandle.IsPending);
    Check(lDone.WaitFor(50) = wrTimeout, 'Delayed scheduler fallback dispatched too early');
    Check(lHandle.IsPending, 'Delayed scheduler fallback should remain pending before the delay expires');
    CheckEquals(0, lHits);

    Check(lDone.WaitFor(3000) = wrSignaled, 'Delayed scheduler fallback never delivered');
    CheckEquals(1, lHits);
    Check(not lHandle.IsPending, 'Handle should not stay pending after fallback delivery');
  finally
    lSub := nil;
    maxSetAsyncScheduler(lPrevScheduler);
    lDone.Free;
  end;
end;

procedure TTestDelayedPosting.SchedulerFailureCancelAndClearPreventDelayedDelivery;
const
  cDelayMs = 400;
var
  lBus: ImaxBus;
  lDone: TEvent;
  lHandleCancel: ImaxDelayedPost;
  lHandleClear: ImaxDelayedPost;
  lHits: integer;
  lPrevScheduler: IEventNexusScheduler;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lPrevScheduler := maxGetAsyncScheduler;
  maxSetAsyncScheduler(TRaiseDelayedScheduler.Create);
  lBus.Clear;
  lDone := TEvent.Create(nil, True, False, '');
  lHits := 0;
  try
    lSub := lBus.SubscribeNamed('delayed.fail.control',
      procedure
      begin
        Inc(lHits);
        lDone.SetEvent;
      end,
      TmaxDelivery.Posting);

    lHandleCancel := lBus.PostDelayedNamed('delayed.fail.control', cDelayMs);
    Check(lHandleCancel <> nil);
    Check(lHandleCancel.IsPending);
    Check(lHandleCancel.Cancel, 'Cancel should succeed while fallback delayed post is pending');
    Check(not lHandleCancel.IsPending);

    lHandleClear := lBus.PostDelayedNamed('delayed.fail.control', cDelayMs);
    Check(lHandleClear <> nil);
    Check(lHandleClear.IsPending);
    lBus.Clear;
    Check(not lHandleClear.IsPending, 'Clear should invalidate fallback delayed handles created before the clear boundary');

    Check(lDone.WaitFor(900) = wrTimeout, 'Canceled or cleared delayed fallback posts should not deliver');
    CheckEquals(0, lHits);
  finally
    lSub := nil;
    maxSetAsyncScheduler(lPrevScheduler);
    lDone.Free;
  end;
end;

{ TTestSchedulers }

function TTestSchedulers.WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): boolean;
var
  lStart: UInt64;
begin
  // NOTE: Do not use a single blocking WaitFor(aTimeoutMs) here.
  // In a console test runner there is no UI message loop. Any code scheduled to the
  // main thread (TThread.Synchronize/Queue or RunOnMain) will only execute when the
  // main thread calls CheckSynchronize. If we block inside WaitFor, those callbacks
  // never run, the event may never be signaled, and tests would hang or time out.
  // We therefore poll the event (WaitFor(0)), pump the synchronize queue, then yield.
  lStart := GetTickCount64;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      exit(True);

    CheckSynchronize(0);
    Sleep(1);
  until GetTickCount64 - lStart >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

procedure TTestSchedulers.ExerciseScheduler(const aScheduler: IEventNexusScheduler; const aName: string);
var
  lMainId, lAsyncId, lMainHandlerId: TThreadID;
  lAsyncEvent, lMainEvent, lDelayEvent: TEvent;
  lDelayStart: UInt64;
begin
  lAsyncEvent := TEvent.Create(nil, True, False, '');
  lMainEvent := TEvent.Create(nil, True, False, '');
  lDelayEvent := TEvent.Create(nil, True, False, '');
  try
    lMainId := TThread.CurrentThread.ThreadID;
    lAsyncId := lMainId;
    lMainHandlerId := 0;

    aScheduler.RunAsync(
      procedure
      begin
        lAsyncId := TThread.CurrentThread.ThreadID;
        lAsyncEvent.SetEvent;
      end);
    Check(WaitForSignal(lAsyncEvent, 1000), aName + ': RunAsync timed out');
    Check(lAsyncId <> lMainId, aName + ': RunAsync executed on main thread');

    aScheduler.RunOnMain(
      procedure
      begin
        lMainHandlerId := TThread.CurrentThread.ThreadID;
        lMainEvent.SetEvent;
      end);
    Check(WaitForSignal(lMainEvent, 1000), aName + ': RunOnMain timed out');
    CheckEquals(lMainId, lMainHandlerId, aName + ': RunOnMain did not execute on main thread');

    lDelayStart := GetTickCount64;
    aScheduler.RunDelayed(
      procedure
      begin
        lDelayEvent.SetEvent;
      end,
      100000);
    Check(WaitForSignal(lDelayEvent, 2000), aName + ': RunDelayed timed out');
    Check(GetTickCount64 - lDelayStart >= 50, aName + ': RunDelayed executed too early');
  finally
    lAsyncEvent.Free;
    lMainEvent.Free;
    lDelayEvent.Free;
  end;
end;

procedure TTestSchedulers.RawThreadScheduler;
begin
  ExerciseScheduler(TmaxRawThreadScheduler.Create, 'raw-thread');
end;

{$IFDEF max_DELPHI}
procedure TTestSchedulers.MaxAsyncScheduler;
begin
  ExerciseScheduler(CreateMaxAsyncScheduler, 'maxAsync');
end;

procedure TTestSchedulers.TTaskScheduler;
begin
  ExerciseScheduler(CreateTTaskScheduler, 'TTask');
end;
{$ENDIF}

{$IFDEF max_DELPHI}
procedure TTestSchedulers.SchedulerSwapUpdatesLiveBus;
var
  lBus: ImaxBus;
  lPrevSched: IEventNexusScheduler;
  lAsyncCalled: TEvent;
  lSub: ImaxSubscription;
begin
  lPrevSched := maxGetAsyncScheduler;
  lAsyncCalled := TEvent.Create(nil, True, False, '');
  lSub := nil;
  try
    lBus := maxBus;
    lBus.Clear;
    maxSetAsyncScheduler(TSignalScheduler.Create(lAsyncCalled));
    try
      lSub := lBus.SubscribeNamed('swap_async',
        procedure
        begin
        end,
        TmaxDelivery.Async);
      lBus.PostNamed('swap_async');
      Check(WaitForSignal(lAsyncCalled, 1000), 'Scheduler swap did not affect the live bus');
    finally
      lSub := nil;
      maxSetAsyncScheduler(lPrevSched);
    end;
  finally
    lAsyncCalled.Free;
  end;
end;

procedure TTestSchedulers.DefaultAsyncProbeReturnsSingleInstanceAcrossThreads;
var
  lExitCode: Cardinal;
begin
  lExitCode := RunProcessAndGetExitCode(ParamStr(0), '--default-async-race-probe');
  CheckEquals(0, Integer(lExitCode),
    Format('DefaultAsync race probe reported exit code %d', [lExitCode]));
end;
{$ENDIF}

{ TTestInterfaceGenerics }

procedure TTestInterfaceGenerics.VerifyPostAndTryPost(const aBus: ImaxBus; const aBusObj: TmaxBus;
  var aReceived: integer);
var
  lReceived: integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    lReceived := aValue;
  end;
{$ENDIF}
begin
  Check(aBus <> nil, 'Bus interface should be assigned');
  lReceived := 0;
  {$IFDEF max_FPC}
  aBus.Subscribe<integer>(@Handler, Posting);
  aBus.Post<integer>(42);
  CheckEquals(42, lReceived, 'Post/Subscribe delivery');
  Check(aBus.TryPost<integer>(43), 'TryPost should succeed');
  {$ELSE}
  aBusObj.Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      lReceived := aValue;
    end,
    Posting);
  aBusObj.Post<integer>(42);
  CheckEquals(42, lReceived, 'Post/Subscribe delivery');
  Check(aBusObj.TryPost<integer>(43), 'TryPost should succeed');
  {$ENDIF}
  CheckEquals(43, lReceived, 'TryPost delivery');
  aReceived := lReceived;
end;

procedure TTestInterfaceGenerics.VerifyStickyBehavior(const aBus: ImaxBus; const aBusObj: TmaxBus;
  var aReceived: integer);
var
  lAdv: ImaxBusAdvanced;
  lReceived: integer;
{$IFDEF max_FPC}
  procedure StickyHandler(const aValue: integer);
  begin
    lReceived := aValue;
  end;
{$ENDIF}
begin
  lAdv := aBus as ImaxBusAdvanced;
  {$IFDEF max_FPC}
  lAdv.EnableSticky<integer>(True);
  aBus.Post<integer>(100);
  {$ELSE}
  aBusObj.EnableSticky<integer>(True);
  aBusObj.Post<integer>(100);
  {$ENDIF}

  lReceived := 0;
  {$IFDEF max_FPC}
  aBus.Subscribe<integer>(@StickyHandler, Posting);
  {$ELSE}
  aBusObj.Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      lReceived := aValue;
    end,
    Posting);
  {$ENDIF}
  CheckEquals(100, lReceived, 'Sticky delivery');
  aReceived := lReceived;
end;

procedure TTestInterfaceGenerics.VerifyQueuePolicyRoundTrip(const aBus: ImaxBus; const aBusObj: TmaxBus);
var
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
begin
  lQueues := aBus as ImaxBusQueues;
  lPolicy.MaxDepth := 5;
  lPolicy.Overflow := DropOldest;
  lPolicy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  lQueues.SetPolicyFor<integer>(lPolicy);
  lPolicy := lQueues.GetPolicyFor<integer>;
  {$ELSE}
  aBusObj.SetPolicyFor<integer>(lPolicy);
  lPolicy := aBusObj.GetPolicyFor<integer>;
  {$ENDIF}
  CheckEquals(5, lPolicy.MaxDepth, 'Policy MaxDepth round-trip');
  Check(lPolicy.Overflow = DropOldest, 'Policy Overflow round-trip');
end;

procedure TTestInterfaceGenerics.VerifyStatsForInteger(const aBus: ImaxBus; const aBusObj: TmaxBus);
var
  lMetrics: ImaxBusMetrics;
  lStats: TmaxTopicStats;
begin
  lMetrics := aBus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  lStats := lMetrics.GetStatsFor<integer>;
  {$ELSE}
  lStats := aBusObj.GetStatsFor<integer>;
  {$ENDIF}
  Check(lStats.PostsTotal >= 3, Format('PostsTotal should be at least 3, got %d', [lStats.PostsTotal]));
  Check(lStats.DeliveredTotal >= 3, Format('DeliveredTotal should be at least 3, got %d', [lStats.DeliveredTotal]));
end;

procedure TTestInterfaceGenerics.UsesInterfaceGenerics;
var
  lBus: ImaxBus;
  lBusObj: TmaxBus;
  lReceived: integer;
begin
  lBus := maxBus;
  lBus.Clear;
  {$IFDEF max_FPC}
  lBusObj := nil;
  {$ELSE}
  lBusObj := maxBusObj(lBus);
  {$ENDIF}

  VerifyPostAndTryPost(lBus, lBusObj, lReceived);
  VerifyStickyBehavior(lBus, lBusObj, lReceived);
  VerifyQueuePolicyRoundTrip(lBus, lBusObj);
  VerifyStatsForInteger(lBus, lBusObj);

  lBus.Clear;
end;

initialization
  {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
  glLogCs:= TCriticalSection.Create  ;
  {$IFEND}
finalization
  {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
  FreeAndNil(glLogCs);
  {$IFEND}
end.

