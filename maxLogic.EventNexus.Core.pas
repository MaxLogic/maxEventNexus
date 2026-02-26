unit maxLogic.EventNexus.Core;

interface

uses
  Classes, SysUtils,
  System.Diagnostics, System.Generics.Collections, System.Generics.Defaults, System.SyncObjs, System.TypInfo, System.Rtti,
  maxLogic.EventNexus.Threading.Adapter;

const
  max_BUS_VERSION = '1.1.0';

type
  TmaxString = string;

  TmaxKeyFunc<t> = reference to function(const aValue: t): TmaxString;

  TMaxStopwatch = TStopwatch;

type
  TmaxObjProcOf<t> = procedure(const aValue: t) of object;

  TmaxProcQueue = TQueue<TmaxProc>;
  TmaxExceptionList = TObjectList<Exception>;

  TmaxMonitorObject = TObject;

  TmaxDelivery = (Posting, Main, Async, Background);
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);
  TmaxMainThreadPolicy = (Strict, DegradeToAsync, DegradeToPosting);
  TmaxPostResult = (NoTopic, Dropped, Coalesced, Queued, DispatchedInline);

  ImaxSubscription = interface
    ['{79C1B0D9-6A9E-4C6B-8E96-88A84E4F1E03}']
    procedure Unsubscribe;
    function IsActive: boolean;
  end;

  ImaxDelayedPost = interface
    ['{2F70B998-4889-474A-A8CF-6A22C1381D09}']
    function Cancel: boolean;
    function IsPending: boolean;
  end;

  ImaxBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): boolean;
    function PostDelayedNamed(const aName: TmaxString; aDelayMs: Cardinal): ImaxDelayedPost;

    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
  end;

  ImaxBusAdvanced = interface(ImaxBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableStickyNamed(const aName: string; aEnable: boolean);

    // Coalescing configuration
  end;

  TmaxQueuePolicy = record
    MaxDepth: integer;
    Overflow: TmaxOverflow;
    DeadlineUs: Int64;
  end;

  TmaxQueuePreset = (Unspecified, State, Action, ControlPlane);

  ImaxBusQueues = interface
    ['{E55F7B60-9B31-4C80-9B2C-8D1F0E26FF9C}']
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    function GetPolicyNamed(const aName: string): TmaxQueuePolicy;

    // Generic policy configuration
  end;

  TmaxTopicStats = record
    PostsTotal: UInt64;
    DeliveredTotal: UInt64;
    DroppedTotal: UInt64;
    ExceptionsTotal: UInt64;
    MaxQueueDepth: UInt32;
    CurrentQueueDepth: UInt32;
  end;

  // Keep hot counters on separate cache-line-sized slots to reduce write contention.
  TmaxPaddedCounter64 = record
    Value: Int64;
    Pad1: Int64;
    Pad2: Int64;
    Pad3: Int64;
    Pad4: Int64;
    Pad5: Int64;
    Pad6: Int64;
    Pad7: Int64;
  end;

  ImaxBusMetrics = interface
    ['{2C4B91E3-1C0A-4B5C-B8B0-0C1A5C3E6D10}']
    function GetStatsNamed(const aName: string): TmaxTopicStats;

    // Generic statistics
    function GetTotals: TmaxTopicStats;
  end;

  ImaxBusImpl = interface
    ['{B6E03A95-642B-4F6A-AE2E-704F7E7E9A3E}']
    function GetSelf: TObject;
  end;

  ImaxSubscriptionState = interface
    ['{6B8BCC86-7AC3-4B6F-9CF9-2F3EE0A5F913}']
    function TryEnter: boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: boolean;
  end;

  TmaxSubscriptionState = class(TInterfacedObject, ImaxSubscriptionState)
  private
    fActive: integer;
    fInFlight: integer;
  public
    constructor Create;
    function TryEnter: boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: boolean;
  end;

  EmaxInvalidSubscription = class(Exception);
  EmaxMainThreadRequired = class(Exception);

  TmaxDispatchErrorDetail = record
    ExceptionClassName: string;
    ExceptionMessage: string;
    Topic: string;
    Delivery: TmaxDelivery;
    SubscriberToken: UInt64;
    SubscriberIndex: integer;
  end;

  EmaxDispatchError = class(Exception)
  private
    fInner: TmaxExceptionList;
    fDetails: TArray<TmaxDispatchErrorDetail>;
  public
    constructor Create(const aInner: TmaxExceptionList); overload;
    constructor Create(const aInner: TmaxExceptionList; const aDetails: TArray<TmaxDispatchErrorDetail>); overload;
    destructor Destroy; override;
    property Inner: TmaxExceptionList read fInner;
    property Details: TArray<TmaxDispatchErrorDetail> read fDetails;
  end;

  TmaxTraceKind = (TraceEnqueue, TraceInvokeStart, TraceInvokeEnd, TraceInvokeError);

  TmaxDispatchTrace = record
    Kind: TmaxTraceKind;
    Topic: string;
    Delivery: TmaxDelivery;
    QueueDepth: UInt32;
    DurationUs: Int64;
    SubscriberToken: UInt64;
    SubscriberIndex: integer;
    ExceptionClassName: string;
    ExceptionMessage: string;
  end;

  TOnAsyncError = reference to procedure(const aTopic: string; const aE: Exception);
  TOnDispatchTrace = reference to procedure(const aTrace: TmaxDispatchTrace);
  TOnMetricSample = reference to procedure(const aName: string; const aStats: TmaxTopicStats);
function maxBus: ImaxBus;
procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
procedure maxSetDispatchTrace(const aHandler: TOnDispatchTrace);
procedure maxSetMetricCallback(const aSampler: TOnMetricSample);
procedure maxSetMetricSampleInterval(aIntervalMs: Cardinal);
procedure maxSetQueuePresetNamed(const aName: string; aPreset: TmaxQueuePreset);
procedure maxSetQueuePresetForType(const aType: PTypeInfo; aPreset: TmaxQueuePreset);
procedure maxSetQueuePresetGuid(const aGuid: TGuid; aPreset: TmaxQueuePreset);
procedure maxSetAsyncScheduler(const aScheduler: IEventNexusScheduler);
function maxGetAsyncScheduler: IEventNexusScheduler;
procedure maxSetMainThreadPolicy(aPolicy: TmaxMainThreadPolicy);

type
  maxSubscribeAttribute = class(TCustomAttribute)
  public
    Name: string;
    Delivery: TmaxDelivery;
    constructor Create(aDelivery: TmaxDelivery); overload;
    constructor Create(const aName: string; aDelivery: TmaxDelivery = TmaxDelivery.Posting); overload;
  end;

procedure AutoSubscribe(const aInstance: TObject);
procedure AutoUnsubscribe(const aInstance: TObject);

type
  TmaxTopicBase = class(TmaxMonitorObject)
  protected
    fQueue: TmaxProcQueue;
    fProcessing: boolean;
    fSticky: boolean;
    fPolicy: TmaxQueuePolicy;
    fPolicyExplicit: boolean;
    fPostsTotal: TmaxPaddedCounter64;
    fDeliveredTotal: TmaxPaddedCounter64;
    fDroppedTotal: TmaxPaddedCounter64;
    fExceptionsTotal: TmaxPaddedCounter64;
    fMaxQueueDepth: UInt32;
    fCurrentQueueDepth: UInt32;
    fMetricName: TmaxString;
    fLastMetricSample: UInt64;
    fWarnedHighWater: boolean;
    procedure TouchMetrics;
    procedure CheckHighWater; inline;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMetricName(const aName: TmaxString); inline;
    function MetricName: TmaxString; inline;
    function Enqueue(const aProc: TmaxProc): boolean;
    function EnqueueWithDispatchFlag(const aProc: TmaxProc; out aDispatchedInline: boolean): boolean;
    function TryBeginDirectDispatch: boolean;
    procedure EndDirectDispatch;
    procedure RemoveByTarget(const aTarget: TObject); virtual; abstract;
    procedure SetSticky(aEnable: boolean); virtual;
    procedure SetPolicy(const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyImplicit(const aPolicy: TmaxQueuePolicy);
    function GetPolicy: TmaxQueuePolicy;
    function HasExplicitPolicy: boolean; inline;
    procedure AddPost; inline;
    procedure AddDelivered(aCount: integer); inline;
    procedure AddDropped; inline;
    procedure AddException; inline;
    function GetStats: TmaxTopicStats; inline;
    function IsProcessing: boolean;
    procedure ResetTopic; virtual;
  end;

  TmaxTypedMetricTopic = record
    Key: PTypeInfo;
    Topic: TmaxTopicBase;
  end;

  TmaxNamedMetricTopic = record
    NameKey: TmaxString;
    Topic: TmaxTopicBase;
  end;

  TmaxNamedTypedMetricTopic = record
    NameKey: TmaxString;
    Key: PTypeInfo;
    Topic: TmaxTopicBase;
  end;

  TmaxGuidMetricTopic = record
    Key: TGuid;
    Topic: TmaxTopicBase;
  end;

  ImaxMetricsIndex = interface
    ['{8DCCB2C3-3B63-4E9C-9F01-1F2A0D7D4B3A}']
    function AddTyped(const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddNamed(const aNameKey: TmaxString; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddNamedTyped(const aNameKey: TmaxString; const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddGuid(const aKey: TGuid; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function GetStatsForType(const aKey: PTypeInfo): TmaxTopicStats;
    function GetStatsNamed(const aNameKey: TmaxString): TmaxTopicStats;
    function GetStatsGuid(const aKey: TGuid): TmaxTopicStats;
    function GetTotals: TmaxTopicStats;
  end;

  TmaxMetricsIndex = class(TInterfacedObject, ImaxMetricsIndex)
  private
    fTyped: TArray<TmaxTypedMetricTopic>;
    fNamed: TArray<TmaxNamedMetricTopic>;
    fNamedTyped: TArray<TmaxNamedTypedMetricTopic>;
    fGuid: TArray<TmaxGuidMetricTopic>;
  public
    constructor CreateEmpty;
    function AddTyped(const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddNamed(const aNameKey: TmaxString; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddNamedTyped(const aNameKey: TmaxString; const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function AddGuid(const aKey: TGuid; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
    function GetStatsForType(const aKey: PTypeInfo): TmaxTopicStats;
    function GetStatsNamed(const aNameKey: TmaxString): TmaxTopicStats;
    function GetStatsGuid(const aKey: TGuid): TmaxTopicStats;
    function GetTotals: TmaxTopicStats;
  end;

  TmaxTypeTopicDict = TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxNameTopicDict = TObjectDictionary<TmaxString, TmaxTopicBase>;
  TmaxNameTypeTopicDict = TObjectDictionary<TmaxString, TObjectDictionary<PTypeInfo, TmaxTopicBase>>;
  TmaxGuidTopicDict = TObjectDictionary<TGuid, TmaxTopicBase>;
  TmaxBoolDictOfTypeInfo = TDictionary<PTypeInfo, boolean>;
  TmaxBoolDictOfString = TDictionary<TmaxString, boolean>;
  TmaxPresetDictOfTypeInfo = TDictionary<PTypeInfo, TmaxQueuePreset>;
  TmaxPresetDictOfString = TDictionary<TmaxString, TmaxQueuePreset>;
  TmaxPresetDictOfGuid = TDictionary<TGuid, TmaxQueuePreset>;
  TmaxSubList = TList<ImaxSubscription>;
  TmaxAutoSubDict = TObjectDictionary<TObject, TmaxSubList>;

  TmaxSubscriptionToken = uInt64;

  TNamedWildcardSubscriber = record
    Pattern: TmaxString;
    Prefix: TmaxString;
    PrefixLen: integer;
    Handler: TmaxProc;
    Mode: TmaxDelivery;
    Token: TmaxSubscriptionToken;
    State: ImaxSubscriptionState;
  end;

  TmaxWeakTarget = record
    Raw: TObject;
    Generation: UInt32;
    class function Create(const aObj: TObject): TmaxWeakTarget; static;
    function Matches(const aObj: TObject): boolean;
    function IsAlive: boolean;
  end;

  TTypedSubscriber<t> = record
    Handler: TmaxProcOf<t>;
    Mode: TmaxDelivery;
    Token: TmaxSubscriptionToken;
    Target: TmaxWeakTarget;
    State: ImaxSubscriptionState;
  end;

  TmaxAutoBridgeKind = (AutoBridgeTyped, AutoBridgeNamedTyped, AutoBridgeGuidTyped);

  TmaxAutoBridgeEntry = class
  public
    Kind: TmaxAutoBridgeKind;
    Token: TmaxSubscriptionToken;
    ParamType: PTypeInfo;
    NameKey: TmaxString;
    GuidKey: TGuid;
    MethodPtr: TMethod;
    Mode: TmaxDelivery;
    State: ImaxSubscriptionState;
    Target: TmaxWeakTarget;
    constructor Create(aKind: TmaxAutoBridgeKind; aToken: TmaxSubscriptionToken; const aParamType: PTypeInfo;
      const aNameKey: TmaxString; const aGuidKey: TGuid; const aMethodPtr: TMethod; aMode: TmaxDelivery;
      const aState: ImaxSubscriptionState; const aTarget: TObject);
  end;

  TmaxAutoBridgeSnapshot = record
    Token: TmaxSubscriptionToken;
    MethodPtr: TMethod;
    Mode: TmaxDelivery;
    State: ImaxSubscriptionState;
    Target: TmaxWeakTarget;
  end;

  TTypedTopic<t> = class(TmaxTopicBase)
  private
    fSubs: TArray<TTypedSubscriber<t>>;
    fSubsVersion: UInt64;
    fSnapshotVersion: UInt64;
    fSnapshotCache: TArray<TTypedSubscriber<t>>;
    fLast: t;
    fHasLast: boolean;
    fStickyFast: integer;
    fCoalesce: boolean;
    fCoalesceFast: integer;
    fKeyFunc: TmaxKeyFunc<t>;
    fWindowUs: integer;
    fPending: TDictionary<TmaxString, t>;
    fPendingLock: TmaxMonitorObject;
    fFlushScheduled: boolean;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDeadLocked;
  public
    constructor Create;
    function Add(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState; const aTarget: TObject = nil): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TTypedSubscriber<t>>;
    function SnapshotAndTryBeginDirectDispatch(out aSubs: TArray<TTypedSubscriber<t>>): boolean;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: boolean); override;
    procedure ResetTopic; override;
    procedure Cache(const aEvent: t);
    function TryGetCached(out aEvent: t): boolean;
    procedure SetCoalesce(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
    function HasCoalesce: boolean;
    function CoalesceKey(const aEvent: t): TmaxString;
    function AddOrUpdatePending(const aKey: TmaxString; const aEvent: t): boolean;
    function PopPending(const aKey: TmaxString; out aEvent: t): boolean;
    function PopAllPending(out aEvents: TArray<t>): boolean;
    procedure ClearPending;
    function CoalesceWindow: integer;
    destructor Destroy; override;
  end;

  type
    TInvokeBox<T> = class
    public
      Topic: TTypedTopic<T>;
      Handler: TmaxProcOf<T>;
      Value: T;
      Token: TmaxSubscriptionToken;
      State: ImaxSubscriptionState;
      class function MakeProc(const aBox: TInvokeBox<T>): TmaxProc; static;
    end;

  TmaxBus = class(TInterfacedObject, ImaxBus, ImaxBusAdvanced, ImaxBusQueues, ImaxBusMetrics, ImaxBusImpl)
	  private
	    fAsync: IEventNexusScheduler;
	    fTypedLock: TmaxMonitorObject;
	    fNamedLock: TmaxMonitorObject;
	    fNamedTypedLock: TmaxMonitorObject;
	    fGuidLock: TmaxMonitorObject;
	    fNamedWildcardLock: TmaxMonitorObject;
	    fConfigLock: TLightweightMREW;
	    fMetricsLock: TLightweightMREW;
	    fMetricsIndex: ImaxMetricsIndex;
	    fTyped: TmaxTypeTopicDict;
	    fNamed: TmaxNameTopicDict;
	    fNamedTyped: TmaxNameTypeTopicDict;
		    fGuid: TmaxGuidTopicDict;
	    fStickyTypes: TmaxBoolDictOfTypeInfo;
	    fStickyNames: TmaxBoolDictOfString;
	    fPresetTypes: TmaxPresetDictOfTypeInfo;
	    fPresetNames: TmaxPresetDictOfString;
	    fPresetGuids: TmaxPresetDictOfGuid;
	    fNamedWildcardSubs: TArray<TNamedWildcardSubscriber>;
	    fNamedWildcardSnapshot: TArray<TNamedWildcardSubscriber>;
	    fNamedWildcardVersion: UInt64;
	    fNamedWildcardSnapshotVersion: UInt64;
	    fNamedWildcardNextToken: TmaxSubscriptionToken;
		    fAutoSubsLock: TmaxMonitorObject;
		    fAutoSubs: TmaxAutoSubDict;
        fAutoBridgeLock: TmaxMonitorObject;
		    fAutoBridgeSubs: TObjectList<TmaxAutoBridgeEntry>;
        fAutoBridgeCount: integer;
        fAutoBridgeNextToken: TmaxSubscriptionToken;
        fDelayedPostEpoch: Int64;
			    fMainThreadId: TThreadID;
			    class procedure AddDispatchError(const aTopic: TmaxString; aMode: TmaxDelivery; aToken: TmaxSubscriptionToken;
			      aSubscriberIndex: integer; const aException: Exception; var aErrors: TmaxExceptionList;
			      var aDetails: TArray<TmaxDispatchErrorDetail>); static;
			    class procedure EmitInvokeTrace(const aTopic: TmaxString; aDelivery: TmaxDelivery; aKind: TmaxTraceKind;
			      aDurationUs: Int64; const aException: Exception); static;
			    class procedure InvokeWithTrace(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc); static;
			    class function WildcardPrefixMatches(const aPrefix: TmaxString; const aName: TmaxString): boolean; static;
			    class function TryParseWildcardPattern(const aPattern: TmaxString; out aPrefix: TmaxString): boolean; static;
			    class procedure MergeDispatchError(const aSource: EmaxDispatchError; var aErrors: TmaxExceptionList;
			      var aDetails: TArray<TmaxDispatchErrorDetail>); static;
			    function AddNamedWildcard(const aPattern: TmaxString; const aPrefix: TmaxString; const aHandler: TmaxProc;
			      aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
			    procedure RemoveNamedWildcardByToken(aToken: TmaxSubscriptionToken);
			    function SnapshotNamedWildcardMatches(const aName: TmaxString): TArray<TNamedWildcardSubscriber>;
          function AddAutoBridgeSubscription(aKind: TmaxAutoBridgeKind; const aParamType: PTypeInfo;
            const aNameKey: TmaxString; const aGuidKey: TGuid; const aMethodPtr: TMethod; aDelivery: TmaxDelivery;
            const aTarget: TObject): ImaxSubscription;
          procedure RemoveAutoBridgeByToken(aToken: TmaxSubscriptionToken);
          function HasAutoBridgeSubscriptions: boolean;
          function SnapshotAutoBridgeTyped(const aParamType: PTypeInfo): TArray<TmaxAutoBridgeSnapshot>;
          function SnapshotAutoBridgeNamedTyped(const aNameKey: TmaxString; const aParamType: PTypeInfo): TArray<TmaxAutoBridgeSnapshot>;
          function SnapshotAutoBridgeGuid(const aGuidKey: TGuid): TArray<TmaxAutoBridgeSnapshot>;
          procedure DispatchAutoBridge<t>(const aTopic: TmaxString; const aSnapshots: TArray<TmaxAutoBridgeSnapshot>;
            const aEvent: t);
          procedure DispatchTypedSubscribers<t>(const aTopicName: TmaxString; const aTopic: TTypedTopic<t>;
            const aSubs: TArray<TTypedSubscriber<t>>; const aValue: t; aRaiseMainThreadRequired: boolean);
          class function DelayMsToUs(aDelayMs: Cardinal): integer; static;
          function ScheduleDelayedPost(const aPostProc: TmaxProc; aDelayMs: Cardinal): ImaxDelayedPost;
			    procedure SetAsyncScheduler(const aAsync: IEventNexusScheduler);
    procedure ScheduleTypedCoalesce<t>(const aTopicName: TmaxString;
      aTopic: TTypedTopic<t>; const aSubs: TArray<TTypedSubscriber<t>>);
		    procedure PublishMetricTypedTopic(const aKey: PTypeInfo; const aTopic: TmaxTopicBase);
		    procedure PublishMetricNamedTopic(const aNameKey: TmaxString; const aTopic: TmaxTopicBase);
		    procedure PublishMetricNamedTypedTopic(const aNameKey: TmaxString; const aKey: PTypeInfo; const aTopic: TmaxTopicBase);
		    procedure PublishMetricGuidTopic(const aKey: TGuid; const aTopic: TmaxTopicBase);
    procedure RememberAutoSubscription(const aInstance: TObject; const aSub: ImaxSubscription);
    procedure AutoSubscribeInstance(const aInstance: TObject);
    procedure AutoUnsubscribeInstance(const aInstance: TObject);
	  public
	    class function PolicyForPreset(aPreset: TmaxQueuePreset): TmaxQueuePolicy; static;
	    procedure SetQueuePresetForType(const aKey: PTypeInfo; aPreset: TmaxQueuePreset);
	    procedure SetQueuePresetNamed(const aNameKey: TmaxString; aPreset: TmaxQueuePreset);
	    procedure SetQueuePresetGuid(const aGuid: TGuid; aPreset: TmaxQueuePreset);
	    function Subscribe<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
	    function Subscribe<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
	    procedure Post<t>(const aEvent: t);
	    function TryPost<t>(const aEvent: t): boolean; overload;
    function PostResult<t>(const aEvent: t): TmaxPostResult; overload;
    function PostDelayed<t>(const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;

	    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    function SubscribeNamedWildcard(const aPattern: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): boolean;
    function PostResultNamed(const aName: TmaxString): TmaxPostResult;
    function PostDelayedNamed(const aName: TmaxString; aDelayMs: Cardinal): ImaxDelayedPost;

    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    procedure PostNamedOf<t>(const aName: TmaxString; const aEvent: t);
    function TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean; overload;
    function PostResultNamedOf<t>(const aName: TmaxString; const aEvent: t): TmaxPostResult; overload;
    function PostDelayedNamedOf<t>(const aName: TmaxString; const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;
    procedure PostMany<t>(const aEvents: array of t);
    procedure PostManyNamedOf<t>(const aName: TmaxString; const aEvents: array of t);

    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    procedure PostGuidOf<t: IInterface>(const aEvent: t);
    function TryPostGuidOf<t: IInterface>(const aEvent: t): boolean; overload;
    function PostResultGuidOf<t: IInterface>(const aEvent: t): TmaxPostResult; overload;
    function PostDelayedGuidOf<t: IInterface>(const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;
    procedure PostManyGuidOf<t: IInterface>(const aEvents: array of t);
    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
    procedure EnableSticky<t>(aEnable: boolean);
    procedure EnableStickyNamed(const aName: string; aEnable: boolean);
    procedure EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0);
    procedure EnableCoalesceNamedOf<t>(const aName: string; const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0);
    procedure EnableCoalesceGuidOf<t: IInterface>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0);
    procedure SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyGuidOf<t: IInterface>(const aPolicy: TmaxQueuePolicy);
    function GetPolicyFor<t>: TmaxQueuePolicy;
    function GetPolicyNamed(const aName: string): TmaxQueuePolicy;
    function GetPolicyGuidOf<t: IInterface>: TmaxQueuePolicy;
    function GetStatsFor<t>: TmaxTopicStats;
    function GetStatsNamed(const aName: string): TmaxTopicStats;
    function GetStatsGuidOf<t: IInterface>: TmaxTopicStats;
    function GetTotals: TmaxTopicStats;
  public
    function GetSelf: TObject;
    constructor Create(const aAsync: IEventNexusScheduler);
    destructor Destroy; override;
    procedure Dispatch(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc; const aOnException: TmaxProc = nil);
  end;


type
  TNamedSubscriber = record
    Handler: TmaxProc;
    Mode: TmaxDelivery;
    Token: TmaxSubscriptionToken;
    Target: TmaxWeakTarget;
    State: ImaxSubscriptionState;
  end;

  TNamedTopic = class(TmaxTopicBase)
  private
    fSubs: TArray<TNamedSubscriber>;
    fSubsVersion: UInt64;
    fSnapshotVersion: UInt64;
    fSnapshotCache: TArray<TNamedSubscriber>;
    fHasLast: boolean;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDeadLocked;
  public
    function Add(const aHandler: TmaxProc; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TNamedSubscriber>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: boolean); override;
    procedure ResetTopic; override;
    procedure Cache;
    function HasCached: boolean;
  end;

  TmaxSubscriptionBase = class(TInterfacedObject, ImaxSubscription)
  protected
    fActive: boolean;
    fState: ImaxSubscriptionState;
  public
    constructor Create(const aState: ImaxSubscriptionState);
    destructor Destroy; override;
    procedure Unsubscribe; virtual; abstract;
    function IsActive: boolean;
  end;

  TmaxTypedSubscription<t> = class(TmaxSubscriptionBase)
  private
    fTopic: TTypedTopic<t>;
    fToken: TmaxSubscriptionToken;
  public
    constructor Create(aTopic: TTypedTopic<t>; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
    procedure Unsubscribe; override;
  end;

  TmaxNamedSubscription = class(TmaxSubscriptionBase)
  private
    fTopic: TNamedTopic;
    fToken: TmaxSubscriptionToken;
  public
    constructor Create(aTopic: TNamedTopic; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
    procedure Unsubscribe; override;
  end;

  TmaxNamedWildcardSubscription = class(TmaxSubscriptionBase)
  private
    fBus: TmaxBus;
    fToken: TmaxSubscriptionToken;
  public
    constructor Create(const aBus: TmaxBus; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
    procedure Unsubscribe; override;
  end;

  TmaxAutoBridgeSubscription = class(TmaxSubscriptionBase)
  private
    fBus: TmaxBus;
    fToken: TmaxSubscriptionToken;
  public
    constructor Create(const aBus: TmaxBus; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
    procedure Unsubscribe; override;
  end;

  TmaxDelayedPostHandle = class(TInterfacedObject, ImaxDelayedPost)
  private
    // 0 = pending, 1 = consumed (canceled, executed, or dropped)
    fState: integer;
  public
    function Cancel: boolean;
    function IsPending: boolean;
  end;

function maxBusObj: TmaxBus; overload;
function maxBusObj(const aIntf: IInterface): TmaxBus; overload;

var
  gAsyncError: TOnAsyncError = nil;
  gDispatchTrace: TOnDispatchTrace = nil;
  gMainThreadPolicy: TmaxMainThreadPolicy = TmaxMainThreadPolicy.DegradeToPosting;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  maxLogic.Utils,
  maxLogic.EventNexus.Threading.RawThread
  ;

resourcestring
  SAggregateOccurred = '%d exception(s) occurred';
  SInvalidBusImplementation = 'Invalid bus implementation';

const
  cGuidNull: TGUID = '{00000000-0000-0000-0000-000000000000}';


var
  gMetricSample: TOnMetricSample = nil;
  gMetricSampleIntervalMs: Cardinal = 1000;
  gMetricSampleIntervalTicks: UInt64 = 0;
  gBusLock: TmaxMonitorObject = nil;
  gBus: ImaxBus = nil;
  gAsyncScheduler: IEventNexusScheduler = nil;
  gAsyncFallback: IEventNexusScheduler = nil;



type
  TDelphiWeakEntry = record
    Generation: UInt32;
    Alive: boolean;
  end;

  TDelphiWeakRegistry = class
  private
    type
      TFreeInstanceThunk = procedure(aSelf: TObject);
    var
    fEntries: TDictionary<TObject, TDelphiWeakEntry>;
    fHooks: TDictionary<TClass, Pointer>;
    fLock: TCriticalSection;
    function EnsureHook(const aObj: TObject): boolean;
    function LocateFreeInstanceSlot(const aClass: TClass; const aOrig: Pointer): PPointer;
    function PrepareFreeInstance(const aObj: TObject): Pointer;
  public
    constructor Create;
    destructor Destroy; override;
    function Observe(const aObj: TObject): UInt32;
    function IsAlive(const aObj: TObject; const aGeneration: UInt32): boolean;
    class function Instance: TDelphiWeakRegistry; static;
  end;

var
  gDelphiWeakRegistry: TDelphiWeakRegistry = nil;

procedure DelphiWeakFreeInstanceHook(aSelf: TObject); forward;

{ TDelphiWeakRegistry }

constructor TDelphiWeakRegistry.Create;
var
  lObjComparer: IEqualityComparer<TObject>;
  lClassComparer: IEqualityComparer<TClass>;
begin
  inherited Create;
  lObjComparer := TEqualityComparer<TObject>.Construct(
    function(const aLeft, aRight: TObject): Boolean
    begin
      Result := Pointer(aLeft) = Pointer(aRight);
    end,
    function(const aValue: TObject): Integer
    var
      lPtr: UIntPtr;
    begin
      lPtr := UIntPtr(aValue);
      Result := Integer(lPtr xor (lPtr shr 32));
    end);
  fEntries := TDictionary<TObject, TDelphiWeakEntry>.Create(lObjComparer);

  lClassComparer := TEqualityComparer<TClass>.Construct(
    function(const aLeft, aRight: TClass): Boolean
    begin
      Result := Pointer(aLeft) = Pointer(aRight);
    end,
    function(const aValue: TClass): Integer
    var
      lPtr: UIntPtr;
    begin
      lPtr := UIntPtr(aValue);
      Result := Integer(lPtr xor (lPtr shr 32));
    end);
  fHooks := TDictionary<TClass, Pointer>.Create(lClassComparer);
  fLock := TCriticalSection.Create;
end;

destructor TDelphiWeakRegistry.Destroy;
begin
  fLock.Free;
  fEntries.Free;
  fHooks.Free;
  inherited Destroy;
end;

class function TDelphiWeakRegistry.Instance: TDelphiWeakRegistry;
begin
  if gDelphiWeakRegistry = nil then
    gDelphiWeakRegistry := TDelphiWeakRegistry.Create;
  Result := gDelphiWeakRegistry;
end;

function TDelphiWeakRegistry.LocateFreeInstanceSlot(const aClass: TClass;
  const aOrig: Pointer): PPointer;
begin
  Result := PPointer(NativeInt(aClass) + vmtFreeInstance);
  if (Result = nil) or (Result^ <> aOrig) then
    Result := nil;
end;

function TDelphiWeakRegistry.EnsureHook(const aObj: TObject): boolean;
var
  lClass: TClass;
  lOrig: Pointer;
  lSlot: PPointer;
  {$IFDEF MSWINDOWS}
  lOldProtect: Cardinal;
begin
  Result := False;
  if aObj = nil then
    exit;
  lClass := aObj.ClassType;
  fLock.Enter;
  try
    if fHooks.ContainsKey(lClass) then
      exit(True);
  finally
    fLock.Leave;
  end;

  lOrig := PPointer(NativeInt(lClass) + vmtFreeInstance)^;
  if lOrig = @DelphiWeakFreeInstanceHook then
    exit(True);

  lSlot := LocateFreeInstanceSlot(lClass, lOrig);
  if lSlot = nil then
    exit(False);

  fLock.Enter;
  try
    if fHooks.ContainsKey(lClass) then
      exit(True);
    fHooks.Add(lClass, lOrig);
    {$IFDEF MSWINDOWS}
    if VirtualProtect(lSlot, SizeOf(Pointer), PAGE_EXECUTE_READWRITE, lOldProtect) then
    try
      lSlot^ := @DelphiWeakFreeInstanceHook;
    finally
      VirtualProtect(lSlot, SizeOf(Pointer), lOldProtect, lOldProtect);
    end
    else
      exit(False);
    {$ELSE}
    lSlot^ := @DelphiWeakFreeInstanceHook;
    {$ENDIF}
    Result := True;
  finally
    fLock.Leave;
  end;
end;

function TDelphiWeakRegistry.PrepareFreeInstance(const aObj: TObject): Pointer;
var
  lEntry: TDelphiWeakEntry;
  lClass: TClass;
begin
  Result := nil;
  if aObj = nil then
    exit;
  fLock.Enter;
  try
    lClass := aObj.ClassType;
    if not fHooks.TryGetValue(lClass, Result) then
      Result := nil;
    if fEntries.TryGetValue(aObj, lEntry) then
    begin
      lEntry.Alive := False;
      if lEntry.Generation = High(UInt32) then
        lEntry.Generation := 1
      else
        Inc(lEntry.Generation);
      fEntries.AddOrSetValue(aObj, lEntry);
    end
    else
    begin
      lEntry.Generation := 1;
      lEntry.Alive := False;
      fEntries.Add(aObj, lEntry);
    end;
  finally
    fLock.Leave;
  end;
end;

function TDelphiWeakRegistry.Observe(const aObj: TObject): UInt32;
var
  lEntry: TDelphiWeakEntry;
begin
  if aObj = nil then
    exit(0);
  if not EnsureHook(aObj) then
    exit(0);
  fLock.Enter;
  try
    if fEntries.TryGetValue(aObj, lEntry) then
    begin
      lEntry.Alive := True;
      fEntries.AddOrSetValue(aObj, lEntry);
      exit(lEntry.Generation);
    end;
    lEntry.Generation := 1;
    lEntry.Alive := True;
    fEntries.Add(aObj, lEntry);
    Result := lEntry.Generation;
  finally
    fLock.Leave;
  end;
end;

function TDelphiWeakRegistry.IsAlive(const aObj: TObject; const aGeneration: UInt32): boolean;
var
  lEntry: TDelphiWeakEntry;
begin
  if (aObj = nil) or (aGeneration = 0) then
    exit(True);
  fLock.Enter;
  try
    if fEntries.TryGetValue(aObj, lEntry) then
      Result := lEntry.Alive and (lEntry.Generation = aGeneration)
    else
      Result := False;
  finally
    fLock.Leave;
  end;
end;

procedure DelphiWeakFreeInstanceHook(aSelf: TObject);
var
  lOrig: Pointer;
begin
  lOrig := TDelphiWeakRegistry.Instance.PrepareFreeInstance(aSelf);
  if lOrig <> nil then
    TDelphiWeakRegistry.TFreeInstanceThunk(lOrig)(aSelf);
end;

{ maxSubscribeAttribute }

constructor maxSubscribeAttribute.Create(aDelivery: TmaxDelivery);
begin
  Name := '';
  Delivery := aDelivery;
end;

constructor maxSubscribeAttribute.Create(const aName: string; aDelivery: TmaxDelivery);
begin
  Name := aName;
  Delivery := aDelivery;
end;

procedure AutoSubscribe(const aInstance: TObject);
var
  lBus: ImaxBus;
  lBusImpl: ImaxBusImpl;
begin
  if aInstance = nil then
    Exit;
  lBus := maxBus;
  if not Supports(lBus, ImaxBusImpl, lBusImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  TmaxBus(lBusImpl.GetSelf).AutoSubscribeInstance(aInstance);
end;

procedure AutoUnsubscribe(const aInstance: TObject);
var
  lBusImpl: ImaxBusImpl;
begin
  if (aInstance = nil) or (gBus = nil) then
    Exit;
  if not Supports(gBus, ImaxBusImpl, lBusImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  TmaxBus(lBusImpl.GetSelf).AutoUnsubscribeInstance(aInstance);
end;
{$ENDIF}

{ EmaxDispatchError }

constructor EmaxDispatchError.Create(const aInner: TmaxExceptionList);
begin
  Create(aInner, nil);
end;

constructor EmaxDispatchError.Create(const aInner: TmaxExceptionList; const aDetails: TArray<TmaxDispatchErrorDetail>);
begin
  fInner := aInner;
  fDetails := Copy(aDetails);
  inherited CreateFmt(SAggregateOccurred, [fInner.Count]);
end;

destructor EmaxDispatchError.Destroy;
begin
  fInner.Free;
  inherited Destroy;
end;

class procedure TmaxBus.AddDispatchError(const aTopic: TmaxString; aMode: TmaxDelivery; aToken: TmaxSubscriptionToken;
  aSubscriberIndex: integer; const aException: Exception; var aErrors: TmaxExceptionList;
  var aDetails: TArray<TmaxDispatchErrorDetail>);
var
  lCount: integer;
  lDetail: TmaxDispatchErrorDetail;
begin
  if aErrors = nil then
    aErrors := TmaxExceptionList.Create(True);
  aErrors.Add(Exception.Create(aException.Message));

  lDetail.ExceptionClassName := aException.ClassName;
  lDetail.ExceptionMessage := aException.Message;
  lDetail.Topic := aTopic;
  lDetail.Delivery := aMode;
  lDetail.SubscriberToken := aToken;
  lDetail.SubscriberIndex := aSubscriberIndex;

  lCount := Length(aDetails);
  SetLength(aDetails, lCount + 1);
  aDetails[lCount] := lDetail;
end;

class procedure TmaxBus.EmitInvokeTrace(const aTopic: TmaxString; aDelivery: TmaxDelivery; aKind: TmaxTraceKind;
  aDurationUs: Int64; const aException: Exception);
var
  lTrace: TmaxDispatchTrace;
begin
  if not Assigned(gDispatchTrace) then
    Exit;
  lTrace.Kind := aKind;
  lTrace.Topic := aTopic;
  lTrace.Delivery := aDelivery;
  lTrace.QueueDepth := 0;
  lTrace.DurationUs := aDurationUs;
  lTrace.SubscriberToken := 0;
  lTrace.SubscriberIndex := -1;
  if aException <> nil then
  begin
    lTrace.ExceptionClassName := aException.ClassName;
    lTrace.ExceptionMessage := aException.Message;
  end
  else
  begin
    lTrace.ExceptionClassName := '';
    lTrace.ExceptionMessage := '';
  end;
  gDispatchTrace(lTrace);
end;

class procedure TmaxBus.InvokeWithTrace(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc);
var
  lTraceEnabled: boolean;
  lStartTicks: Int64;
  lDurationUs: Int64;
begin
  lTraceEnabled := Assigned(gDispatchTrace);
  if lTraceEnabled then
  begin
    EmitInvokeTrace(aTopic, aDelivery, TmaxTraceKind.TraceInvokeStart, 0, nil);
    lStartTicks := TMaxStopwatch.GetTimeStamp;
  end
  else
    lStartTicks := 0;
  try
    aHandler();
    if lTraceEnabled then
    begin
      if TMaxStopwatch.Frequency <> 0 then
        lDurationUs := ((TMaxStopwatch.GetTimeStamp - lStartTicks) * 1000000) div TMaxStopwatch.Frequency
      else
        lDurationUs := 0;
      EmitInvokeTrace(aTopic, aDelivery, TmaxTraceKind.TraceInvokeEnd, lDurationUs, nil);
    end;
  except
    on e: Exception do
    begin
      if lTraceEnabled then
      begin
        if TMaxStopwatch.Frequency <> 0 then
          lDurationUs := ((TMaxStopwatch.GetTimeStamp - lStartTicks) * 1000000) div TMaxStopwatch.Frequency
        else
          lDurationUs := 0;
        EmitInvokeTrace(aTopic, aDelivery, TmaxTraceKind.TraceInvokeError, lDurationUs, e);
      end;
      raise;
    end;
  end;
end;

class function TmaxBus.WildcardPrefixMatches(const aPrefix: TmaxString; const aName: TmaxString): boolean;
begin
  if aPrefix = '' then
    Exit(True);
  if Length(aName) < Length(aPrefix) then
    Exit(False);
  Result := SameText(Copy(aName, 1, Length(aPrefix)), aPrefix);
end;

class function TmaxBus.TryParseWildcardPattern(const aPattern: TmaxString; out aPrefix: TmaxString): boolean;
var
  lLen: integer;
  lBody: TmaxString;
begin
  aPrefix := '';
  lLen := Length(aPattern);
  if lLen = 0 then
    Exit(False);
  if aPattern = '*' then
    Exit(True);
  if aPattern[lLen] <> '*' then
    Exit(False);
  lBody := Copy(aPattern, 1, lLen - 1);
  if Pos('*', lBody) <> 0 then
    Exit(False);
  aPrefix := lBody;
  Result := True;
end;

function TmaxBus.AddNamedWildcard(const aPattern: TmaxString; const aPrefix: TmaxString; const aHandler: TmaxProc;
  aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
var
  lNew: TArray<TNamedWildcardSubscriber>;
  lSub: TNamedWildcardSubscriber;
begin
  TMonitor.Enter(fNamedWildcardLock);
  try
    if fNamedWildcardNextToken = 0 then
      fNamedWildcardNextToken := 1;
    lSub.Pattern := aPattern;
    lSub.Prefix := aPrefix;
    lSub.PrefixLen := Length(aPrefix);
    lSub.Handler := aHandler;
    lSub.Mode := aMode;
    lSub.Token := fNamedWildcardNextToken;
    lSub.State := TmaxSubscriptionState.Create;
    aState := lSub.State;
    Inc(fNamedWildcardNextToken);

    lNew := Copy(fNamedWildcardSubs);
    SetLength(lNew, Length(lNew) + 1);
    lNew[High(lNew)] := lSub;
    fNamedWildcardSubs := lNew;
    Inc(fNamedWildcardVersion);
    Result := lSub.Token;
  finally
    TMonitor.Exit(fNamedWildcardLock);
  end;
end;

procedure TmaxBus.RemoveNamedWildcardByToken(aToken: TmaxSubscriptionToken);
var
  lNew: TArray<TNamedWildcardSubscriber>;
  lCount: integer;
  lIdx: integer;
  lOut: integer;
begin
  TMonitor.Enter(fNamedWildcardLock);
  try
    lCount := Length(fNamedWildcardSubs);
    if lCount = 0 then
      Exit;
    SetLength(lNew, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if fNamedWildcardSubs[lIdx].Token <> aToken then
      begin
        lNew[lOut] := fNamedWildcardSubs[lIdx];
        Inc(lOut);
      end
      else if Assigned(fNamedWildcardSubs[lIdx].State) then
        fNamedWildcardSubs[lIdx].State.Deactivate;
    if lOut = lCount then
      Exit;
    SetLength(lNew, lOut);
    fNamedWildcardSubs := lNew;
    Inc(fNamedWildcardVersion);
  finally
    TMonitor.Exit(fNamedWildcardLock);
  end;
end;

function TmaxBus.SnapshotNamedWildcardMatches(const aName: TmaxString): TArray<TNamedWildcardSubscriber>;
var
  lCount: integer;
  lIdx: integer;
  lOut: integer;
  lFiltered: TArray<TNamedWildcardSubscriber>;
  lMatches: TArray<TNamedWildcardSubscriber>;
  lMatchCount: integer;
  lI: integer;
  lJ: integer;
  lTmp: TNamedWildcardSubscriber;
begin
  TMonitor.Enter(fNamedWildcardLock);
  try
    lCount := Length(fNamedWildcardSubs);
    if lCount = 0 then
    begin
      Result := nil;
      Exit;
    end;

    SetLength(lFiltered, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if (fNamedWildcardSubs[lIdx].State = nil) or fNamedWildcardSubs[lIdx].State.IsActive then
      begin
        lFiltered[lOut] := fNamedWildcardSubs[lIdx];
        Inc(lOut);
      end
      else if Assigned(fNamedWildcardSubs[lIdx].State) then
        fNamedWildcardSubs[lIdx].State.Deactivate;

    if lOut <> lCount then
    begin
      SetLength(lFiltered, lOut);
      fNamedWildcardSubs := lFiltered;
      Inc(fNamedWildcardVersion);
    end;

    SetLength(lMatches, lOut);
    lMatchCount := 0;
    for lIdx := 0 to lOut - 1 do
      if WildcardPrefixMatches(fNamedWildcardSubs[lIdx].Prefix, aName) then
      begin
        lMatches[lMatchCount] := fNamedWildcardSubs[lIdx];
        Inc(lMatchCount);
      end;
  finally
    TMonitor.Exit(fNamedWildcardLock);
  end;

  SetLength(lMatches, lMatchCount);
  for lI := 0 to lMatchCount - 2 do
    for lJ := lI + 1 to lMatchCount - 1 do
      if (lMatches[lJ].PrefixLen > lMatches[lI].PrefixLen) or
        ((lMatches[lJ].PrefixLen = lMatches[lI].PrefixLen) and (lMatches[lJ].Token < lMatches[lI].Token)) then
      begin
        lTmp := lMatches[lI];
        lMatches[lI] := lMatches[lJ];
        lMatches[lJ] := lTmp;
      end;
  Result := lMatches;
end;

class procedure TmaxBus.MergeDispatchError(const aSource: EmaxDispatchError; var aErrors: TmaxExceptionList;
  var aDetails: TArray<TmaxDispatchErrorDetail>);
var
  lIdx: integer;
  lBase: integer;
  lDetailCount: integer;
begin
  if aSource = nil then
    Exit;

  if (aSource.Inner <> nil) and (aSource.Inner.Count > 0) then
  begin
    if aErrors = nil then
      aErrors := TmaxExceptionList.Create(True);
    for lIdx := 0 to aSource.Inner.Count - 1 do
      aErrors.Add(Exception.Create(aSource.Inner[lIdx].Message));
  end;

  lDetailCount := Length(aSource.Details);
  if lDetailCount = 0 then
    Exit;
  lBase := Length(aDetails);
  SetLength(aDetails, lBase + lDetailCount);
  for lIdx := 0 to lDetailCount - 1 do
    aDetails[lBase + lIdx] := aSource.Details[lIdx];
end;

{ TmaxAutoBridgeEntry }

constructor TmaxAutoBridgeEntry.Create(aKind: TmaxAutoBridgeKind; aToken: TmaxSubscriptionToken;
  const aParamType: PTypeInfo; const aNameKey: TmaxString; const aGuidKey: TGuid; const aMethodPtr: TMethod;
  aMode: TmaxDelivery; const aState: ImaxSubscriptionState; const aTarget: TObject);
begin
  inherited Create;
  Kind := aKind;
  Token := aToken;
  ParamType := aParamType;
  NameKey := aNameKey;
  GuidKey := aGuidKey;
  MethodPtr := aMethodPtr;
  Mode := aMode;
  State := aState;
  Target := TmaxWeakTarget.Create(aTarget);
end;

{ TmaxWeakTarget }

class function TmaxWeakTarget.Create(const aObj: TObject): TmaxWeakTarget;
begin
  Result.Raw := aObj;
  if aObj <> nil then
    Result.Generation := TDelphiWeakRegistry.Instance.Observe(aObj)
  else
    Result.Generation := 0;
end;

function TmaxWeakTarget.Matches(const aObj: TObject): boolean;
begin
  Result := (Raw <> nil) and (Raw = aObj);
end;

function TmaxWeakTarget.IsAlive: boolean;
begin
  if (Raw = nil) or (Generation = 0) then
    exit(True);
  Result := TDelphiWeakRegistry.Instance.IsAlive(Raw, Generation);
end;

{ TmaxSubscriptionState }

constructor TmaxSubscriptionState.Create;
begin
  inherited Create;
  fActive := 1;
  fInFlight := 0;
end;

function TmaxSubscriptionState.TryEnter: boolean;
begin
  if TInterlocked.CompareExchange(fActive, 0, 0) = 0 then
    Exit(False);
  TInterlocked.Increment(fInFlight);
  if TInterlocked.CompareExchange(fActive, 0, 0) = 0 then
  begin
    TInterlocked.Decrement(fInFlight);
    Exit(False);
  end;
  Result := True;
end;

procedure TmaxSubscriptionState.Leave;
begin
  if TInterlocked.CompareExchange(fInFlight, 0, 0) > 0 then
    TInterlocked.Decrement(fInFlight);
end;

procedure TmaxSubscriptionState.Deactivate;
begin
  TInterlocked.Exchange(fActive, 0);
end;

function TmaxSubscriptionState.IsActive: boolean;
begin
  Result := TInterlocked.CompareExchange(fActive, 0, 0) <> 0;
end;

{ TmaxTopicBase }

constructor TmaxTopicBase.Create;
begin
  inherited Create;
  fQueue := TmaxProcQueue.Create;
  fProcessing := False;
  fSticky := False;
  fPolicy.MaxDepth := 0;
  fPolicy.Overflow := DropNewest;
  fPolicy.DeadlineUs := 0;
  fPolicyExplicit := False;
  fMetricName := '';
	fLastMetricSample := 0;
	fWarnedHighWater := False;
	fPostsTotal.Value := 0;
	fDeliveredTotal.Value := 0;
	fDroppedTotal.Value := 0;
	fExceptionsTotal.Value := 0;
	fMaxQueueDepth := 0;
	fCurrentQueueDepth := 0;
end;

destructor TmaxTopicBase.Destroy;
begin
  fQueue.Free;
  inherited Destroy;
end;

procedure TmaxTopicBase.SetMetricName(const aName: TmaxString);
begin
  if (fMetricName = '') and (aName <> '') then
    fMetricName := aName;
end;

function TmaxTopicBase.MetricName: TmaxString;
begin
  Result := fMetricName;
end;

procedure TmaxTopicBase.SetPolicy(const aPolicy: TmaxQueuePolicy);
begin
  TMonitor.Enter(Self);
  try
    fPolicy := aPolicy;
    fPolicyExplicit := True;
    fWarnedHighWater := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TmaxTopicBase.SetPolicyImplicit(const aPolicy: TmaxQueuePolicy);
begin
  TMonitor.Enter(Self);
  try
    fPolicy := aPolicy;
    fPolicyExplicit := False;
    fWarnedHighWater := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TmaxTopicBase.GetPolicy: TmaxQueuePolicy;
begin
  TMonitor.Enter(Self);
  try
    Result := fPolicy;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TmaxTopicBase.HasExplicitPolicy: boolean;
begin
  Result := fPolicyExplicit;
end;

procedure TmaxTopicBase.TouchMetrics;
var
  lNow: UInt64;
begin
  if (fMetricName = '') or (not Assigned(gMetricSample)) then
    Exit;
  if gMetricSampleIntervalTicks <> 0 then
  begin
    lNow := UInt64(TMaxStopwatch.GetTimeStamp);
    if (fLastMetricSample <> 0) and ((lNow - fLastMetricSample) < gMetricSampleIntervalTicks) then
      Exit;
    fLastMetricSample := lNow;
	end;
	gMetricSample(fMetricName, GetStats);
end;

procedure TmaxTopicBase.CheckHighWater;
begin
	if fPolicy.MaxDepth = 0 then
	begin
		if (not fWarnedHighWater) and (fCurrentQueueDepth > 10000) then
		begin
			fWarnedHighWater := True;
			fLastMetricSample := 0;
			TouchMetrics;
		end
		else if fWarnedHighWater and (fCurrentQueueDepth <= 5000) then
		begin
			fWarnedHighWater := False;
			fLastMetricSample := 0;
			TouchMetrics;
		end;
	end;
end;

procedure TmaxTopicBase.AddPost;
begin
	TInterlocked.Add(fPostsTotal.Value, 1);
	TouchMetrics;
end;

procedure TmaxTopicBase.AddDelivered(aCount: integer);
begin
	if aCount > 0 then
		TInterlocked.Add(fDeliveredTotal.Value, Int64(aCount));
	TouchMetrics;
end;

procedure TmaxTopicBase.AddDropped;
begin
	TInterlocked.Add(fDroppedTotal.Value, 1);
	TouchMetrics;
end;

procedure TmaxTopicBase.AddException;
begin
	TInterlocked.Add(fExceptionsTotal.Value, 1);
	TouchMetrics;
end;

function TmaxTopicBase.GetStats: TmaxTopicStats;
begin
	Result.PostsTotal := UInt64(TInterlocked.Read(fPostsTotal.Value));
	Result.DeliveredTotal := UInt64(TInterlocked.Read(fDeliveredTotal.Value));
	Result.DroppedTotal := UInt64(TInterlocked.Read(fDroppedTotal.Value));
	Result.ExceptionsTotal := UInt64(TInterlocked.Read(fExceptionsTotal.Value));
	Result.MaxQueueDepth := fMaxQueueDepth;
	Result.CurrentQueueDepth := fCurrentQueueDepth;
end;

function TmaxTopicBase.IsProcessing: boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fProcessing;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TmaxTopicBase.ResetTopic;
begin
	TMonitor.Enter(Self);
	try
		fQueue.Clear;
		fProcessing := False;
		fSticky := False;
		fPolicy.MaxDepth := 0;
		fPolicy.Overflow := DropNewest;
		fPolicy.DeadlineUs := 0;
		fPolicyExplicit := False;
		fMetricName := '';
		fLastMetricSample := 0;
		fWarnedHighWater := False;
		fPostsTotal.Value := 0;
		fDeliveredTotal.Value := 0;
		fDroppedTotal.Value := 0;
		fExceptionsTotal.Value := 0;
		fMaxQueueDepth := 0;
		fCurrentQueueDepth := 0;
		TMonitor.PulseAll(Self);
	finally
		TMonitor.Exit(Self);
	end;
end;



function TmaxTopicBase.Enqueue(const aProc: TmaxProc): boolean;
var
  lDispatchedInline: boolean;
begin
  Result := EnqueueWithDispatchFlag(aProc, lDispatchedInline);
end;

function TmaxTopicBase.TryBeginDirectDispatch: boolean;
var
  lEmitTrace: boolean;
  lTrace: TmaxDispatchTrace;
begin
  lEmitTrace := False;
  TMonitor.Enter(Self);
  try
    Result := (fPolicy.MaxDepth = 0) and (not fProcessing) and (fQueue.Count = 0);
    if Result then
    begin
      fProcessing := True;
      if Assigned(gDispatchTrace) then
      begin
        lTrace.Kind := TmaxTraceKind.TraceEnqueue;
        lTrace.Topic := fMetricName;
        lTrace.Delivery := TmaxDelivery.Posting;
        lTrace.QueueDepth := fCurrentQueueDepth;
        lTrace.DurationUs := 0;
        lTrace.SubscriberToken := 0;
        lTrace.SubscriberIndex := -1;
        lTrace.ExceptionClassName := '';
        lTrace.ExceptionMessage := '';
        lEmitTrace := True;
      end;
    end;
  finally
    TMonitor.Exit(Self);
  end;
  if lEmitTrace and Assigned(gDispatchTrace) then
    gDispatchTrace(lTrace);
end;

procedure TmaxTopicBase.EndDirectDispatch;
var
  lProc: TmaxProc;
begin
  while True do
  begin
    TMonitor.Enter(Self);
    try
      if fQueue.Count = 0 then
      begin
        fProcessing := False;
        TMonitor.PulseAll(Self);
        TouchMetrics;
        Exit;
      end;
      lProc := fQueue.Dequeue();
      if fCurrentQueueDepth > 0 then
        Dec(fCurrentQueueDepth);
      CheckHighWater;
      TouchMetrics;
      TMonitor.Pulse(Self);
    finally
      TMonitor.Exit(Self);
    end;
    try
      lProc();
    except
      TMonitor.Enter(Self);
      try
        fProcessing := False;
        TMonitor.PulseAll(Self);
        TouchMetrics;
      finally
        TMonitor.Exit(Self);
      end;
      raise;
    end;
  end;
end;

function TmaxTopicBase.EnqueueWithDispatchFlag(const aProc: TmaxProc; out aDispatchedInline: boolean): boolean;
var
  lProc: TmaxProc;
  lTimer: TMaxStopwatch;
  lDeadlineMs: Cardinal;
  lDeadlineUs: Int64;
  lDeadlineTicks: Int64;
  lRemainingMs: Int64;
  lWaitMs: Cardinal;
  lElapsedMs: Int64;
  lEnqueueTimer: TMaxStopwatch;
  lWrapped: TmaxProc;
  lNeedDeadlineGuard: boolean;
  lEmitTrace: boolean;
  lAlreadyProcessing: boolean;
  lTrace: TmaxDispatchTrace;
begin
  aDispatchedInline := False;
  Result := True;
  lEmitTrace := False;
  lAlreadyProcessing := False;
  TMonitor.Enter(self);
  try
    // Capacity check - ONLY count queued items, not the active one
    if (fPolicy.MaxDepth > 0) then
    begin
      case fPolicy.Overflow of
        DropNewest:
          begin
            if fQueue.Count >= fPolicy.MaxDepth then
            begin
              AddDropped;
              exit(False);
            end;
          end;
        DropOldest:
          begin
            if fQueue.Count >= fPolicy.MaxDepth then
            begin
              // Drop the oldest *queued* item (not the active one)
              if fQueue.Count > 0 then
              begin
                fQueue.Dequeue;
					if fCurrentQueueDepth > 0 then
						Dec(fCurrentQueueDepth);
					AddDropped;
				end;
			end;
          end;
        Block:
          begin
            while fQueue.Count >= fPolicy.MaxDepth do
              TMonitor.Wait(self, Cardinal(-1));
          end;
        Deadline:
          begin
            if fPolicy.DeadlineUs <= 0 then
            begin
              AddDropped;
              exit(False);
            end
            else
            begin
              lDeadlineMs := Cardinal((fPolicy.DeadlineUs + 999) div 1000);
              if lDeadlineMs = 0 then
                lDeadlineMs := 1;
              lTimer := TMaxStopwatch.StartNew;
              while fQueue.Count >= fPolicy.MaxDepth do
              begin
                lElapsedMs := lTimer.ElapsedMilliseconds;
                lRemainingMs := Int64(lDeadlineMs) - lElapsedMs;
                if lRemainingMs <= 0 then
                begin
                  AddDropped;
                  exit(False);
                end;
                if lRemainingMs > High(Cardinal) then
                  lWaitMs := High(Cardinal)
                else
                  lWaitMs := lRemainingMs;
                TMonitor.Wait(self, lWaitMs);
              end;
            end;
          end;
      end;
    end;

    // Wrap with deadline staleness guard (only if the item can actually sit in the queue)
    lNeedDeadlineGuard := (fPolicy.Overflow = Deadline) and (fPolicy.DeadlineUs > 0) and (fProcessing or (fQueue.Count > 0));
    if lNeedDeadlineGuard then
    begin
      lDeadlineUs := fPolicy.DeadlineUs;
      lDeadlineTicks := (lDeadlineUs * TMaxStopwatch.Frequency) div 1000000;
      if lDeadlineTicks <= 0 then
        lDeadlineTicks := 1;

      lEnqueueTimer := TMaxStopwatch.StartNew;
      lWrapped :=
        procedure
        begin
          if (fPolicy.Overflow = Deadline) and (fPolicy.DeadlineUs = lDeadlineUs) then
          begin
            if lEnqueueTimer.ElapsedTicks >= lDeadlineTicks then
            begin
              AddDropped;
              Exit;
            end;
          end;
          aProc();
        end;
    end
    else
      lWrapped := aProc;

	fQueue.Enqueue(lWrapped);
	Inc(fCurrentQueueDepth);
	if fCurrentQueueDepth > fMaxQueueDepth then
		fMaxQueueDepth := fCurrentQueueDepth;
	CheckHighWater;
	TouchMetrics;
    if Assigned(gDispatchTrace) then
    begin
      lTrace.Kind := TmaxTraceKind.TraceEnqueue;
      lTrace.Topic := fMetricName;
      lTrace.Delivery := TmaxDelivery.Posting;
      lTrace.QueueDepth := fCurrentQueueDepth;
      lTrace.DurationUs := 0;
      lTrace.SubscriberToken := 0;
      lTrace.SubscriberIndex := -1;
      lTrace.ExceptionClassName := '';
      lTrace.ExceptionMessage := '';
      lEmitTrace := True;
    end;
    lAlreadyProcessing := fProcessing;
    if not lAlreadyProcessing then
    begin
      fProcessing := True;
      aDispatchedInline := True;
    end;
  finally
    TMonitor.exit(self);
  end;

  if lEmitTrace and Assigned(gDispatchTrace) then
    gDispatchTrace(lTrace);
  if lAlreadyProcessing then
    Exit(Result);
  
  // Processing loop (unchanged)
  while True do
  begin
    TMonitor.Enter(self);
    try
      if fQueue.Count = 0 then
      begin
        fProcessing := False;
        TMonitor.PulseAll(self);
        TouchMetrics;
        exit;
      end;
	lProc := fQueue.Dequeue();
	if fCurrentQueueDepth > 0 then
		Dec(fCurrentQueueDepth);
	CheckHighWater;
	TouchMetrics;
      TMonitor.Pulse(self);
    finally
      TMonitor.exit(self);
    end;
    try
      lProc();
    except
      TMonitor.Enter(self);
      try
        fProcessing := False;
        TMonitor.PulseAll(self);
        TouchMetrics;
      finally
        TMonitor.Exit(self);
      end;
      raise;
    end;
  end;
end;

procedure TmaxTopicBase.SetSticky(aEnable: boolean);
begin
  fSticky := aEnable;
end;

function NameEquals(const aLeft: TmaxString; const aRight: TmaxString): boolean; inline;
begin
  Result := SameText(aLeft, aRight);
end;

function TypeMetricName(const aInfo: PTypeInfo): TmaxString; inline;
begin
  Result := GetTypeName(aInfo);
end;

function NamedMetricName(const aName: TmaxString): TmaxString; inline;
begin
  Result := UpperCase(aName);
end;

function NamedTypeMetricName(const aName: TmaxString; const aInfo: PTypeInfo): TmaxString; inline;
begin
  Result := UpperCase(aName) + ':' + GetTypeName(aInfo);
end;

function GuidMetricName(const aGuid: TGuid): TmaxString; inline;
begin
  Result := GuidToString(aGuid);
end;

{ TmaxMetricsIndex }

constructor TmaxMetricsIndex.CreateEmpty;
begin
  inherited Create;
  SetLength(fTyped, 0);
  SetLength(fNamed, 0);
  SetLength(fNamedTyped, 0);
  SetLength(fGuid, 0);
end;

function TmaxMetricsIndex.AddTyped(const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
var
  lIdx: integer;
  lLen: integer;
  lNew: TmaxMetricsIndex;
begin
  if (aKey = nil) or (aTopic = nil) then
    Exit(Self);
  for lIdx := 0 to High(fTyped) do
    if fTyped[lIdx].Key = aKey then
      Exit(Self);

  lNew := TmaxMetricsIndex.CreateEmpty;
  lNew.fNamed := fNamed;
  lNew.fNamedTyped := fNamedTyped;
  lNew.fGuid := fGuid;

  lLen := Length(fTyped);
  SetLength(lNew.fTyped, lLen + 1);
  for lIdx := 0 to lLen - 1 do
    lNew.fTyped[lIdx] := fTyped[lIdx];
  lNew.fTyped[lLen].Key := aKey;
  lNew.fTyped[lLen].Topic := aTopic;
  Result := lNew;
end;

function TmaxMetricsIndex.AddNamed(const aNameKey: TmaxString; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
var
  lIdx: integer;
  lLen: integer;
  lNew: TmaxMetricsIndex;
begin
  if (aNameKey = '') or (aTopic = nil) then
    Exit(Self);
  for lIdx := 0 to High(fNamed) do
    if NameEquals(fNamed[lIdx].NameKey, aNameKey) then
      Exit(Self);

  lNew := TmaxMetricsIndex.CreateEmpty;
  lNew.fTyped := fTyped;
  lNew.fNamedTyped := fNamedTyped;
  lNew.fGuid := fGuid;

  lLen := Length(fNamed);
  SetLength(lNew.fNamed, lLen + 1);
  for lIdx := 0 to lLen - 1 do
    lNew.fNamed[lIdx] := fNamed[lIdx];
  lNew.fNamed[lLen].NameKey := aNameKey;
  lNew.fNamed[lLen].Topic := aTopic;
  Result := lNew;
end;

function TmaxMetricsIndex.AddNamedTyped(const aNameKey: TmaxString; const aKey: PTypeInfo; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
var
  lIdx: integer;
  lLen: integer;
  lNew: TmaxMetricsIndex;
begin
  if (aNameKey = '') or (aKey = nil) or (aTopic = nil) then
    Exit(Self);
  for lIdx := 0 to High(fNamedTyped) do
    if NameEquals(fNamedTyped[lIdx].NameKey, aNameKey) and (fNamedTyped[lIdx].Key = aKey) then
      Exit(Self);

  lNew := TmaxMetricsIndex.CreateEmpty;
  lNew.fTyped := fTyped;
  lNew.fNamed := fNamed;
  lNew.fGuid := fGuid;

  lLen := Length(fNamedTyped);
  SetLength(lNew.fNamedTyped, lLen + 1);
  for lIdx := 0 to lLen - 1 do
    lNew.fNamedTyped[lIdx] := fNamedTyped[lIdx];
  lNew.fNamedTyped[lLen].NameKey := aNameKey;
  lNew.fNamedTyped[lLen].Key := aKey;
  lNew.fNamedTyped[lLen].Topic := aTopic;
  Result := lNew;
end;

function TmaxMetricsIndex.AddGuid(const aKey: TGuid; const aTopic: TmaxTopicBase): ImaxMetricsIndex;
var
  lIdx: integer;
  lLen: integer;
  lNew: TmaxMetricsIndex;
begin
  if (aTopic = nil) or IsEqualGUID(aKey, cGuidNull) then
    Exit(Self);
  for lIdx := 0 to High(fGuid) do
    if IsEqualGUID(fGuid[lIdx].Key, aKey) then
      Exit(Self);

  lNew := TmaxMetricsIndex.CreateEmpty;
  lNew.fTyped := fTyped;
  lNew.fNamed := fNamed;
  lNew.fNamedTyped := fNamedTyped;

  lLen := Length(fGuid);
  SetLength(lNew.fGuid, lLen + 1);
  for lIdx := 0 to lLen - 1 do
    lNew.fGuid[lIdx] := fGuid[lIdx];
  lNew.fGuid[lLen].Key := aKey;
  lNew.fGuid[lLen].Topic := aTopic;
  Result := lNew;
end;

function TmaxMetricsIndex.GetStatsForType(const aKey: PTypeInfo): TmaxTopicStats;
var
  lIdx: integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if aKey = nil then
    Exit;
  for lIdx := 0 to High(fTyped) do
    if fTyped[lIdx].Key = aKey then
      Exit(fTyped[lIdx].Topic.GetStats);
end;

function TmaxMetricsIndex.GetStatsGuid(const aKey: TGuid): TmaxTopicStats;
var
  lIdx: integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if IsEqualGUID(aKey, cGuidNull) then
    Exit;
  for lIdx := 0 to High(fGuid) do
    if IsEqualGUID(fGuid[lIdx].Key, aKey) then
      Exit(fGuid[lIdx].Topic.GetStats);
end;

function TmaxMetricsIndex.GetStatsNamed(const aNameKey: TmaxString): TmaxTopicStats;
var
  lIdx: integer;
  lStats: TmaxTopicStats;
begin
  FillChar(Result, SizeOf(Result), 0);
  if aNameKey = '' then
    Exit;

  for lIdx := 0 to High(fNamed) do
    if NameEquals(fNamed[lIdx].NameKey, aNameKey) then
    begin
      Result := fNamed[lIdx].Topic.GetStats;
      break;
    end;

  for lIdx := 0 to High(fNamedTyped) do
    if NameEquals(fNamedTyped[lIdx].NameKey, aNameKey) then
    begin
      lStats := fNamedTyped[lIdx].Topic.GetStats;
      Result.PostsTotal := Result.PostsTotal + lStats.PostsTotal;
      Result.DeliveredTotal := Result.DeliveredTotal + lStats.DeliveredTotal;
      Result.DroppedTotal := Result.DroppedTotal + lStats.DroppedTotal;
      Result.ExceptionsTotal := Result.ExceptionsTotal + lStats.ExceptionsTotal;
      if lStats.MaxQueueDepth > Result.MaxQueueDepth then
        Result.MaxQueueDepth := lStats.MaxQueueDepth;
      Result.CurrentQueueDepth := Result.CurrentQueueDepth + lStats.CurrentQueueDepth;
    end;
end;

function TmaxMetricsIndex.GetTotals: TmaxTopicStats;
var
  lIdx: integer;
  lStats: TmaxTopicStats;
begin
  FillChar(Result, SizeOf(Result), 0);

  for lIdx := 0 to High(fTyped) do
  begin
    lStats := fTyped[lIdx].Topic.GetStats;
    Result.PostsTotal := Result.PostsTotal + lStats.PostsTotal;
    Result.DeliveredTotal := Result.DeliveredTotal + lStats.DeliveredTotal;
    Result.DroppedTotal := Result.DroppedTotal + lStats.DroppedTotal;
    Result.ExceptionsTotal := Result.ExceptionsTotal + lStats.ExceptionsTotal;
    if lStats.MaxQueueDepth > Result.MaxQueueDepth then
      Result.MaxQueueDepth := lStats.MaxQueueDepth;
    Result.CurrentQueueDepth := Result.CurrentQueueDepth + lStats.CurrentQueueDepth;
  end;

  for lIdx := 0 to High(fNamed) do
  begin
    lStats := fNamed[lIdx].Topic.GetStats;
    Result.PostsTotal := Result.PostsTotal + lStats.PostsTotal;
    Result.DeliveredTotal := Result.DeliveredTotal + lStats.DeliveredTotal;
    Result.DroppedTotal := Result.DroppedTotal + lStats.DroppedTotal;
    Result.ExceptionsTotal := Result.ExceptionsTotal + lStats.ExceptionsTotal;
    if lStats.MaxQueueDepth > Result.MaxQueueDepth then
      Result.MaxQueueDepth := lStats.MaxQueueDepth;
    Result.CurrentQueueDepth := Result.CurrentQueueDepth + lStats.CurrentQueueDepth;
  end;

  for lIdx := 0 to High(fNamedTyped) do
  begin
    lStats := fNamedTyped[lIdx].Topic.GetStats;
    Result.PostsTotal := Result.PostsTotal + lStats.PostsTotal;
    Result.DeliveredTotal := Result.DeliveredTotal + lStats.DeliveredTotal;
    Result.DroppedTotal := Result.DroppedTotal + lStats.DroppedTotal;
    Result.ExceptionsTotal := Result.ExceptionsTotal + lStats.ExceptionsTotal;
    if lStats.MaxQueueDepth > Result.MaxQueueDepth then
      Result.MaxQueueDepth := lStats.MaxQueueDepth;
    Result.CurrentQueueDepth := Result.CurrentQueueDepth + lStats.CurrentQueueDepth;
  end;

  for lIdx := 0 to High(fGuid) do
  begin
    lStats := fGuid[lIdx].Topic.GetStats;
    Result.PostsTotal := Result.PostsTotal + lStats.PostsTotal;
    Result.DeliveredTotal := Result.DeliveredTotal + lStats.DeliveredTotal;
    Result.DroppedTotal := Result.DroppedTotal + lStats.DroppedTotal;
    Result.ExceptionsTotal := Result.ExceptionsTotal + lStats.ExceptionsTotal;
    if lStats.MaxQueueDepth > Result.MaxQueueDepth then
      Result.MaxQueueDepth := lStats.MaxQueueDepth;
    Result.CurrentQueueDepth := Result.CurrentQueueDepth + lStats.CurrentQueueDepth;
  end;
end;

{ TTypedTopic<T> }

constructor TTypedTopic<t>.Create;
begin
  inherited Create;
  fPendingLock := TmaxMonitorObject.Create;
  fNextToken := 1;
  fStickyFast := 0;
  fCoalesceFast := 0;
  SetLength(fSubs, 0);
  SetLength(fSnapshotCache, 0);
  fSubsVersion := 1;
  fSnapshotVersion := 0;
end;

procedure TTypedTopic<t>.PruneDeadLocked;
var
  lNeedsPrune: boolean;
  lIdx, lCount, lOut: integer;
  lCopy: TArray<TTypedSubscriber<t>>;
  lKeep: boolean;
begin
  lCount := length(fSubs);
  if lCount = 0 then
    exit;
  lNeedsPrune := False;
  for lIdx := 0 to lCount - 1 do
    if (not fSubs[lIdx].Target.IsAlive) or
      (assigned(fSubs[lIdx].State) and not fSubs[lIdx].State.IsActive) then
    begin
      lNeedsPrune := True;
      break;
    end;
  if not lNeedsPrune then
    exit;
  SetLength(lCopy, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
  begin
    lKeep := fSubs[lIdx].Target.IsAlive;
    if lKeep and assigned(fSubs[lIdx].State) then
      lKeep := fSubs[lIdx].State.IsActive;
    if lKeep then
    begin
      lCopy[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  end;
  SetLength(lCopy, lOut);
  fSubs := lCopy;
  Inc(fSubsVersion);
end;

function TTypedTopic<t>.Add(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState; const aTarget: TObject = nil): TmaxSubscriptionToken;
var
  lNew: TArray<TTypedSubscriber<t>>;
  lSub: TTypedSubscriber<t>;
begin
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    if fNextToken = 0 then
      fNextToken := 1;
    lSub.Handler := aHandler;
    lSub.Mode := aMode;
    lSub.Token := fNextToken;
    lSub.Target := TmaxWeakTarget.Create(aTarget); // store weak target when available (object-method overload)
    lSub.State := TmaxSubscriptionState.Create;
    aState := lSub.State;
    Inc(fNextToken);
    lNew := copy(fSubs);
    SetLength(lNew, length(lNew) + 1);
    lNew[High(lNew)] := lSub;
    fSubs := lNew;
    Inc(fSubsVersion);
    Result := lSub.Token;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TTypedTopic<t>.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TTypedSubscriber<t>>;
begin
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    lCount := length(fSubs);
    if lCount = 0 then
      exit;
    lNew := nil;
    SetLength(lNew, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if fSubs[lIdx].Token <> aToken then
      begin
        lNew[lOut] := fSubs[lIdx];
        Inc(lOut);
      end
      else if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if lOut = lCount then
    begin
      SetLength(lNew, 0);
      exit;
    end;
    SetLength(lNew, lOut);
    fSubs := lNew;
    Inc(fSubsVersion);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTypedTopic<t>.Snapshot: TArray<TTypedSubscriber<t>>;
begin
  TMonitor.Enter(Self);
  try
    if fSnapshotVersion <> fSubsVersion then
    begin
      fSnapshotCache := fSubs;
      fSnapshotVersion := fSubsVersion;
    end;
    Result := fSnapshotCache;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTypedTopic<t>.SnapshotAndTryBeginDirectDispatch(out aSubs: TArray<TTypedSubscriber<t>>): boolean;
var
  lEmitTrace: boolean;
  lTrace: TmaxDispatchTrace;
begin
  lEmitTrace := False;
  TMonitor.Enter(Self);
  try
    if fSnapshotVersion <> fSubsVersion then
    begin
      fSnapshotCache := fSubs;
      fSnapshotVersion := fSubsVersion;
    end;
    aSubs := fSnapshotCache;
    Result := (Length(aSubs) <> 0) and (fPolicy.MaxDepth = 0) and (not fProcessing) and (fQueue.Count = 0);
    if Result then
    begin
      fProcessing := True;
      if Assigned(gDispatchTrace) then
      begin
        lTrace.Kind := TmaxTraceKind.TraceEnqueue;
        lTrace.Topic := fMetricName;
        lTrace.Delivery := TmaxDelivery.Posting;
        lTrace.QueueDepth := fCurrentQueueDepth;
        lTrace.DurationUs := 0;
        lTrace.SubscriberToken := 0;
        lTrace.SubscriberIndex := -1;
        lTrace.ExceptionClassName := '';
        lTrace.ExceptionMessage := '';
        lEmitTrace := True;
      end;
    end;
  finally
    TMonitor.Exit(Self);
  end;
  if lEmitTrace and Assigned(gDispatchTrace) then
    gDispatchTrace(lTrace);
end;

procedure TTypedTopic<t>.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TTypedSubscriber<t>>;
begin
  if aTarget = nil then
    exit;
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    lCount := length(fSubs);
    if lCount = 0 then
      exit;
    lNew := nil;
    SetLength(lNew, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if not fSubs[lIdx].Target.Matches(aTarget) then
      begin
        lNew[lOut] := fSubs[lIdx];
        Inc(lOut);
      end
      else if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if lOut <> lCount then
    begin
      SetLength(lNew, lOut);
      fSubs := lNew;
      Inc(fSubsVersion);
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TTypedTopic<t>.SetSticky(aEnable: boolean);
begin
  TMonitor.Enter(Self);
  try
    inherited SetSticky(aEnable);
    if not aEnable then
      fHasLast := False;
    TInterlocked.Exchange(fStickyFast, Ord(aEnable));
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TTypedTopic<t>.ResetTopic;
var
  lIdx: integer;
begin
  inherited ResetTopic;

  TMonitor.Enter(Self);
  try
    for lIdx := 0 to High(fSubs) do
      if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if Length(fSubs) <> 0 then
      Inc(fSubsVersion);
    SetLength(fSubs, 0);
    SetLength(fSnapshotCache, 0);
    fSnapshotVersion := 0;
    fHasLast := False;
    TInterlocked.Exchange(fStickyFast, 0);
  finally
    TMonitor.Exit(Self);
  end;

  TMonitor.Enter(fPendingLock);
  try
    fCoalesce := False;
    fKeyFunc := nil;
    fWindowUs := 0;
    fFlushScheduled := False;
    TInterlocked.Exchange(fCoalesceFast, 0);
    if fPending <> nil then
    begin
      fPending.Free;
      fPending := nil;
    end;
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

procedure TTypedTopic<t>.Cache(const aEvent: t);
begin
  if TInterlocked.CompareExchange(fStickyFast, 0, 0) = 0 then
    Exit;
  TMonitor.Enter(Self);
  try
    if fSticky then
    begin
      fLast := aEvent;
      fHasLast := True;
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTypedTopic<t>.TryGetCached(out aEvent: t): boolean;
begin
  if TInterlocked.CompareExchange(fStickyFast, 0, 0) = 0 then
    Exit(False);
  TMonitor.Enter(Self);
  try
    Result := fSticky and fHasLast;
    if Result then
      aEvent := fLast;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TTypedTopic<t>.SetCoalesce(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
begin
  TMonitor.Enter(fPendingLock);
  try
    fCoalesce := assigned(aKeyOf);
    TInterlocked.Exchange(fCoalesceFast, Ord(fCoalesce));
    fKeyFunc := aKeyOf;
    if aWindowUs < 0 then
      fWindowUs := 0
    else
      fWindowUs := aWindowUs;
    if fCoalesce then
    begin
      if fPending = nil then
      begin
        fPending := TDictionary<TmaxString, t>.Create;
      end;
    end
    else
    begin
      fFlushScheduled := False;
      if fPending <> nil then
      begin
        fPending.Free;
        fPending := nil;
      end;
    end;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

function TTypedTopic<t>.HasCoalesce: boolean;
begin
  Result := TInterlocked.CompareExchange(fCoalesceFast, 0, 0) <> 0;
end;

function TTypedTopic<t>.CoalesceKey(const aEvent: t): TmaxString;
var
  lKeyFunc: TmaxKeyFunc<t>;
begin
  if TInterlocked.CompareExchange(fCoalesceFast, 0, 0) = 0 then
    Exit('');
  TMonitor.Enter(fPendingLock);
  try
    lKeyFunc := fKeyFunc;
  finally
    TMonitor.Exit(fPendingLock);
  end;
  if assigned(lKeyFunc) then
    Result := lKeyFunc(aEvent)
  else
    Result := '';
end;

function TTypedTopic<t>.AddOrUpdatePending(const aKey: TmaxString; const aEvent: t): boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending = nil then
    begin
      fPending := TDictionary<TmaxString, t>.Create;
    end;
    fPending.AddOrSetValue(aKey, aEvent);
    Result := not fFlushScheduled;
    fFlushScheduled := True;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

function TTypedTopic<t>.PopPending(const aKey: TmaxString; out aEvent: t): boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    Result := False;
    if fPending = nil then
      exit;
    if fPending.TryGetValue(aKey, aEvent) then
    begin
      fPending.Remove(aKey);
      Result := True;
    end;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

function TTypedTopic<t>.PopAllPending(out aEvents: TArray<t>): boolean;
var
  lPair: TPair<TmaxString, t>;
var
  lIdx: Integer;
begin
  SetLength(aEvents, 0);
  TMonitor.Enter(fPendingLock);
  try
    fFlushScheduled := False;
    if (fPending = nil) or (fPending.Count = 0) then
      exit(False);
    SetLength(aEvents, fPending.Count);
    lIdx := 0;
    for lPair in fPending do
    begin
      aEvents[lIdx] := lPair.Value;
      Inc(lIdx);
    end;
    fPending.Clear;
    if lIdx <> Length(aEvents) then
      SetLength(aEvents, lIdx);
    Result := lIdx > 0;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

procedure TTypedTopic<t>.ClearPending;
begin
  TMonitor.Enter(fPendingLock);
  try
    fFlushScheduled := False;
    if fPending <> nil then
      fPending.Clear;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

function TTypedTopic<t>.CoalesceWindow: integer;
begin
  TMonitor.Enter(fPendingLock);
  try
    Result := fWindowUs;
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

destructor TTypedTopic<t>.Destroy;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending <> nil then
      fPending.Free;
    fPending := nil;
  finally
    TMonitor.exit(fPendingLock);
  end;
  fPendingLock.Free;
  inherited Destroy;
end;

{ TNamedTopic }

function TNamedTopic.Add(const aHandler: TmaxProc; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
var
  lSub: TNamedSubscriber;
  lNew: TArray<TNamedSubscriber>;
begin
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    if fNextToken = 0 then
      fNextToken := 1;
    lSub.Handler := aHandler;
    lSub.Mode := aMode;
    lSub.Token := fNextToken;
    lSub.Target := TmaxWeakTarget.Create(nil); // cannot derive target from an anonymous method; treat as always-alive
    lSub.State := TmaxSubscriptionState.Create;
    aState := lSub.State;
    Inc(fNextToken);
    lNew := copy(fSubs);
    SetLength(lNew, length(lNew) + 1);
    lNew[High(lNew)] := lSub;
    fSubs := lNew;
    Inc(fSubsVersion);
    Result := lSub.Token;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TNamedSubscriber>;
begin
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    lCount := length(fSubs);
    if lCount = 0 then
      exit;
    lNew := nil;
    SetLength(lNew, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if fSubs[lIdx].Token <> aToken then
      begin
        lNew[lOut] := fSubs[lIdx];
        Inc(lOut);
      end
      else if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if lOut = lCount then
    begin
      SetLength(lNew, 0);
      exit;
    end;
    SetLength(lNew, lOut);
    fSubs := lNew;
    Inc(fSubsVersion);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.PruneDeadLocked;
var
  lNeedsPrune: boolean;
  lIdx, lCount, lOut: integer;
  lCopy: TArray<TNamedSubscriber>;
  lKeep: boolean;
begin
  lCount := length(fSubs);
  if lCount = 0 then
    exit;
  lNeedsPrune := False;
  for lIdx := 0 to lCount - 1 do
    if (not fSubs[lIdx].Target.IsAlive) or
      (assigned(fSubs[lIdx].State) and not fSubs[lIdx].State.IsActive) then
    begin
      lNeedsPrune := True;
      break;
    end;
  if not lNeedsPrune then
    exit;
  SetLength(lCopy, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
  begin
    lKeep := fSubs[lIdx].Target.IsAlive;
    if lKeep and assigned(fSubs[lIdx].State) then
      lKeep := fSubs[lIdx].State.IsActive;
    if lKeep then
    begin
      lCopy[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  end;
  SetLength(lCopy, lOut);
  fSubs := lCopy;
  Inc(fSubsVersion);
end;

function TNamedTopic.Snapshot: TArray<TNamedSubscriber>;
begin
  TMonitor.Enter(Self);
  try
    if fSnapshotVersion <> fSubsVersion then
    begin
      fSnapshotCache := fSubs;
      fSnapshotVersion := fSubsVersion;
    end;
    Result := fSnapshotCache;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TNamedSubscriber>;
begin
  if aTarget = nil then
    exit;
  TMonitor.Enter(Self);
  try
    PruneDeadLocked;
    lCount := length(fSubs);
    if lCount = 0 then
      exit;
    lNew := nil;
    SetLength(lNew, lCount);
    lOut := 0;
    for lIdx := 0 to lCount - 1 do
      if not fSubs[lIdx].Target.Matches(aTarget) then
      begin
        lNew[lOut] := fSubs[lIdx];
        Inc(lOut);
      end
      else if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if lOut <> lCount then
    begin
      SetLength(lNew, lOut);
      fSubs := lNew;
      Inc(fSubsVersion);
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.SetSticky(aEnable: boolean);
begin
  TMonitor.Enter(Self);
  try
    inherited SetSticky(aEnable);
    if not aEnable then
      fHasLast := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.ResetTopic;
var
  lIdx: integer;
begin
  inherited ResetTopic;
  TMonitor.Enter(Self);
  try
    for lIdx := 0 to High(fSubs) do
      if assigned(fSubs[lIdx].State) then
        fSubs[lIdx].State.Deactivate;
    if Length(fSubs) <> 0 then
      Inc(fSubsVersion);
    SetLength(fSubs, 0);
    SetLength(fSnapshotCache, 0);
    fSnapshotVersion := 0;
    fHasLast := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TNamedTopic.Cache;
begin
  TMonitor.Enter(Self);
  try
    if fSticky then
      fHasLast := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TNamedTopic.HasCached: boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fSticky and fHasLast;
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TmaxSubscriptionBase }

constructor TmaxSubscriptionBase.Create(const aState: ImaxSubscriptionState);
begin
  inherited Create;
  fActive := True;
  fState := aState;
end;

destructor TmaxSubscriptionBase.Destroy;
begin
  if fActive then
    Unsubscribe;
  fState := nil;
  inherited Destroy;
end;

function TmaxSubscriptionBase.IsActive: boolean;
begin
  Result := fActive and assigned(fState) and fState.IsActive;
end;

{ TmaxTypedSubscription<T> }

constructor TmaxTypedSubscription<t>.Create(aTopic: TTypedTopic<t>; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
begin
  inherited Create(aState);
  fTopic := aTopic;
  fToken := aToken;
end;

procedure TmaxTypedSubscription<t>.Unsubscribe;
begin
  if fActive then
  begin
    if assigned(fState) then
      fState.Deactivate;
    fTopic.RemoveByToken(fToken);
    fState := nil;
    fActive := False;
  end;
end;

{ TmaxNamedSubscription }

constructor TmaxNamedSubscription.Create(aTopic: TNamedTopic; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
begin
  inherited Create(aState);
  fTopic := aTopic;
  fToken := aToken;
end;

procedure TmaxNamedSubscription.Unsubscribe;
begin
  if fActive then
  begin
    if assigned(fState) then
      fState.Deactivate;
    fTopic.RemoveByToken(fToken);
    fState := nil;
    fActive := False;
  end;
end;

{ TmaxNamedWildcardSubscription }

constructor TmaxNamedWildcardSubscription.Create(const aBus: TmaxBus; aToken: TmaxSubscriptionToken;
  const aState: ImaxSubscriptionState);
begin
  inherited Create(aState);
  fBus := aBus;
  fToken := aToken;
end;

procedure TmaxNamedWildcardSubscription.Unsubscribe;
begin
  if fActive then
  begin
    if Assigned(fState) then
      fState.Deactivate;
    if fBus <> nil then
      fBus.RemoveNamedWildcardByToken(fToken);
    fState := nil;
    fActive := False;
  end;
end;

{ TmaxAutoBridgeSubscription }

constructor TmaxAutoBridgeSubscription.Create(const aBus: TmaxBus; aToken: TmaxSubscriptionToken;
  const aState: ImaxSubscriptionState);
begin
  inherited Create(aState);
  fBus := aBus;
  fToken := aToken;
end;

procedure TmaxAutoBridgeSubscription.Unsubscribe;
begin
  if fActive then
  begin
    if Assigned(fState) then
      fState.Deactivate;
    if fBus <> nil then
      fBus.RemoveAutoBridgeByToken(fToken);
    fState := nil;
    fActive := False;
  end;
end;

{ TmaxDelayedPostHandle }

function TmaxDelayedPostHandle.Cancel: boolean;
begin
  Result := TInterlocked.CompareExchange(fState, 1, 0) = 0;
end;

function TmaxDelayedPostHandle.IsPending: boolean;
begin
  Result := TInterlocked.CompareExchange(fState, 0, 0) = 0;
end;

function DefaultAsync: IEventNexusScheduler;
begin
  if gAsyncScheduler <> nil then
    exit(gAsyncScheduler);
  if gAsyncFallback = nil then
    gAsyncFallback := TmaxRawThreadScheduler.Create;
  Result := gAsyncFallback;
end;

function maxBus: ImaxBus;
begin
  if gBus = nil then
  begin
    TMonitor.Enter(gBusLock);
    try
      if gBus = nil then
        gBus := TmaxBus.Create(DefaultAsync);
    finally
      TMonitor.Exit(gBusLock);
    end;
  end;
  Result := gBus;
end;

procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
begin
  gAsyncError := aHandler;
end;

procedure maxSetDispatchTrace(const aHandler: TOnDispatchTrace);
begin
  gDispatchTrace := aHandler;
end;

procedure maxSetMetricCallback(const aSampler: TOnMetricSample);
begin
  gMetricSample := aSampler;
end;

procedure maxSetMetricSampleInterval(aIntervalMs: Cardinal);
begin
  gMetricSampleIntervalMs := aIntervalMs;
  if aIntervalMs = 0 then
    gMetricSampleIntervalTicks := 0
  else
  begin
    gMetricSampleIntervalTicks := (UInt64(aIntervalMs) * UInt64(TMaxStopwatch.Frequency)) div 1000;
    if gMetricSampleIntervalTicks = 0 then
      gMetricSampleIntervalTicks := 1;
  end;
end;

procedure maxSetQueuePresetNamed(const aName: string; aPreset: TmaxQueuePreset);
var
  lBusImpl: ImaxBusImpl;
  lBus: ImaxBus;
  lNameKey: TmaxString;
begin
  lBus := maxBus;
  if not Supports(lBus, ImaxBusImpl, lBusImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  lNameKey := aName;
  TmaxBus(lBusImpl.GetSelf).SetQueuePresetNamed(lNameKey, aPreset);
end;

procedure maxSetQueuePresetForType(const aType: PTypeInfo; aPreset: TmaxQueuePreset);
var
  lBusImpl: ImaxBusImpl;
  lBus: ImaxBus;
begin
  lBus := maxBus;
  if not Supports(lBus, ImaxBusImpl, lBusImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  TmaxBus(lBusImpl.GetSelf).SetQueuePresetForType(aType, aPreset);
end;

procedure maxSetQueuePresetGuid(const aGuid: TGuid; aPreset: TmaxQueuePreset);
var
  lBusImpl: ImaxBusImpl;
  lBus: ImaxBus;
begin
  lBus := maxBus;
  if not Supports(lBus, ImaxBusImpl, lBusImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  TmaxBus(lBusImpl.GetSelf).SetQueuePresetGuid(aGuid, aPreset);
end;

procedure maxSetAsyncScheduler(const aScheduler: IEventNexusScheduler);
var
  lBusImpl: ImaxBusImpl;
  lAsync: IEventNexusScheduler;
begin
  TMonitor.Enter(gBusLock);
  try
    gAsyncScheduler := aScheduler;
    if gBus <> nil then
    begin
      if not Supports(gBus, ImaxBusImpl, lBusImpl) then
        raise Exception.Create(SInvalidBusImplementation);
      lAsync := DefaultAsync;
      TmaxBus(lBusImpl.GetSelf).SetAsyncScheduler(lAsync);
    end;
  finally
    TMonitor.Exit(gBusLock);
  end;
end;

function maxGetAsyncScheduler: IEventNexusScheduler;
begin
  if gAsyncScheduler <> nil then
    Result := gAsyncScheduler
  else
    Result := DefaultAsync;
end;

procedure maxSetMainThreadPolicy(aPolicy: TmaxMainThreadPolicy);
begin
  gMainThreadPolicy := aPolicy;
end;

 // Stable-capture invoke helpers (avoid capturing loop locals by reference)

class function TInvokeBox<T>.MakeProc(const aBox: TInvokeBox<T>): TmaxProc;
begin
  Result :=
    procedure
    var
      h: TmaxProcOf<T>;
      v: T;
      lTopic: TTypedTopic<T>;
      st: ImaxSubscriptionState;
      tok: TmaxSubscriptionToken;
    begin
      h := aBox.Handler;
      v := aBox.Value;
      lTopic := aBox.Topic;
      st := aBox.State;
      tok := aBox.Token;
      try
        try
          h(v);
          lTopic.AddDelivered(1);
        except
          on e: Exception do
          begin
            lTopic.AddException;
            if (e is EAccessViolation) or (e is EInvalidPointer) then
            begin
              lTopic.RemoveByToken(tok);
              Exit;
            end;
            raise;
          end;
        end;
      finally
        if st <> nil then
          st.Leave;
        aBox.Free;
      end;
    end;
end;

type
  TInvokeBoxNamed = class
  public
    Topic: TNamedTopic;
    Handler: TmaxProc;
    Token: TmaxSubscriptionToken;
    State: ImaxSubscriptionState;
  end;

function MakeNamedHandlerProc(const aBox: TInvokeBoxNamed): TmaxProc;
begin
  Result :=
    procedure
    var
      h: TmaxProc;
      t: TNamedTopic;
      st: ImaxSubscriptionState;
      tok: TmaxSubscriptionToken;
    begin
      h := aBox.Handler;
      t := aBox.Topic;
      st := aBox.State;
      tok := aBox.Token;
      try
        try
          h();
          t.AddDelivered(1);
        except
          on e: Exception do
          begin
            t.AddException;
            if (e is EAccessViolation) or (e is EInvalidPointer) then
            begin
              t.RemoveByToken(tok);
              Exit;
            end;
            raise;
          end;
        end;
      finally
        if st <> nil then
          st.Leave;
        aBox.Free;
      end;
    end;
end;

function MakeNamedAutoMethodProc(const aMethodPtr: TMethod): TmaxProc;
type
  TNoArgObjProc = procedure of object;
var
  lMethodPtr: TMethod;
begin
  lMethodPtr := aMethodPtr;
  Result :=
    procedure
    var
      lProc: TNoArgObjProc;
    begin
      TMethod(lProc) := lMethodPtr;
      lProc();
    end;
end;

function TmaxBus.AddAutoBridgeSubscription(aKind: TmaxAutoBridgeKind; const aParamType: PTypeInfo;
  const aNameKey: TmaxString; const aGuidKey: TGuid; const aMethodPtr: TMethod; aDelivery: TmaxDelivery;
  const aTarget: TObject): ImaxSubscription;
var
  lState: ImaxSubscriptionState;
  lEntry: TmaxAutoBridgeEntry;
begin
  lState := TmaxSubscriptionState.Create;
  TMonitor.Enter(fAutoBridgeLock);
  try
    lEntry := TmaxAutoBridgeEntry.Create(aKind, fAutoBridgeNextToken, aParamType, aNameKey, aGuidKey, aMethodPtr,
      aDelivery, lState, aTarget);
    Inc(fAutoBridgeNextToken);
    fAutoBridgeSubs.Add(lEntry);
    TInterlocked.Increment(fAutoBridgeCount);
    Result := TmaxAutoBridgeSubscription.Create(Self, lEntry.Token, lState);
  finally
    TMonitor.Exit(fAutoBridgeLock);
  end;
end;

procedure TmaxBus.RemoveAutoBridgeByToken(aToken: TmaxSubscriptionToken);
var
  lIdx: integer;
  lEntry: TmaxAutoBridgeEntry;
begin
  TMonitor.Enter(fAutoBridgeLock);
  try
    for lIdx := fAutoBridgeSubs.Count - 1 downto 0 do
      if fAutoBridgeSubs[lIdx].Token = aToken then
      begin
        lEntry := fAutoBridgeSubs[lIdx];
        if Assigned(lEntry.State) then
          lEntry.State.Deactivate;
        fAutoBridgeSubs.Delete(lIdx);
        TInterlocked.Decrement(fAutoBridgeCount);
        Break;
      end;
  finally
    TMonitor.Exit(fAutoBridgeLock);
  end;
end;

function TmaxBus.HasAutoBridgeSubscriptions: boolean;
begin
  Result := TInterlocked.CompareExchange(fAutoBridgeCount, 0, 0) <> 0;
end;

function TmaxBus.SnapshotAutoBridgeTyped(const aParamType: PTypeInfo): TArray<TmaxAutoBridgeSnapshot>;
var
  lIdx: integer;
  lOut: integer;
  lEntry: TmaxAutoBridgeEntry;
  lResult: TArray<TmaxAutoBridgeSnapshot>;
begin
  if not HasAutoBridgeSubscriptions then
    Exit(nil);
  TMonitor.Enter(fAutoBridgeLock);
  try
    SetLength(lResult, fAutoBridgeSubs.Count);
    lOut := 0;
    for lIdx := 0 to fAutoBridgeSubs.Count - 1 do
    begin
      lEntry := fAutoBridgeSubs[lIdx];
      if (lEntry.Kind <> AutoBridgeTyped) or (lEntry.ParamType <> aParamType) then
        Continue;
      if Assigned(lEntry.State) and (not lEntry.State.IsActive) then
        Continue;
      lResult[lOut].Token := lEntry.Token;
      lResult[lOut].MethodPtr := lEntry.MethodPtr;
      lResult[lOut].Mode := lEntry.Mode;
      lResult[lOut].State := lEntry.State;
      lResult[lOut].Target := lEntry.Target;
      Inc(lOut);
    end;
    SetLength(lResult, lOut);
    Result := lResult;
  finally
    TMonitor.Exit(fAutoBridgeLock);
  end;
end;

function TmaxBus.SnapshotAutoBridgeNamedTyped(const aNameKey: TmaxString;
  const aParamType: PTypeInfo): TArray<TmaxAutoBridgeSnapshot>;
var
  lIdx: integer;
  lOut: integer;
  lEntry: TmaxAutoBridgeEntry;
  lResult: TArray<TmaxAutoBridgeSnapshot>;
begin
  if not HasAutoBridgeSubscriptions then
    Exit(nil);
  TMonitor.Enter(fAutoBridgeLock);
  try
    SetLength(lResult, fAutoBridgeSubs.Count);
    lOut := 0;
    for lIdx := 0 to fAutoBridgeSubs.Count - 1 do
    begin
      lEntry := fAutoBridgeSubs[lIdx];
      if (lEntry.Kind <> AutoBridgeNamedTyped) or (lEntry.ParamType <> aParamType) or (lEntry.NameKey <> aNameKey) then
        Continue;
      if Assigned(lEntry.State) and (not lEntry.State.IsActive) then
        Continue;
      lResult[lOut].Token := lEntry.Token;
      lResult[lOut].MethodPtr := lEntry.MethodPtr;
      lResult[lOut].Mode := lEntry.Mode;
      lResult[lOut].State := lEntry.State;
      lResult[lOut].Target := lEntry.Target;
      Inc(lOut);
    end;
    SetLength(lResult, lOut);
    Result := lResult;
  finally
    TMonitor.Exit(fAutoBridgeLock);
  end;
end;

function TmaxBus.SnapshotAutoBridgeGuid(const aGuidKey: TGuid): TArray<TmaxAutoBridgeSnapshot>;
var
  lIdx: integer;
  lOut: integer;
  lEntry: TmaxAutoBridgeEntry;
  lResult: TArray<TmaxAutoBridgeSnapshot>;
begin
  if not HasAutoBridgeSubscriptions then
    Exit(nil);
  TMonitor.Enter(fAutoBridgeLock);
  try
    SetLength(lResult, fAutoBridgeSubs.Count);
    lOut := 0;
    for lIdx := 0 to fAutoBridgeSubs.Count - 1 do
    begin
      lEntry := fAutoBridgeSubs[lIdx];
      if (lEntry.Kind <> AutoBridgeGuidTyped) or (not IsEqualGUID(lEntry.GuidKey, aGuidKey)) then
        Continue;
      if Assigned(lEntry.State) and (not lEntry.State.IsActive) then
        Continue;
      lResult[lOut].Token := lEntry.Token;
      lResult[lOut].MethodPtr := lEntry.MethodPtr;
      lResult[lOut].Mode := lEntry.Mode;
      lResult[lOut].State := lEntry.State;
      lResult[lOut].Target := lEntry.Target;
      Inc(lOut);
    end;
    SetLength(lResult, lOut);
    Result := lResult;
  finally
    TMonitor.Exit(fAutoBridgeLock);
  end;
end;

procedure TmaxBus.DispatchAutoBridge<t>(const aTopic: TmaxString; const aSnapshots: TArray<TmaxAutoBridgeSnapshot>;
  const aEvent: t);
type
  TBridgeObjProc = procedure(const aValue: t) of object;
var
  lIdx: integer;
  lMode: TmaxDelivery;
  lToken: TmaxSubscriptionToken;
  lState: ImaxSubscriptionState;
  lHandler: TBridgeObjProc;
  lHandlerCopy: TBridgeObjProc;
  lStateCopy: ImaxSubscriptionState;
  lEventCopy: t;
  lScheduled: TmaxProc;
  lErrors: TmaxExceptionList;
  lDetails: TArray<TmaxDispatchErrorDetail>;
begin
  if Length(aSnapshots) = 0 then
    Exit;
  lErrors := nil;
  lDetails := nil;
  for lIdx := 0 to High(aSnapshots) do
  begin
    lState := aSnapshots[lIdx].State;
    if (lState <> nil) and (not lState.TryEnter) then
      Continue;
    if not aSnapshots[lIdx].Target.IsAlive then
    begin
      RemoveAutoBridgeByToken(aSnapshots[lIdx].Token);
      if lState <> nil then
        lState.Leave;
      Continue;
    end;

    lMode := aSnapshots[lIdx].Mode;
    lToken := aSnapshots[lIdx].Token;
    TMethod(lHandler) := aSnapshots[lIdx].MethodPtr;

    try
      if lMode = Posting then
      begin
        try
          lHandler(aEvent);
        finally
          if lState <> nil then
            lState.Leave;
        end;
      end
      else
      begin
        lHandlerCopy := lHandler;
        lStateCopy := lState;
        lEventCopy := aEvent;
        lScheduled :=
          procedure
          begin
            try
              lHandlerCopy(lEventCopy);
            finally
              if lStateCopy <> nil then
                lStateCopy.Leave;
            end;
          end;
        try
          Dispatch(aTopic, lMode, lScheduled, nil);
        except
          if lState <> nil then
            lState.Leave;
          raise;
        end;
      end;
    except
      on e: EmaxMainThreadRequired do
        raise;
      on e: Exception do
      begin
        AddDispatchError(aTopic, lMode, lToken, lIdx, e, lErrors, lDetails);
      end;
    end;
  end;
  if lErrors <> nil then
    raise EmaxDispatchError.Create(lErrors, lDetails);
end;

procedure TmaxBus.RememberAutoSubscription(const aInstance: TObject; const aSub: ImaxSubscription);
var
  lList: TmaxSubList;
begin
  if (aInstance = nil) or (aSub = nil) then
    Exit;
  TMonitor.Enter(fAutoSubsLock);
  try
    if not fAutoSubs.TryGetValue(aInstance, lList) then
    begin
      lList := TmaxSubList.Create;
      fAutoSubs.Add(aInstance, lList);
    end;
    lList.Add(aSub);
  finally
    TMonitor.Exit(fAutoSubsLock);
  end;
end;

procedure TmaxBus.AutoUnsubscribeInstance(const aInstance: TObject);
var
  lList: TmaxSubList;
  lSubs: TArray<ImaxSubscription>;
  i: Integer;
begin
  if aInstance = nil then
    Exit;
  lList := nil;
  TMonitor.Enter(fAutoSubsLock);
  try
    if not fAutoSubs.TryGetValue(aInstance, lList) then
      Exit;
    SetLength(lSubs, lList.Count);
    for i := 0 to lList.Count - 1 do
      lSubs[i] := lList[i];
    fAutoSubs.Remove(aInstance);
  finally
    TMonitor.Exit(fAutoSubsLock);
  end;
  for i := 0 to High(lSubs) do
    if lSubs[i] <> nil then
      lSubs[i].Unsubscribe;
end;

procedure TmaxBus.AutoSubscribeInstance(const aInstance: TObject);
var
  lCtx: TRttiContext;
  lType: TRttiType;

  procedure ProcessType(const aType: TRttiType);
  var
    lMethod: TRttiMethod;
    lAttr: TCustomAttribute;
    lAttrInstance: maxSubscribeAttribute;
    lParams: TArray<TRttiParameter>;
    lParamType: TRttiType;
    lFlags: TParamFlags;
    lSub: ImaxSubscription;
    lMethodPtr: TMethod;
    lName: string;
    lDelivery: TmaxDelivery;
  begin
    for lMethod in aType.GetMethods do
    begin
      if lMethod.Parent <> aType then
        Continue;
      if not (lMethod.Visibility in [mvPublic, mvProtected, mvPublished]) then
        Continue;
      if lMethod.IsClassMethod or lMethod.IsConstructor or lMethod.IsDestructor then
        Continue;
      lAttrInstance := nil;
      for lAttr in lMethod.GetAttributes do
        if lAttr is maxSubscribeAttribute then
        begin
          if lAttrInstance <> nil then
            raise EmaxInvalidSubscription.CreateFmt('Multiple maxSubscribe attributes on %s.%s', [aType.ToString, lMethod.Name]);
          lAttrInstance := maxSubscribeAttribute(lAttr);
        end;
      if lAttrInstance = nil then
        Continue;
      if lMethod.MethodKind <> mkProcedure then
        raise EmaxInvalidSubscription.CreateFmt('Method %s.%s must be a procedure', [aType.ToString, lMethod.Name]);
      lParams := lMethod.GetParameters;
      if Length(lParams) > 1 then
        raise EmaxInvalidSubscription.CreateFmt('Method %s.%s must have at most one parameter', [aType.ToString, lMethod.Name]);

      lDelivery := lAttrInstance.Delivery;
      lName := lAttrInstance.Name;
      lSub := nil;

      if lName = '' then
      begin
        if Length(lParams) <> 1 then
          raise EmaxInvalidSubscription.CreateFmt('Method %s.%s must have exactly one parameter for typed topics', [aType.ToString, lMethod.Name]);
        lParamType := lParams[0].ParamType;
        if lParamType = nil then
          raise EmaxInvalidSubscription.CreateFmt('Unable to resolve parameter type for %s.%s', [aType.ToString, lMethod.Name]);
        lFlags := lParams[0].Flags;
        if (pfVar in lFlags) or (pfOut in lFlags) then
          raise EmaxInvalidSubscription.CreateFmt('Parameter of %s.%s must be passed by value or const', [aType.ToString, lMethod.Name]);
        if lMethod.CodeAddress = nil then
          raise EmaxInvalidSubscription.CreateFmt('Method %s.%s is abstract and cannot be subscribed', [aType.ToString, lMethod.Name]);
        lMethodPtr.Code := lMethod.CodeAddress;
        lMethodPtr.Data := aInstance;
        if (lParamType is TRttiInterfaceType) and not IsEqualGUID(TRttiInterfaceType(lParamType).GUID, cGuidNull) then
          lSub := AddAutoBridgeSubscription(AutoBridgeGuidTyped, lParamType.Handle, '', TRttiInterfaceType(lParamType).GUID,
            lMethodPtr, lDelivery, aInstance)
        else
          lSub := AddAutoBridgeSubscription(AutoBridgeTyped, lParamType.Handle, '', cGuidNull, lMethodPtr, lDelivery,
            aInstance);
      end
      else
      begin
        if Length(lParams) = 0 then
        begin
          if lMethod.CodeAddress = nil then
            raise EmaxInvalidSubscription.CreateFmt('Method %s.%s is abstract and cannot be subscribed', [aType.ToString, lMethod.Name]);
          lMethodPtr.Code := lMethod.CodeAddress;
          lMethodPtr.Data := aInstance;
          lSub := SubscribeNamed(TmaxString(lName), MakeNamedAutoMethodProc(lMethodPtr), lDelivery);
        end
        else
        begin
          if Length(lParams) <> 1 then
            raise EmaxInvalidSubscription.CreateFmt('Method %s.%s must have zero or one parameter for named topics', [aType.ToString, lMethod.Name]);
          lParamType := lParams[0].ParamType;
          if lParamType = nil then
            raise EmaxInvalidSubscription.CreateFmt('Unable to resolve parameter type for %s.%s', [aType.ToString, lMethod.Name]);
          lFlags := lParams[0].Flags;
          if (pfVar in lFlags) or (pfOut in lFlags) then
            raise EmaxInvalidSubscription.CreateFmt('Parameter of %s.%s must be passed by value or const', [aType.ToString, lMethod.Name]);
          if lMethod.CodeAddress = nil then
            raise EmaxInvalidSubscription.CreateFmt('Method %s.%s is abstract and cannot be subscribed', [aType.ToString, lMethod.Name]);
          lMethodPtr.Code := lMethod.CodeAddress;
          lMethodPtr.Data := aInstance;
          lSub := AddAutoBridgeSubscription(AutoBridgeNamedTyped, lParamType.Handle, TmaxString(lName), cGuidNull,
            lMethodPtr, lDelivery, aInstance);
        end;
      end;

      if lSub = nil then
        raise EmaxInvalidSubscription.CreateFmt('Failed to subscribe %s.%s', [aType.ToString, lMethod.Name]);
      RememberAutoSubscription(aInstance, lSub);
    end;
  end;

begin
  if aInstance = nil then
    Exit;
  AutoUnsubscribeInstance(aInstance);
  lCtx := TRttiContext.Create;
  try
    lType := lCtx.GetType(aInstance.ClassType);
    while lType <> nil do
    begin
      ProcessType(lType);
      lType := lType.BaseType;
    end;
  finally
    lCtx.Free;
  end;
end;

{ TmaxBus }

procedure TmaxBus.DispatchTypedSubscribers<t>(const aTopicName: TmaxString; const aTopic: TTypedTopic<t>;
  const aSubs: TArray<TTypedSubscriber<t>>; const aValue: t; aRaiseMainThreadRequired: boolean);
var
  i: Integer;
  lHandler: TmaxProcOf<t>;
  lMode: TmaxDelivery;
  lToken: TmaxSubscriptionToken;
  lState: ImaxSubscriptionState;
  lErrs: TmaxExceptionList;
  lErrDetails: TArray<TmaxDispatchErrorDetail>;
  lBox: TInvokeBox<t>;
  lDeliveredCount: integer;
begin
  lErrs := nil;
  lErrDetails := nil;
  lDeliveredCount := 0;
  for i := 0 to High(aSubs) do
  begin
    lHandler := aSubs[i].Handler;
    lMode := aSubs[i].Mode;
    lToken := aSubs[i].Token;
    lState := aSubs[i].State;

    if (lState <> nil) and (not lState.TryEnter) then
      Continue;

    if not aSubs[i].Target.IsAlive then
    begin
      aTopic.RemoveByToken(lToken);
      if lState <> nil then
        lState.Leave;
      Continue;
    end;

    try
      if lMode = Posting then
      begin
        try
          try
            lHandler(aValue);
            Inc(lDeliveredCount);
          except
            on e: Exception do
            begin
              aTopic.AddException;
              if (e is EAccessViolation) or (e is EInvalidPointer) then
              begin
                aTopic.RemoveByToken(lToken);
                Continue;
              end;
              raise;
            end;
          end;
        finally
          if lState <> nil then
            lState.Leave;
        end;
      end else
      begin
        lBox := TInvokeBox<t>.Create;
        lBox.Topic := aTopic;
        lBox.Handler := lHandler;
        lBox.Value := aValue;
        lBox.Token := lToken;
        lBox.State := lState;
        Dispatch(aTopicName, lMode, TInvokeBox<t>.MakeProc(lBox), nil);
      end;
    except
      on e: EmaxMainThreadRequired do
      begin
        if aRaiseMainThreadRequired then
          raise;
        AddDispatchError(aTopicName, lMode, lToken, i, e, lErrs, lErrDetails);
      end;
      on e: Exception do
      begin
        AddDispatchError(aTopicName, lMode, lToken, i, e, lErrs, lErrDetails);
      end;
    end;
  end;
  if lDeliveredCount > 0 then
    aTopic.AddDelivered(lDeliveredCount);
  if lErrs <> nil then
    raise EmaxDispatchError.Create(lErrs, lErrDetails);
end;

procedure TmaxBus.ScheduleTypedCoalesce<t>(const aTopicName: TmaxString;
		  aTopic: TTypedTopic<t>; const aSubs: TArray<TTypedSubscriber<t>>);
var
  lSubsCopy: TArray<TTypedSubscriber<t>>;
  lScheduled: TmaxProc;
begin
  lSubsCopy := Copy(aSubs);
  lScheduled :=
    procedure
    var
      lEvents: TArray<t>;
    begin
      if not aTopic.PopAllPending(lEvents) then
        exit;
      
      aTopic.Enqueue(
        procedure
        var
          lEvtIdx: Integer;
          lEvt: t;
          lEx: EmaxDispatchError;
        begin
          for lEvtIdx := 0 to High(lEvents) do
          begin
            lEvt := lEvents[lEvtIdx];
            try
              DispatchTypedSubscribers<t>(aTopicName, aTopic, lSubsCopy, lEvt, False);
            except
              on e: EmaxDispatchError do
              begin
                if Assigned(gAsyncError) then
                begin
                  lEx := e;
                  gAsyncError(aTopicName, lEx);
                end;
              end;
            end;
          end;
        end);
    end;
  try
    fAsync.RunDelayed(lScheduled, aTopic.CoalesceWindow);
  except
    // Keep progress even if delayed scheduling backend rejects the submission.
    lScheduled();
  end;
end;

procedure TmaxBus.PublishMetricTypedTopic(const aKey: PTypeInfo; const aTopic: TmaxTopicBase);
begin
  if (aKey = nil) or (aTopic = nil) then
    Exit;
  fMetricsLock.BeginWrite;
  try
    fMetricsIndex := fMetricsIndex.AddTyped(aKey, aTopic);
  finally
    fMetricsLock.EndWrite;
  end;
end;

procedure TmaxBus.PublishMetricNamedTopic(const aNameKey: TmaxString; const aTopic: TmaxTopicBase);
begin
  if (aNameKey = '') or (aTopic = nil) then
    Exit;
  fMetricsLock.BeginWrite;
  try
    fMetricsIndex := fMetricsIndex.AddNamed(aNameKey, aTopic);
  finally
    fMetricsLock.EndWrite;
  end;
end;

procedure TmaxBus.PublishMetricNamedTypedTopic(const aNameKey: TmaxString; const aKey: PTypeInfo; const aTopic: TmaxTopicBase);
begin
  if (aNameKey = '') or (aKey = nil) or (aTopic = nil) then
    Exit;
  fMetricsLock.BeginWrite;
  try
    fMetricsIndex := fMetricsIndex.AddNamedTyped(aNameKey, aKey, aTopic);
  finally
    fMetricsLock.EndWrite;
  end;
end;

procedure TmaxBus.PublishMetricGuidTopic(const aKey: TGuid; const aTopic: TmaxTopicBase);
begin
  if (aTopic = nil) or IsEqualGUID(aKey, cGuidNull) then
    Exit;
  fMetricsLock.BeginWrite;
  try
    fMetricsIndex := fMetricsIndex.AddGuid(aKey, aTopic);
  finally
    fMetricsLock.EndWrite;
  end;
end;

{ TmaxBus }

constructor TmaxBus.Create(const aAsync: IEventNexusScheduler);
begin
  inherited Create;
  fAsync := aAsync;
  fTypedLock := TmaxMonitorObject.Create;
  fNamedLock := TmaxMonitorObject.Create;
  fNamedTypedLock := TmaxMonitorObject.Create;
  fGuidLock := TmaxMonitorObject.Create;
  fNamedWildcardLock := TmaxMonitorObject.Create;
  fMetricsIndex := TmaxMetricsIndex.CreateEmpty;
  fTyped := TmaxTypeTopicDict.Create([doOwnsValues]);
  fNamed := TmaxNameTopicDict.Create([doOwnsValues], TIStringComparer.Ordinal);
  fNamedTyped := TmaxNameTypeTopicDict.Create([doOwnsValues], TIStringComparer.Ordinal);
	fGuid := TmaxGuidTopicDict.Create([doOwnsValues]);
	fStickyTypes := TmaxBoolDictOfTypeInfo.Create;
	fStickyNames := TmaxBoolDictOfString.Create(TIStringComparer.Ordinal);
	fPresetTypes := TmaxPresetDictOfTypeInfo.Create;
  fPresetNames := TmaxPresetDictOfString.Create(TIStringComparer.Ordinal);
  fPresetGuids := TmaxPresetDictOfGuid.Create;
  SetLength(fNamedWildcardSubs, 0);
  SetLength(fNamedWildcardSnapshot, 0);
  fNamedWildcardVersion := 1;
  fNamedWildcardSnapshotVersion := 0;
  fNamedWildcardNextToken := 1;
  fAutoSubsLock := TmaxMonitorObject.Create;
  fAutoSubs := TmaxAutoSubDict.Create([doOwnsValues]);
  fAutoBridgeLock := TmaxMonitorObject.Create;
  fAutoBridgeSubs := TObjectList<TmaxAutoBridgeEntry>.Create(True);
  fAutoBridgeCount := 0;
  fAutoBridgeNextToken := 1;
  fDelayedPostEpoch := 0;
		fMainThreadId := TThread.CurrentThread.ThreadID;
end;

class function TmaxBus.DelayMsToUs(aDelayMs: Cardinal): integer;
const
  cMaxDelayMs = High(integer) div 1000;
begin
  if aDelayMs = 0 then
    Exit(0);
  if aDelayMs > cMaxDelayMs then
    Exit(High(integer));
  Result := integer(aDelayMs) * 1000;
end;

function TmaxBus.ScheduleDelayedPost(const aPostProc: TmaxProc; aDelayMs: Cardinal): ImaxDelayedPost;
var
  lDelayUs: integer;
  lEpoch: Int64;
  lHandle: ImaxDelayedPost;
begin
  lHandle := TmaxDelayedPostHandle.Create;
  lDelayUs := DelayMsToUs(aDelayMs);
  lEpoch := TInterlocked.CompareExchange(fDelayedPostEpoch, 0, 0);
  try
    fAsync.RunDelayed(
      procedure
      begin
        if TInterlocked.CompareExchange(fDelayedPostEpoch, 0, 0) <> lEpoch then
        begin
          lHandle.Cancel;
          Exit;
        end;
        if not lHandle.Cancel then
          Exit;
        if Assigned(aPostProc) then
          aPostProc();
      end,
      lDelayUs);
  except
    // Keep progress even when delayed scheduler submission fails.
    if lHandle.Cancel and Assigned(aPostProc) then
      aPostProc();
  end;
  Result := lHandle;
end;

procedure TmaxBus.SetAsyncScheduler(const aAsync: IEventNexusScheduler);
begin
  fConfigLock.BeginWrite;
  try
    fAsync := aAsync;
  finally
    fConfigLock.EndWrite;
  end;
end;

destructor TmaxBus.Destroy;
begin
  fMetricsIndex := nil;
  fTyped.Free;
  fNamedTyped.Free;
  fNamed.Free;
  fGuid.Free;
  fStickyTypes.Free;
  fStickyNames.Free;
  fPresetTypes.Free;
  fPresetNames.Free;
  fPresetGuids.Free;
  fAutoBridgeSubs.Free;
  fAutoBridgeLock.Free;
  fAutoSubs.Free;
  fAutoSubsLock.Free;
  fNamedWildcardLock.Free;
  fGuidLock.Free;
  fNamedTypedLock.Free;
  fNamedLock.Free;
  fTypedLock.Free;
  inherited Destroy;
end;

class function TmaxBus.PolicyForPreset(aPreset: TmaxQueuePreset): TmaxQueuePolicy;
begin
  case aPreset of
    TmaxQueuePreset.State:
      begin
        Result.MaxDepth := 256;
        Result.Overflow := DropOldest;
        Result.DeadlineUs := 0;
      end;
    TmaxQueuePreset.Action:
      begin
        Result.MaxDepth := 1024;
        Result.Overflow := Deadline;
        Result.DeadlineUs := 2000;
      end;
    TmaxQueuePreset.ControlPlane:
      begin
        Result.MaxDepth := 1;
        Result.Overflow := Block;
        Result.DeadlineUs := 0;
      end;
  else
    Result.MaxDepth := 0;
    Result.Overflow := DropNewest;
    Result.DeadlineUs := 0;
  end;
end;

procedure TmaxBus.SetQueuePresetForType(const aKey: PTypeInfo; aPreset: TmaxQueuePreset);
var
  lObj: TmaxTopicBase;
  lPolicy: TmaxQueuePolicy;
begin
  fConfigLock.BeginWrite;
  try
    if aPreset = TmaxQueuePreset.Unspecified then
      fPresetTypes.Remove(aKey)
    else
      fPresetTypes.AddOrSetValue(aKey, aPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lPolicy := PolicyForPreset(aPreset);
  TMonitor.Enter(fTypedLock);
  try
    if fTyped.TryGetValue(aKey, lObj) and (not lObj.HasExplicitPolicy) then
      lObj.SetPolicyImplicit(lPolicy);
  finally
    TMonitor.Exit(fTypedLock);
  end;
end;

procedure TmaxBus.SetQueuePresetNamed(const aNameKey: TmaxString; aPreset: TmaxQueuePreset);
var
  lObj: TmaxTopicBase;
  lTypeDict: TmaxTypeTopicDict;
  lPolicy: TmaxQueuePolicy;
  lInner: TPair<PTypeInfo, TmaxTopicBase>;
begin
  fConfigLock.BeginWrite;
  try
    if aPreset = TmaxQueuePreset.Unspecified then
      fPresetNames.Remove(aNameKey)
    else
      fPresetNames.AddOrSetValue(aNameKey, aPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lPolicy := PolicyForPreset(aPreset);
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(aNameKey, lObj) and (not lObj.HasExplicitPolicy) then
      lObj.SetPolicyImplicit(lPolicy);
  finally
    TMonitor.Exit(fNamedLock);
  end;

  TMonitor.Enter(fNamedTypedLock);
  try
    if fNamedTyped.TryGetValue(aNameKey, lTypeDict) then
      for lInner in lTypeDict do
        if not lInner.Value.HasExplicitPolicy then
          lInner.Value.SetPolicyImplicit(lPolicy);
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;
end;

procedure TmaxBus.SetQueuePresetGuid(const aGuid: TGuid; aPreset: TmaxQueuePreset);
var
  lObj: TmaxTopicBase;
  lPolicy: TmaxQueuePolicy;
begin
  fConfigLock.BeginWrite;
  try
    if aPreset = TmaxQueuePreset.Unspecified then
      fPresetGuids.Remove(aGuid)
    else
      fPresetGuids.AddOrSetValue(aGuid, aPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lPolicy := PolicyForPreset(aPreset);
  TMonitor.Enter(fGuidLock);
  try
    if fGuid.TryGetValue(aGuid, lObj) and (not lObj.HasExplicitPolicy) then
      lObj.SetPolicyImplicit(lPolicy);
  finally
    TMonitor.Exit(fGuidLock);
  end;
end;

procedure TmaxBus.Dispatch(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc; const aOnException: TmaxProc);
begin
  case aDelivery of
    Posting:
      try
        InvokeWithTrace(aTopic, aDelivery, aHandler);
      except
        on e: Exception do
        begin
          if Assigned(aOnException) then
            aOnException();
          raise;
        end;
      end;
    Main:
      if (TThread.CurrentThread.ThreadID = fMainThreadId) or fAsync.IsMainThread() then
      begin
        try
          InvokeWithTrace(aTopic, aDelivery, aHandler);
        except
          on e: Exception do
          begin
            if Assigned(aOnException) then
              aOnException();
            if Assigned(gAsyncError) then
              gAsyncError(aTopic, e);
          end;
        end;
      end
      else
      begin
        if not IsConsole then
        begin
          fAsync.RunOnMain(
            procedure
            begin
              try
                InvokeWithTrace(aTopic, aDelivery, aHandler);
              except
                on e: Exception do
                begin
                  if Assigned(aOnException) then
                    aOnException();
                  if Assigned(gAsyncError) then
                    gAsyncError(aTopic, e);
                end;
              end;
            end);
        end
        else
        begin
          case gMainThreadPolicy of
            TmaxMainThreadPolicy.Strict:
              raise EmaxMainThreadRequired.CreateFmt(
                'Main delivery requires a UI main thread (topic=%s, postingTid=%d)',
                [aTopic, TThread.CurrentThread.ThreadID]);
            TmaxMainThreadPolicy.DegradeToAsync:
              begin
                fAsync.RunAsync(
                  procedure
                  begin
                    try
                      InvokeWithTrace(aTopic, aDelivery, aHandler);
                    except
                      on e: Exception do
                      begin
                        if Assigned(aOnException) then
                          aOnException();
                        if Assigned(gAsyncError) then
                          gAsyncError(aTopic, e);
                      end;
                    end;
                  end);
              end;
            TmaxMainThreadPolicy.DegradeToPosting:
              begin
                try
                  InvokeWithTrace(aTopic, aDelivery, aHandler);
                except
                  on e: Exception do
                  begin
                    if Assigned(aOnException) then
                      aOnException();
                    if Assigned(gAsyncError) then
                      gAsyncError(aTopic, e);
                  end;
                end;
              end;
          end;
        end;
      end;
    Async:
      begin
        fAsync.RunAsync(
          procedure
          begin
            try
              InvokeWithTrace(aTopic, aDelivery, aHandler);
            except
              on e: Exception do
              begin
                if Assigned(aOnException) then
                  aOnException();
                if Assigned(gAsyncError) then
                  gAsyncError(aTopic, e);
              end;
            end;
          end);
      end;
    Background:
      if (TThread.CurrentThread.ThreadID = fMainThreadId) or fAsync.IsMainThread() then
      begin
        fAsync.RunAsync(
          procedure
          begin
            try
              InvokeWithTrace(aTopic, aDelivery, aHandler);
            except
              on e: Exception do
              begin
                if Assigned(aOnException) then
                  aOnException();
                if Assigned(gAsyncError) then
                  gAsyncError(aTopic, e);
              end;
            end;
          end)
      end
      else
      try
        InvokeWithTrace(aTopic, aDelivery, aHandler);
      except
        on e: Exception do
        begin
          if Assigned(aOnException) then
            aOnException();
          if Assigned(gAsyncError) then
            gAsyncError(aTopic, e);
        end;
      end;
  end;
end;

function TmaxBus.Subscribe<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lSend: boolean;
  lLast: t;
  lMetricName: TmaxString;
  lState: ImaxSubscriptionState;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lKey := TypeInfo(t);
  lMetricName := TypeMetricName(lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetTypes.TryGetValue(lKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lCreated := False;
  TMonitor.Enter(fTypedLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetricName);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetricName);
  finally
    TMonitor.Exit(fTypedLock);
  end;

  if lCreated then
    PublishMetricTypedTopic(lKey, lTopic);

  lToken := lTopic.Add(aHandler, aMode, lState);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetricName, aMode,
            procedure
            begin
              try
                try
                  aHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

function TmaxBus.Subscribe<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lSend: boolean;
  lLast: t;
  lMetricName: TmaxString;
  lState: ImaxSubscriptionState;
  lTarget: TObject;
  lWrapper: TmaxProcOf<t>;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lKey := TypeInfo(t);
  lMetricName := TypeMetricName(lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetTypes.TryGetValue(lKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lCreated := False;
  TMonitor.Enter(fTypedLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetricName);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetricName);
  finally
    TMonitor.Exit(fTypedLock);
  end;

  if lCreated then
    PublishMetricTypedTopic(lKey, lTopic);

  lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetricName, aMode,
            procedure
            begin
              try
                try
                  aHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.Post<t>(const aEvent: t);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lCreated := False;

  lKey := TypeInfo(t);
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeTyped(lKey);
  lTopic := nil;
  TMonitor.Enter(fTypedLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fTypedLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetTypes.TryGetValue(lKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
    begin
      if Length(lAutoSubs) <> 0 then
      begin
        if lMetric = '' then
          lMetric := TypeMetricName(lKey);
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      end;
      exit;
    end;

    TMonitor.Enter(fTypedLock);
    try
      if not fTyped.TryGetValue(lKey, lObj) then
      begin
        if lMetric = '' then
          lMetric := TypeMetricName(lKey);
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        if lPreset <> TmaxQueuePreset.Unspecified then
          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lCreated := True;
      end
      else
      begin
        lTopic := TTypedTopic<t>(lObj);
        if lMetric = '' then
          lMetric := lTopic.MetricName;
      end;
    finally
      TMonitor.Exit(fTypedLock);
    end;

    if lCreated then
      PublishMetricTypedTopic(lKey, lTopic);
  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := TypeMetricName(lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;
  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    lTopic.Enqueue(
      procedure
      begin
        DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      end);
  end;
  if Length(lAutoSubs) <> 0 then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
end;

function TmaxBus.TryPost<t>(const aEvent: t): boolean;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lCreated := False;

  Result := True;
  lKey := TypeInfo(t);
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeTyped(lKey);
  lTopic := nil;
  TMonitor.Enter(fTypedLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fTypedLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetTypes.TryGetValue(lKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
    begin
      if Length(lAutoSubs) <> 0 then
      begin
        if lMetric = '' then
          lMetric := TypeMetricName(lKey);
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      end;
      exit;
    end;

    TMonitor.Enter(fTypedLock);
    try
      if not fTyped.TryGetValue(lKey, lObj) then
      begin
        if lMetric = '' then
          lMetric := TypeMetricName(lKey);
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        if lPreset <> TmaxQueuePreset.Unspecified then
          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lCreated := True;
      end
      else
      begin
        lTopic := TTypedTopic<t>(lObj);
        if lMetric = '' then
          lMetric := lTopic.MetricName;
      end;
    finally
      TMonitor.Exit(fTypedLock);
    end;

    if lCreated then
      PublishMetricTypedTopic(lKey, lTopic);

    lTopic.Cache(aEvent);
    lTopic.AddPost;
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    exit;
  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := TypeMetricName(lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;
  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      Result := True;
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
      Result := True
    else
      Result := lTopic.Enqueue(
        procedure
        begin
          DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
        end);
  end;
  if Result and (Length(lAutoSubs) <> 0) then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
end;

function TmaxBus.PostResult<t>(const aEvent: t): TmaxPostResult;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSticky: boolean;
  lAccepted: boolean;
  lQueueDepth: UInt32;
  lWasProcessing: boolean;
begin
  lKey := TypeInfo(t);
  lTopic := nil;
  lQueueDepth := 0;
  lWasProcessing := False;

  TMonitor.Enter(fTypedLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fTypedLock);
  end;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lKey);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
      Exit(TmaxPostResult.NoTopic);
  end
  else
  begin
    lQueueDepth := lTopic.GetStats.CurrentQueueDepth;
    lWasProcessing := lTopic.IsProcessing;
  end;

  if (lTopic <> nil) and lTopic.HasCoalesce then
  begin
    lAccepted := TryPost<t>(aEvent);
    if not lAccepted then
      Exit(TmaxPostResult.Dropped);
    Exit(TmaxPostResult.Coalesced);
  end;

  lAccepted := TryPost<t>(aEvent);
  if not lAccepted then
    Exit(TmaxPostResult.Dropped);
  if (lQueueDepth > 0) or lWasProcessing then
    Exit(TmaxPostResult.Queued);
  Result := TmaxPostResult.DispatchedInline;
end;

function TmaxBus.PostDelayed<t>(const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;
var
  lEvent: t;
begin
  lEvent := aEvent;
  Result := ScheduleDelayedPost(
    procedure
    begin
      Post<t>(lEvent);
    end,
    aDelayMs);
end;

procedure TmaxBus.PostMany<t>(const aEvents: array of t);
var
  lIdx: integer;
  lErrors: TmaxExceptionList;
  lDetails: TArray<TmaxDispatchErrorDetail>;
begin
  lErrors := nil;
  lDetails := nil;
  for lIdx := Low(aEvents) to High(aEvents) do
    try
      Post<t>(aEvents[lIdx]);
    except
      on e: EmaxDispatchError do
      begin
        MergeDispatchError(e, lErrors, lDetails);
      end;
    end;
  if lErrors <> nil then
    raise EmaxDispatchError.Create(lErrors, lDetails);
end;

function TmaxBus.SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery): ImaxSubscription;
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lToken: TmaxSubscriptionToken;
  lSend: boolean;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lNameKey := aName;
  lMetric := NamedMetricName(lNameKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyNames.ContainsKey(lNameKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetNames.TryGetValue(lNameKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lCreated := False;
  TMonitor.Enter(fNamedLock);
  try
    if not fNamed.TryGetValue(lNameKey, lObj) then
    begin
      lTopic := TNamedTopic.Create;
      lTopic.SetMetricName(lMetric);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fNamed.Add(lNameKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := lObj as TNamedTopic;
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fNamedLock);
  end;

  if lCreated then
    PublishMetricNamedTopic(lNameKey, lTopic);

  lToken := lTopic.Add(aHandler, aMode, lState);
  lSend := lTopic.HasCached;
  if lSend then
    lTopic.Enqueue(
      procedure
      begin
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                try
                  aHandler();
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxNamedSubscription.Create(lTopic, lToken, lState);
end;

function TmaxBus.SubscribeNamedWildcard(const aPattern: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery): ImaxSubscription;
var
  lPrefix: TmaxString;
  lToken: TmaxSubscriptionToken;
  lState: ImaxSubscriptionState;
begin
  lPrefix := '';
  if not TryParseWildcardPattern(aPattern, lPrefix) then
    raise EmaxInvalidSubscription.CreateFmt('Invalid wildcard pattern: %s', [aPattern]);
  lToken := AddNamedWildcard(aPattern, lPrefix, aHandler, aMode, lState);
  Result := TmaxNamedWildcardSubscription.Create(Self, lToken, lState);
end;

procedure TmaxBus.PostNamed(const aName: TmaxString);
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lSubs: TArray<TNamedSubscriber>;
  lWildcardSubs: TArray<TNamedWildcardSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  lNameKey := aName;
  lMetric := '';
  lWildcardSubs := SnapshotNamedWildcardMatches(lNameKey);
  lCreated := False;
  lTopic := nil;
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
      lTopic := lObj as TNamedTopic;
  finally
    TMonitor.Exit(fNamedLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyNames.ContainsKey(lNameKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetNames.TryGetValue(lNameKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if (not lSticky) and (Length(lWildcardSubs) = 0) then
      exit;

	    TMonitor.Enter(fNamedLock);
	    try
	      if not fNamed.TryGetValue(lNameKey, lObj) then
	      begin
          if lMetric = '' then
            lMetric := NamedMetricName(lNameKey);
	        lTopic := TNamedTopic.Create;
	        lTopic.SetMetricName(lMetric);
	        if lPreset <> TmaxQueuePreset.Unspecified then
	          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	        if lSticky then
	          lTopic.SetSticky(True);
	        fNamed.Add(lNameKey, lTopic);
	        lCreated := True;
	      end
	      else
        begin
          lTopic := lObj as TNamedTopic;
          if lMetric = '' then
            lMetric := lTopic.MetricName;
        end;
	    finally
	      TMonitor.Exit(fNamedLock);
	    end;

	    if lCreated then
	      PublishMetricNamedTopic(lNameKey, lTopic);
	  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := NamedMetricName(lNameKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lSubs := lTopic.Snapshot;
  lTopic.Cache;
  lTopic.AddPost;
  if (Length(lSubs) = 0) and (Length(lWildcardSubs) = 0) then
    exit;
  lTopic.Enqueue(
    procedure
    var
      lErrs: TmaxExceptionList;
      lErrDetails: TArray<TmaxDispatchErrorDetail>;
      i: Integer;
      lWildIdx: Integer;
      lHandler: TmaxProc;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
      lBox: TInvokeBoxNamed;
    begin
      lErrs := nil;
      lErrDetails := nil;

      for i := 0 to High(lSubs) do
      begin
        lHandler := lSubs[i].Handler;
        lMode := lSubs[i].Mode;
        lToken := lSubs[i].Token;
        lState := lSubs[i].State;

        if (lState <> nil) and not lState.TryEnter then
          continue;

        if not lSubs[i].Target.IsAlive then
        begin
          lTopic.RemoveByToken(lToken);
          if lState <> nil then
            lState.Leave;
          continue;
        end;
        try
          if lMode = Posting then
          begin
            try
              try
                lHandler();
                lTopic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  lTopic.AddException;
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                  begin
                    lTopic.RemoveByToken(lToken);
                    continue;
                  end;
                  raise;
                end;
              end;
            finally
              if lState <> nil then
                lState.Leave;
            end;
          end
          else
          begin
            lBox := TInvokeBoxNamed.Create;
            lBox.Topic := lTopic;
            lBox.Handler := lHandler;
            lBox.Token := lToken;
            lBox.State := lState;
            Dispatch(lMetric, lMode, MakeNamedHandlerProc(lBox), nil);
          end;
        except
          on e: EmaxMainThreadRequired do
            raise;
          on e: Exception do
          begin
            AddDispatchError(lMetric, lMode, lToken, i, e, lErrs, lErrDetails);
          end;
        end;
      end;

      for lWildIdx := 0 to High(lWildcardSubs) do
      begin
        lHandler := lWildcardSubs[lWildIdx].Handler;
        lMode := lWildcardSubs[lWildIdx].Mode;
        lToken := lWildcardSubs[lWildIdx].Token;
        lState := lWildcardSubs[lWildIdx].State;

        if (lState <> nil) and not lState.TryEnter then
          continue;

        try
          if lMode = Posting then
          begin
            try
              try
                lHandler();
                lTopic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  lTopic.AddException;
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                  begin
                    RemoveNamedWildcardByToken(lToken);
                    continue;
                  end;
                  raise;
                end;
              end;
            finally
              if lState <> nil then
                lState.Leave;
            end;
          end
          else
          begin
            lBox := TInvokeBoxNamed.Create;
            lBox.Topic := lTopic;
            lBox.Handler := lHandler;
            lBox.Token := lToken;
            lBox.State := lState;
            Dispatch(lMetric, lMode, MakeNamedHandlerProc(lBox), nil);
          end;
        except
          on e: EmaxMainThreadRequired do
            raise;
          on e: Exception do
          begin
            AddDispatchError(lMetric, lMode, lToken, -(lWildIdx + 1), e, lErrs, lErrDetails);
          end;
        end;
      end;

      if lErrs <> nil then
        raise EmaxDispatchError.Create(lErrs, lErrDetails);
    end);
end;

function TmaxBus.TryPostNamed(const aName: TmaxString): boolean;
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lSubs: TArray<TNamedSubscriber>;
  lWildcardSubs: TArray<TNamedWildcardSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lCreated: boolean;
begin
  Result := True;
  lNameKey := aName;
  lMetric := '';
  lWildcardSubs := SnapshotNamedWildcardMatches(lNameKey);
  lCreated := False;
  lTopic := nil;
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
      lTopic := lObj as TNamedTopic;
  finally
    TMonitor.Exit(fNamedLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyNames.ContainsKey(lNameKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetNames.TryGetValue(lNameKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if (not lSticky) and (Length(lWildcardSubs) = 0) then
      exit;

	    TMonitor.Enter(fNamedLock);
	    try
	      if not fNamed.TryGetValue(lNameKey, lObj) then
	      begin
          if lMetric = '' then
            lMetric := NamedMetricName(lNameKey);
	        lTopic := TNamedTopic.Create;
	        lTopic.SetMetricName(lMetric);
	        if lPreset <> TmaxQueuePreset.Unspecified then
	          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	        if lSticky then
	          lTopic.SetSticky(True);
	        fNamed.Add(lNameKey, lTopic);
	        lCreated := True;
	      end
	      else
        begin
          lTopic := lObj as TNamedTopic;
          if lMetric = '' then
            lMetric := lTopic.MetricName;
        end;
	    finally
	      TMonitor.Exit(fNamedLock);
	    end;

	    if lCreated then
	      PublishMetricNamedTopic(lNameKey, lTopic);

    if Length(lWildcardSubs) = 0 then
    begin
      lTopic.Cache;
      lTopic.AddPost;
      exit;
    end;
	  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := NamedMetricName(lNameKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lSubs := lTopic.Snapshot;
  lTopic.Cache;
  lTopic.AddPost;
  if (Length(lSubs) = 0) and (Length(lWildcardSubs) = 0) then
    exit;
  Result := lTopic.Enqueue(
    procedure
    var
      lErrs: TmaxExceptionList;
      lErrDetails: TArray<TmaxDispatchErrorDetail>;
      i: Integer;
      lWildIdx: Integer;
      lHandler: TmaxProc;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
      lBox: TInvokeBoxNamed;
    begin
      lErrs := nil;
      lErrDetails := nil;

      for i := 0 to High(lSubs) do
      begin
        lHandler := lSubs[i].Handler;
        lMode := lSubs[i].Mode;
        lToken := lSubs[i].Token;
        lState := lSubs[i].State;

        if (lState <> nil) and not lState.TryEnter then
          continue;

        if not lSubs[i].Target.IsAlive then
        begin
          lTopic.RemoveByToken(lToken);
          if lState <> nil then
            lState.Leave;
          continue;
        end;
        try
          if lMode = Posting then
          begin
            try
              try
                lHandler();
                lTopic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  lTopic.AddException;
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                  begin
                    lTopic.RemoveByToken(lToken);
                    continue;
                  end;
                  raise;
                end;
              end;
            finally
              if lState <> nil then
                lState.Leave;
            end;
          end
          else
          begin
            lBox := TInvokeBoxNamed.Create;
            lBox.Topic := lTopic;
            lBox.Handler := lHandler;
            lBox.Token := lToken;
            lBox.State := lState;
            Dispatch(lMetric, lMode, MakeNamedHandlerProc(lBox), nil);
          end;
        except
          on e: EmaxMainThreadRequired do
            raise;
          on e: Exception do
          begin
            AddDispatchError(lMetric, lMode, lToken, i, e, lErrs, lErrDetails);
          end;
        end;
      end;

      for lWildIdx := 0 to High(lWildcardSubs) do
      begin
        lHandler := lWildcardSubs[lWildIdx].Handler;
        lMode := lWildcardSubs[lWildIdx].Mode;
        lToken := lWildcardSubs[lWildIdx].Token;
        lState := lWildcardSubs[lWildIdx].State;

        if (lState <> nil) and not lState.TryEnter then
          continue;

        try
          if lMode = Posting then
          begin
            try
              try
                lHandler();
                lTopic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  lTopic.AddException;
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                  begin
                    RemoveNamedWildcardByToken(lToken);
                    continue;
                  end;
                  raise;
                end;
              end;
            finally
              if lState <> nil then
                lState.Leave;
            end;
          end
          else
          begin
            lBox := TInvokeBoxNamed.Create;
            lBox.Topic := lTopic;
            lBox.Handler := lHandler;
            lBox.Token := lToken;
            lBox.State := lState;
            Dispatch(lMetric, lMode, MakeNamedHandlerProc(lBox), nil);
          end;
        except
          on e: EmaxMainThreadRequired do
            raise;
          on e: Exception do
          begin
            AddDispatchError(lMetric, lMode, lToken, -(lWildIdx + 1), e, lErrs, lErrDetails);
          end;
        end;
      end;

      if lErrs <> nil then
        raise EmaxDispatchError.Create(lErrs, lErrDetails);
    end);
end;

function TmaxBus.PostResultNamed(const aName: TmaxString): TmaxPostResult;
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lWildcardSubs: TArray<TNamedWildcardSubscriber>;
  lNameKey: TmaxString;
  lSticky: boolean;
  lAccepted: boolean;
  lQueueDepth: UInt32;
  lWasProcessing: boolean;
begin
  lNameKey := aName;
  lWildcardSubs := SnapshotNamedWildcardMatches(lNameKey);
  lTopic := nil;
  lQueueDepth := 0;
  lWasProcessing := False;

  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
      lTopic := lObj as TNamedTopic;
  finally
    TMonitor.Exit(fNamedLock);
  end;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyNames.ContainsKey(lNameKey);
    finally
      fConfigLock.EndWrite;
    end;
    if (not lSticky) and (Length(lWildcardSubs) = 0) then
      Exit(TmaxPostResult.NoTopic);
  end
  else
  begin
    lQueueDepth := lTopic.GetStats.CurrentQueueDepth;
    lWasProcessing := lTopic.IsProcessing;
  end;

  lAccepted := TryPostNamed(aName);
  if not lAccepted then
    Exit(TmaxPostResult.Dropped);
  if (lQueueDepth > 0) or lWasProcessing then
    Exit(TmaxPostResult.Queued);
  Result := TmaxPostResult.DispatchedInline;
end;

function TmaxBus.PostDelayedNamed(const aName: TmaxString; aDelayMs: Cardinal): ImaxDelayedPost;
var
  lName: TmaxString;
begin
  lName := aName;
  Result := ScheduleDelayedPost(
    procedure
    begin
      PostNamed(lName);
    end,
    aDelayMs);
end;

function TmaxBus.SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lKey: PTypeInfo;
  lSend: boolean;
  lLast: t;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
	  lBase: TmaxTopicBase;
	  lSticky: boolean;
		  lPreset: TmaxQueuePreset;
		  lBasePolicy: TmaxQueuePolicy;
		  lHasBasePolicy: boolean;
		  lCreated: boolean;
		begin
  lKey := TypeInfo(t);
  lNameKey := aName;
  lMetric := NamedTypeMetricName(lNameKey, lKey);
	  fConfigLock.BeginWrite;
	  try
	    lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
	    lPreset := TmaxQueuePreset.Unspecified;
	    fPresetNames.TryGetValue(lNameKey, lPreset);
	  finally
	    fConfigLock.EndWrite;
	  end;

  lHasBasePolicy := False;
  lBasePolicy := Default(TmaxQueuePolicy);
	  TMonitor.Enter(fNamedLock);
	  try
	    if fNamed.TryGetValue(lNameKey, lBase) then
	    begin
	      if lBase.HasExplicitPolicy then
	      begin
	        lBasePolicy := lBase.GetPolicy;
	        lHasBasePolicy := True;
	      end;
	    end;
	  finally
	    TMonitor.Exit(fNamedLock);
	  end;

  lCreated := False;
  TMonitor.Enter(fNamedTypedLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, lTypeDict);
    end;
	    if not lTypeDict.TryGetValue(lKey, lObj) then
	    begin
	      lTopic := TTypedTopic<t>.Create;
	      lTopic.SetMetricName(lMetric);
	      if lHasBasePolicy then
	        lTopic.SetPolicy(lBasePolicy)
	      else if lPreset <> TmaxQueuePreset.Unspecified then
	        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	      if lSticky then
	        lTopic.SetSticky(True);
	      lTypeDict.Add(lKey, lTopic);
	      lCreated := True;
	    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  if lCreated then
    PublishMetricNamedTypedTopic(lNameKey, lKey, lTopic);

  lToken := lTopic.Add(aHandler, aMode, lState);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          try
            Dispatch(lMetric, aMode,
              procedure
              begin
                try
                  try
                    aHandler(lVal);
                    lTopic.AddDelivered(1);
                  except
                    on e: Exception do
                    begin
                      if (e is EAccessViolation) or (e is EInvalidPointer) then
                      begin
                        lTopic.RemoveByToken(lToken);
                        lTopic.AddException;
                        exit;
                      end;
                      raise;
                    end;
                  end;
                finally
                  if lState <> nil then
                    lState.Leave;
                end;
              end,
              procedure
              begin
                lTopic.AddException;
              end);
          except
            on e: Exception do ; // swallow; metrics already updated via aOnException
          end;
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

function TmaxBus.SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lKey: PTypeInfo;
  lSend: boolean;
  lLast: t;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
  lBase: TmaxTopicBase;
  lTarget: TObject;
	  lWrapper: TmaxProcOf<t>;
		  lSticky: boolean;
		  lPreset: TmaxQueuePreset;
		  lBasePolicy: TmaxQueuePolicy;
		  lHasBasePolicy: boolean;
		  lCreated: boolean;
		begin
  lKey := TypeInfo(t);
  lNameKey := aName;
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

	  fConfigLock.BeginWrite;
	  try
	    lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
	    lPreset := TmaxQueuePreset.Unspecified;
	    fPresetNames.TryGetValue(lNameKey, lPreset);
	  finally
	    fConfigLock.EndWrite;
	  end;

  lHasBasePolicy := False;
  lBasePolicy := Default(TmaxQueuePolicy);
	  TMonitor.Enter(fNamedLock);
	  try
	    if fNamed.TryGetValue(lNameKey, lBase) then
	    begin
	      if lBase.HasExplicitPolicy then
	      begin
	        lBasePolicy := lBase.GetPolicy;
	        lHasBasePolicy := True;
	      end;
	    end;
	  finally
	    TMonitor.Exit(fNamedLock);
	  end;

  lCreated := False;
  TMonitor.Enter(fNamedTypedLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, lTypeDict);
    end;
	    if not lTypeDict.TryGetValue(lKey, lObj) then
	    begin
	      lTopic := TTypedTopic<t>.Create;
	      lTopic.SetMetricName(lMetric);
	      if lHasBasePolicy then
	        lTopic.SetPolicy(lBasePolicy)
	      else if lPreset <> TmaxQueuePreset.Unspecified then
	        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	      if lSticky then
	        lTopic.SetSticky(True);
	      lTypeDict.Add(lKey, lTopic);
	      lCreated := True;
	    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  if lCreated then
    PublishMetricNamedTypedTopic(lNameKey, lKey, lTopic);

  lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                try
                  aHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.PostNamedOf<t>(const aName: TmaxString; const aEvent: t);
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lBase: TmaxTopicBase;
  lKey: PTypeInfo;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lBasePolicy: TmaxQueuePolicy;
  lHasBasePolicy: boolean;
  lCreated: boolean;
begin
  lCreated := False;

  lKey := TypeInfo(t);
  lNameKey := aName;
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeNamedTyped(lNameKey, lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetNames.TryGetValue(lNameKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lHasBasePolicy := False;
  lBasePolicy := Default(TmaxQueuePolicy);
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lBase) then
    begin
      if lBase.HasExplicitPolicy then
      begin
        lBasePolicy := lBase.GetPolicy;
        lHasBasePolicy := True;
      end;
    end;
  finally
    TMonitor.Exit(fNamedLock);
  end;

  lTopic := nil;
  TMonitor.Enter(fNamedTypedLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if not lSticky then
      begin
        if Length(lAutoSubs) <> 0 then
        begin
          if lMetric = '' then
            lMetric := NamedTypeMetricName(lNameKey, lKey);
          DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
        end;
        exit;
      end;
      lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, lTypeDict);
    end;
    if lTypeDict.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj)
    else
    begin
      if not lSticky then
      begin
        if Length(lAutoSubs) <> 0 then
        begin
          if lMetric = '' then
            lMetric := NamedTypeMetricName(lNameKey, lKey);
          DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
        end;
        exit;
      end;
      if lMetric = '' then
        lMetric := NamedTypeMetricName(lNameKey, lKey);
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lHasBasePolicy then
        lTopic.SetPolicy(lBasePolicy)
      else if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
      lCreated := True;
    end;
    if lMetric = '' then
      lMetric := lTopic.MetricName;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  if lCreated then
    PublishMetricNamedTypedTopic(lNameKey, lKey, lTopic);
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := NamedTypeMetricName(lNameKey, lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;
  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    lTopic.Enqueue(
      procedure
      begin
        DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      end);
  end;
  if Length(lAutoSubs) <> 0 then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
end;

	function TmaxBus.TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lBase: TmaxTopicBase;
  lKey: PTypeInfo;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lBasePolicy: TmaxQueuePolicy;
  lHasBasePolicy: boolean;
  lCreated: boolean;
begin
  Result := True;
  lKey := TypeInfo(t);
  lNameKey := aName;
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeNamedTyped(lNameKey, lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetNames.TryGetValue(lNameKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lHasBasePolicy := False;
  lBasePolicy := Default(TmaxQueuePolicy);
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lBase) then
    begin
      if lBase.HasExplicitPolicy then
      begin
        lBasePolicy := lBase.GetPolicy;
        lHasBasePolicy := True;
      end;
    end;
  finally
    TMonitor.Exit(fNamedLock);
  end;

  lCreated := False;
  lTopic := nil;
  TMonitor.Enter(fNamedTypedLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if not lSticky then
      begin
        if Length(lAutoSubs) <> 0 then
        begin
          if lMetric = '' then
            lMetric := NamedTypeMetricName(lNameKey, lKey);
          DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
        end;
        exit;
      end;
      lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, lTypeDict);
    end;
    if lTypeDict.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj)
    else
    begin
      if not lSticky then
      begin
        if Length(lAutoSubs) <> 0 then
        begin
          if lMetric = '' then
            lMetric := NamedTypeMetricName(lNameKey, lKey);
          DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
        end;
        exit;
      end;
      if lMetric = '' then
        lMetric := NamedTypeMetricName(lNameKey, lKey);
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lHasBasePolicy then
        lTopic.SetPolicy(lBasePolicy)
      else if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
      lCreated := True;
    end;
    if lMetric = '' then
      lMetric := lTopic.MetricName;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  if lCreated then
  begin
    PublishMetricNamedTypedTopic(lNameKey, lKey, lTopic);
    lTopic.Cache(aEvent);
    lTopic.AddPost;
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    exit;
  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := NamedTypeMetricName(lNameKey, lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;
  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      Result := True;
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
      Result := True
    else
      Result := lTopic.Enqueue(
        procedure
        begin
          DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
        end);
  end;
  if Result and (Length(lAutoSubs) <> 0) then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
end;

function TmaxBus.PostResultNamedOf<t>(const aName: TmaxString; const aEvent: t): TmaxPostResult;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lNameKey: TmaxString;
  lKey: PTypeInfo;
  lSticky: boolean;
  lAccepted: boolean;
  lQueueDepth: UInt32;
  lWasProcessing: boolean;
begin
  lNameKey := aName;
  lKey := TypeInfo(t);
  lTopic := nil;
  lQueueDepth := 0;
  lWasProcessing := False;

  TMonitor.Enter(fNamedTypedLock);
  try
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) and lTypeDict.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
      Exit(TmaxPostResult.NoTopic);
  end
  else
  begin
    lQueueDepth := lTopic.GetStats.CurrentQueueDepth;
    lWasProcessing := lTopic.IsProcessing;
  end;

  if (lTopic <> nil) and lTopic.HasCoalesce then
  begin
    lAccepted := TryPostNamedOf<t>(aName, aEvent);
    if not lAccepted then
      Exit(TmaxPostResult.Dropped);
    Exit(TmaxPostResult.Coalesced);
  end;

  lAccepted := TryPostNamedOf<t>(aName, aEvent);
  if not lAccepted then
    Exit(TmaxPostResult.Dropped);
  if (lQueueDepth > 0) or lWasProcessing then
    Exit(TmaxPostResult.Queued);
  Result := TmaxPostResult.DispatchedInline;
end;

function TmaxBus.PostDelayedNamedOf<t>(const aName: TmaxString; const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;
var
  lName: TmaxString;
  lEvent: t;
begin
  lName := aName;
  lEvent := aEvent;
  Result := ScheduleDelayedPost(
    procedure
    begin
      PostNamedOf<t>(lName, lEvent);
    end,
    aDelayMs);
end;

procedure TmaxBus.PostManyNamedOf<t>(const aName: TmaxString; const aEvents: array of t);
var
  lIdx: integer;
  lErrors: TmaxExceptionList;
  lDetails: TArray<TmaxDispatchErrorDetail>;
begin
  lErrors := nil;
  lDetails := nil;
  for lIdx := Low(aEvents) to High(aEvents) do
    try
      PostNamedOf<t>(aName, aEvents[lIdx]);
    except
      on e: EmaxDispatchError do
      begin
        MergeDispatchError(e, lErrors, lDetails);
      end;
    end;
  if lErrors <> nil then
    raise EmaxDispatchError.Create(lErrors, lDetails);
end;

function TmaxBus.SubscribeGuidOf<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lSend: boolean;
  lLast: t;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lTypeKey: PTypeInfo;
  lCreated: boolean;
begin
  lTypeKey := TypeInfo(t);
  lKey := GetTypeData(lTypeKey)^.Guid;
  lMetric := GuidMetricName(lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lTypeKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetGuids.TryGetValue(lKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lCreated := False;
  TMonitor.Enter(fGuidLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fGuid.Add(lKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fGuidLock);
  end;

  if lCreated then
    PublishMetricGuidTopic(lKey, lTopic);

  lToken := lTopic.Add(aHandler, aMode, lState);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                try
                  aHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

function TmaxBus.SubscribeGuidOf<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lToken: TmaxSubscriptionToken;
  lSend: boolean;
  lLast: t;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
  lTarget: TObject;
  lWrapper: TmaxProcOf<t>;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lTypeKey: PTypeInfo;
  lCreated: boolean;
begin
  lTypeKey := TypeInfo(t);
  lKey := GetTypeData(lTypeKey)^.Guid;
  lMetric := GuidMetricName(lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lTypeKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetGuids.TryGetValue(lKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lCreated := False;
  TMonitor.Enter(fGuidLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fGuid.Add(lKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fGuidLock);
  end;

  if lCreated then
    PublishMetricGuidTopic(lKey, lTopic);

  lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
  lSend := lTopic.TryGetCached(lLast);
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                try
                  aHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                    begin
                      lTopic.RemoveByToken(lToken);
                      lTopic.AddException;
                      exit;
                    end;
                    raise;
                  end;
                end;
              finally
                if lState <> nil then
                  lState.Leave;
              end;
            end,
            procedure
            begin
              lTopic.AddException;
            end);
        except
          on e: Exception do ; // swallow; metrics already updated via aOnException
        end;
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.PostGuidOf<t>(const aEvent: t);
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lTypeKey: PTypeInfo;
  lCreated: boolean;
begin
  lCreated := False;

  lTypeKey := TypeInfo(t);
  lKey := GetTypeData(lTypeKey)^.Guid;
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeGuid(lKey);
  lTopic := nil;
  TMonitor.Enter(fGuidLock);
  try
    if fGuid.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fGuidLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lTypeKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetGuids.TryGetValue(lKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
    begin
      if Length(lAutoSubs) <> 0 then
      begin
        if lMetric = '' then
          lMetric := GuidMetricName(lKey);
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      end;
      exit;
    end;

	    TMonitor.Enter(fGuidLock);
	    try
	      if not fGuid.TryGetValue(lKey, lObj) then
	      begin
          if lMetric = '' then
            lMetric := GuidMetricName(lKey);
	        lTopic := TTypedTopic<t>.Create;
	        lTopic.SetMetricName(lMetric);
	        if lPreset <> TmaxQueuePreset.Unspecified then
	          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	        lTopic.SetSticky(True);
	        fGuid.Add(lKey, lTopic);
	        lCreated := True;
	      end
	      else
        begin
	        lTopic := TTypedTopic<t>(lObj);
          if lMetric = '' then
            lMetric := lTopic.MetricName;
        end;
	    finally
	      TMonitor.Exit(fGuidLock);
	    end;

	    if lCreated then
	      PublishMetricGuidTopic(lKey, lTopic);
	  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := GuidMetricName(lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;
  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    lTopic.Enqueue(
      procedure
      begin
        DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      end);
  end;
  if Length(lAutoSubs) <> 0 then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
		end;

function TmaxBus.TryPostGuidOf<t>(const aEvent: t): boolean;
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lAutoSubs: TArray<TmaxAutoBridgeSnapshot>;
  lNeedSchedule: boolean;
  lHasCoalesce: boolean;
  lKeyStr: TmaxString;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lTypeKey: PTypeInfo;
  lCreated: boolean;
begin
  lCreated := False;

  Result := True;
  lTypeKey := TypeInfo(t);
  lKey := GetTypeData(lTypeKey)^.Guid;
  lMetric := '';
  lAutoSubs := SnapshotAutoBridgeGuid(lKey);

  lTopic := nil;
  TMonitor.Enter(fGuidLock);
  try
    if fGuid.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fGuidLock);
  end;
  if lTopic <> nil then
    lMetric := lTopic.MetricName;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lTypeKey);
      lPreset := TmaxQueuePreset.Unspecified;
      fPresetGuids.TryGetValue(lKey, lPreset);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
    begin
      if Length(lAutoSubs) <> 0 then
      begin
        if lMetric = '' then
          lMetric := GuidMetricName(lKey);
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      end;
      exit;
    end;

	    TMonitor.Enter(fGuidLock);
	    try
	      if not fGuid.TryGetValue(lKey, lObj) then
	      begin
          if lMetric = '' then
            lMetric := GuidMetricName(lKey);
	        lTopic := TTypedTopic<t>.Create;
	        lTopic.SetMetricName(lMetric);
	        if lPreset <> TmaxQueuePreset.Unspecified then
	          lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
	        lTopic.SetSticky(True);
	        fGuid.Add(lKey, lTopic);
	        lCreated := True;
	      end
	      else
        begin
	        lTopic := TTypedTopic<t>(lObj);
          if lMetric = '' then
            lMetric := lTopic.MetricName;
        end;
	    finally
	      TMonitor.Exit(fGuidLock);
	    end;

	    if lCreated then
	      PublishMetricGuidTopic(lKey, lTopic);

	    lTopic.Cache(aEvent);
      lTopic.AddPost;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
	    exit;
	  end;
  if lMetric = '' then
  begin
    lMetric := lTopic.MetricName;
    if lMetric = '' then
    begin
      lMetric := GuidMetricName(lKey);
      lTopic.SetMetricName(lMetric);
    end;
  end;

  lTopic.Cache(aEvent);
  lHasCoalesce := lTopic.HasCoalesce;
  if lHasCoalesce then
  begin
    lSubs := lTopic.Snapshot;
    lKeyStr := lTopic.CoalesceKey(aEvent);
    lNeedSchedule := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    lTopic.AddPost;
    if Length(lSubs) = 0 then
    begin
      lTopic.ClearPending;
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    if not lNeedSchedule then
    begin
      if Length(lAutoSubs) <> 0 then
        DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
      Exit;
    end;
    ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs);
    if Length(lAutoSubs) <> 0 then
      DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
    Exit;
  end;

  lTopic.AddPost;
  if lTopic.SnapshotAndTryBeginDirectDispatch(lSubs) then
  begin
    try
      DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
      Result := True;
    finally
      lTopic.EndDirectDispatch;
    end;
  end
  else
  begin
    if Length(lSubs) = 0 then
      Result := True
    else
      Result := lTopic.Enqueue(
        procedure
        begin
          DispatchTypedSubscribers<t>(lMetric, lTopic, lSubs, aEvent, True);
        end);
  end;
  if Result and (Length(lAutoSubs) <> 0) then
    DispatchAutoBridge<t>(lMetric, lAutoSubs, aEvent);
		end;

function TmaxBus.PostResultGuidOf<t>(const aEvent: t): TmaxPostResult;
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lTypeKey: PTypeInfo;
  lSticky: boolean;
  lAccepted: boolean;
  lQueueDepth: UInt32;
  lWasProcessing: boolean;
begin
  lTypeKey := TypeInfo(t);
  lKey := GetTypeData(lTypeKey)^.Guid;
  lTopic := nil;
  lQueueDepth := 0;
  lWasProcessing := False;

  TMonitor.Enter(fGuidLock);
  try
    if fGuid.TryGetValue(lKey, lObj) then
      lTopic := TTypedTopic<t>(lObj);
  finally
    TMonitor.Exit(fGuidLock);
  end;

  if lTopic = nil then
  begin
    fConfigLock.BeginWrite;
    try
      lSticky := fStickyTypes.ContainsKey(lTypeKey);
    finally
      fConfigLock.EndWrite;
    end;
    if not lSticky then
      Exit(TmaxPostResult.NoTopic);
  end
  else
  begin
    lQueueDepth := lTopic.GetStats.CurrentQueueDepth;
    lWasProcessing := lTopic.IsProcessing;
  end;

  if (lTopic <> nil) and lTopic.HasCoalesce then
  begin
    lAccepted := TryPostGuidOf<t>(aEvent);
    if not lAccepted then
      Exit(TmaxPostResult.Dropped);
    Exit(TmaxPostResult.Coalesced);
  end;

  lAccepted := TryPostGuidOf<t>(aEvent);
  if not lAccepted then
    Exit(TmaxPostResult.Dropped);
  if (lQueueDepth > 0) or lWasProcessing then
    Exit(TmaxPostResult.Queued);
  Result := TmaxPostResult.DispatchedInline;
end;

function TmaxBus.PostDelayedGuidOf<t>(const aEvent: t; aDelayMs: Cardinal): ImaxDelayedPost;
var
  lEvent: t;
begin
  lEvent := aEvent;
  Result := ScheduleDelayedPost(
    procedure
    begin
      PostGuidOf<t>(lEvent);
    end,
    aDelayMs);
end;

procedure TmaxBus.PostManyGuidOf<t>(const aEvents: array of t);
var
  lIdx: integer;
  lErrors: TmaxExceptionList;
  lDetails: TArray<TmaxDispatchErrorDetail>;
begin
  lErrors := nil;
  lDetails := nil;
  for lIdx := Low(aEvents) to High(aEvents) do
    try
      PostGuidOf<t>(aEvents[lIdx]);
    except
      on e: EmaxDispatchError do
      begin
        MergeDispatchError(e, lErrors, lDetails);
      end;
    end;
  if lErrors <> nil then
    raise EmaxDispatchError.Create(lErrors, lDetails);
end;

procedure TmaxBus.EnableSticky<t>(aEnable: boolean);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lKvName: TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lGuid: TGuid;
  lMetric: TmaxString;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  fConfigLock.BeginWrite;
  try
    if aEnable then
      fStickyTypes.AddOrSetValue(lKey, True)
    else
      fStickyTypes.Remove(lKey);
  finally
    fConfigLock.EndWrite;
  end;

  TMonitor.Enter(fTypedLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
    begin
      lObj.SetMetricName(lMetric);
      lObj.SetSticky(aEnable);
    end;
  finally
    TMonitor.Exit(fTypedLock);
  end;

  TMonitor.Enter(fNamedTypedLock);
  try
    for lKvName in fNamedTyped do
      if lKvName.Value.TryGetValue(lKey, lObj) then
      begin
        lObj.SetMetricName(NamedTypeMetricName(lKvName.Key, lKey));
        lObj.SetSticky(aEnable);
      end;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;

  lGuid := GetTypeData(lKey)^.Guid;
  TMonitor.Enter(fGuidLock);
  try
    if fGuid.TryGetValue(lGuid, lObj) then
    begin
      lObj.SetMetricName(GuidMetricName(lGuid));
      lObj.SetSticky(aEnable);
    end;
  finally
    TMonitor.Exit(fGuidLock);
  end;
end;

procedure TmaxBus.EnableStickyNamed(const aName: string; aEnable: boolean);
var
  lObj: TmaxTopicBase;
  lTypeDict: TmaxTypeTopicDict;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  lNameKey := aName;
  lMetric := NamedMetricName(lNameKey);
  fConfigLock.BeginWrite;
  try
    if aEnable then
      fStickyNames.AddOrSetValue(lNameKey, True)
    else
      fStickyNames.Remove(lNameKey);
  finally
    fConfigLock.EndWrite;
  end;

  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
    begin
      lObj.SetMetricName(lMetric);
      lObj.SetSticky(aEnable);
    end;
  finally
    TMonitor.Exit(fNamedLock);
  end;

  TMonitor.Enter(fNamedTypedLock);
  try
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
      for lKvInner in lTypeDict do
      begin
        lKvInner.Value.SetMetricName(NamedTypeMetricName(lNameKey, lKvInner.Key));
        lKvInner.Value.SetSticky(aEnable);
      end;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;
end;

procedure TmaxBus.EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetTypes.TryGetValue(lKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  TMonitor.Enter(fTypedLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fTypedLock);
  end;
  PublishMetricTypedTopic(lKey, lTopic);
  lTopic.SetCoalesce(aKeyOf, aWindowUs);
end;

procedure TmaxBus.EnableCoalesceNamedOf<t>(const aName: string; const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lBase: TmaxTopicBase;
  lKey: PTypeInfo;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lBasePolicy: TmaxQueuePolicy;
  lHasBasePolicy: boolean;
begin
  lKey := TypeInfo(t);
  lNameKey := aName;
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetNames.TryGetValue(lNameKey, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  lHasBasePolicy := False;
  lBasePolicy := Default(TmaxQueuePolicy);
  TMonitor.Enter(fNamedLock);
  try
    if fNamed.TryGetValue(lNameKey, lBase) then
    begin
      if lBase.HasExplicitPolicy then
      begin
        lBasePolicy := lBase.GetPolicy;
        lHasBasePolicy := True;
      end;
    end;
  finally
    TMonitor.Exit(fNamedLock);
  end;

  TMonitor.Enter(fNamedTypedLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, lTypeDict);
    end;
    if not lTypeDict.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lHasBasePolicy then
        lTopic.SetPolicy(lBasePolicy)
      else if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;
  PublishMetricNamedTypedTopic(lNameKey, lKey, lTopic);
  lTopic.SetCoalesce(aKeyOf, aWindowUs);
end;

procedure TmaxBus.EnableCoalesceGuidOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
var
  lGuid: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
  lSticky: boolean;
  lPreset: TmaxQueuePreset;
  lTypeKey: PTypeInfo;
begin
  lTypeKey := TypeInfo(t);
  lGuid := GetTypeData(lTypeKey)^.Guid;
  lMetric := GuidMetricName(lGuid);
  fConfigLock.BeginWrite;
  try
    lSticky := fStickyTypes.ContainsKey(lTypeKey);
    lPreset := TmaxQueuePreset.Unspecified;
    fPresetGuids.TryGetValue(lGuid, lPreset);
  finally
    fConfigLock.EndWrite;
  end;

  TMonitor.Enter(fGuidLock);
  try
    if not fGuid.TryGetValue(lGuid, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if lPreset <> TmaxQueuePreset.Unspecified then
        lTopic.SetPolicyImplicit(PolicyForPreset(lPreset));
      if lSticky then
        lTopic.SetSticky(True);
      fGuid.Add(lGuid, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fGuidLock);
  end;
  PublishMetricGuidTopic(lGuid, lTopic);
  lTopic.SetCoalesce(aKeyOf, aWindowUs);
end;

procedure TmaxBus.UnsubscribeAllFor(const aTarget: TObject);
var
  lKvTyped: TPair<PTypeInfo, TmaxTopicBase>;
  lKvNamed: TPair<TmaxString, TmaxTopicBase>;
  lKvName:  TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lKvGuid:  TPair<TGuid, TmaxTopicBase>;
  lTypedTopics: TArray<TmaxTopicBase>;
  lNamedTopics: TArray<TmaxTopicBase>;
  lNamedTypedTopics: TArray<TmaxTopicBase>;
  lGuidTopics: TArray<TmaxTopicBase>;
  lTopic: TmaxTopicBase;
  lIdx: integer;
  lCount: integer;
begin
  if aTarget = nil then
    exit;

  TMonitor.Enter(fTypedLock);
  try
    SetLength(lTypedTopics, fTyped.Count);
    lIdx := 0;
    for lKvTyped in fTyped do
    begin
      lTypedTopics[lIdx] := lKvTyped.Value;
      Inc(lIdx);
    end;
  finally
    TMonitor.Exit(fTypedLock);
  end;
  for lTopic in lTypedTopics do
    lTopic.RemoveByTarget(aTarget);

  TMonitor.Enter(fNamedLock);
  try
    SetLength(lNamedTopics, fNamed.Count);
    lIdx := 0;
    for lKvNamed in fNamed do
    begin
      lNamedTopics[lIdx] := lKvNamed.Value;
      Inc(lIdx);
    end;
  finally
    TMonitor.Exit(fNamedLock);
  end;
  for lTopic in lNamedTopics do
    lTopic.RemoveByTarget(aTarget);

  TMonitor.Enter(fNamedTypedLock);
  try
    lCount := 0;
    for lKvName in fNamedTyped do
      Inc(lCount, lKvName.Value.Count);
    SetLength(lNamedTypedTopics, lCount);
    lIdx := 0;
    for lKvName in fNamedTyped do
      for lKvInner in lKvName.Value do
      begin
        lNamedTypedTopics[lIdx] := lKvInner.Value;
        Inc(lIdx);
      end;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;
  for lTopic in lNamedTypedTopics do
    lTopic.RemoveByTarget(aTarget);

  TMonitor.Enter(fGuidLock);
  try
    SetLength(lGuidTopics, fGuid.Count);
    lIdx := 0;
    for lKvGuid in fGuid do
    begin
      lGuidTopics[lIdx] := lKvGuid.Value;
      Inc(lIdx);
    end;
  finally
    TMonitor.Exit(fGuidLock);
  end;
  for lTopic in lGuidTopics do
    lTopic.RemoveByTarget(aTarget);
  AutoUnsubscribeInstance(aTarget);
end;

procedure TmaxBus.Clear;
var
  lAutoKeys: TArray<TObject>;
  lKey: TObject;
var
  lStickyTypes: TmaxBoolDictOfTypeInfo;
  lStickyNames: TmaxBoolDictOfString;
  lPresetTypes: TmaxPresetDictOfTypeInfo;
  lPresetNames: TmaxPresetDictOfString;
  lPresetGuids: TmaxPresetDictOfGuid;
  lStickyGuids: TDictionary<TGuid, boolean>;
  lKvTyped: TPair<PTypeInfo, TmaxTopicBase>;
  lKvNamed: TPair<TmaxString, TmaxTopicBase>;
  lKvName: TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lKvGuid: TPair<TGuid, TmaxTopicBase>;
  lKvStickyType: TPair<PTypeInfo, boolean>;
  lKvStickyName: TPair<TmaxString, boolean>;
  lKvPresetType: TPair<PTypeInfo, TmaxQueuePreset>;
  lKvPresetName: TPair<TmaxString, TmaxQueuePreset>;
  lKvPresetGuid: TPair<TGuid, TmaxQueuePreset>;
  lPreset: TmaxQueuePreset;
  lIdx: integer;
begin
  TInterlocked.Increment(fDelayedPostEpoch);
  lAutoKeys := nil;
  TMonitor.Enter(fAutoSubsLock);
  try
    lAutoKeys := fAutoSubs.Keys.ToArray;
  finally
    TMonitor.Exit(fAutoSubsLock);
  end;
  for lKey in lAutoKeys do
    AutoUnsubscribeInstance(lKey);

  lStickyTypes := nil;
  lStickyNames := nil;
  lPresetTypes := nil;
  lPresetNames := nil;
  lPresetGuids := nil;
  lStickyGuids := nil;
  try
    lStickyTypes := TmaxBoolDictOfTypeInfo.Create;
    lStickyNames := TmaxBoolDictOfString.Create;
    lPresetTypes := TmaxPresetDictOfTypeInfo.Create;
    lPresetNames := TmaxPresetDictOfString.Create;
    lPresetGuids := TmaxPresetDictOfGuid.Create;
    lStickyGuids := TDictionary<TGuid, boolean>.Create;

    // Snapshot config without holding it during bus/topic locks (avoid lock-order deadlocks)
    fConfigLock.BeginWrite;
    try
      for lKvStickyType in fStickyTypes do
        lStickyTypes.AddOrSetValue(lKvStickyType.Key, True);
      for lKvStickyName in fStickyNames do
        lStickyNames.AddOrSetValue(lKvStickyName.Key, True);
      for lKvPresetType in fPresetTypes do
        lPresetTypes.AddOrSetValue(lKvPresetType.Key, lKvPresetType.Value);
      for lKvPresetName in fPresetNames do
        lPresetNames.AddOrSetValue(lKvPresetName.Key, lKvPresetName.Value);
      for lKvPresetGuid in fPresetGuids do
        lPresetGuids.AddOrSetValue(lKvPresetGuid.Key, lKvPresetGuid.Value);
    finally
      fConfigLock.EndWrite;
    end;

    for lKvStickyType in lStickyTypes do
      lStickyGuids.AddOrSetValue(GetTypeData(lKvStickyType.Key)^.Guid, True);

    TMonitor.Enter(fTypedLock);
    try
      for lKvTyped in fTyped do
      begin
        lKvTyped.Value.ResetTopic;
        lKvTyped.Value.SetMetricName(TypeMetricName(lKvTyped.Key));
        lPreset := TmaxQueuePreset.Unspecified;
        if lPresetTypes.TryGetValue(lKvTyped.Key, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
          lKvTyped.Value.SetPolicyImplicit(PolicyForPreset(lPreset));
        if lStickyTypes.ContainsKey(lKvTyped.Key) then
          lKvTyped.Value.SetSticky(True);
      end;
    finally
      TMonitor.Exit(fTypedLock);
    end;

    TMonitor.Enter(fNamedLock);
    try
      for lKvNamed in fNamed do
      begin
        lKvNamed.Value.ResetTopic;
        lKvNamed.Value.SetMetricName(NamedMetricName(lKvNamed.Key));
        lPreset := TmaxQueuePreset.Unspecified;
        if lPresetNames.TryGetValue(lKvNamed.Key, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
          lKvNamed.Value.SetPolicyImplicit(PolicyForPreset(lPreset));
        if lStickyNames.ContainsKey(lKvNamed.Key) then
          lKvNamed.Value.SetSticky(True);
      end;
    finally
      TMonitor.Exit(fNamedLock);
    end;

    TMonitor.Enter(fNamedTypedLock);
    try
      for lKvName in fNamedTyped do
      begin
        lPreset := TmaxQueuePreset.Unspecified;
        lPresetNames.TryGetValue(lKvName.Key, lPreset);
        for lKvInner in lKvName.Value do
        begin
          lKvInner.Value.ResetTopic;
          lKvInner.Value.SetMetricName(NamedTypeMetricName(lKvName.Key, lKvInner.Key));
          if (lPreset <> TmaxQueuePreset.Unspecified) then
            lKvInner.Value.SetPolicyImplicit(PolicyForPreset(lPreset));
          if lStickyNames.ContainsKey(lKvName.Key) or lStickyTypes.ContainsKey(lKvInner.Key) then
            lKvInner.Value.SetSticky(True);
        end;
      end;
    finally
      TMonitor.Exit(fNamedTypedLock);
    end;

	    TMonitor.Enter(fGuidLock);
	    try
	      for lKvGuid in fGuid do
      begin
        lKvGuid.Value.ResetTopic;
        lKvGuid.Value.SetMetricName(GuidMetricName(lKvGuid.Key));
        lPreset := TmaxQueuePreset.Unspecified;
        if lPresetGuids.TryGetValue(lKvGuid.Key, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
          lKvGuid.Value.SetPolicyImplicit(PolicyForPreset(lPreset));
        if lStickyGuids.ContainsKey(lKvGuid.Key) then
          lKvGuid.Value.SetSticky(True);
      end;
	    finally
	      TMonitor.Exit(fGuidLock);
	    end;

    TMonitor.Enter(fNamedWildcardLock);
    try
      for lIdx := 0 to High(fNamedWildcardSubs) do
        if Assigned(fNamedWildcardSubs[lIdx].State) then
          fNamedWildcardSubs[lIdx].State.Deactivate;
      if Length(fNamedWildcardSubs) <> 0 then
        Inc(fNamedWildcardVersion);
      SetLength(fNamedWildcardSubs, 0);
      SetLength(fNamedWildcardSnapshot, 0);
      fNamedWildcardSnapshotVersion := 0;
    finally
      TMonitor.Exit(fNamedWildcardLock);
    end;
	  finally
	    lStickyGuids.Free;
	    lPresetGuids.Free;
    lPresetNames.Free;
    lPresetTypes.Free;
    lStickyNames.Free;
    lStickyTypes.Free;
  end;

end;

procedure TmaxBus.SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
  lCreated: boolean;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  lCreated := False;
  TMonitor.Enter(fTypedLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      fTyped.Add(lKey, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fTypedLock);
  end;
  if lCreated then
    PublishMetricTypedTopic(lKey, lTopic);
  lTopic.SetPolicy(aPolicy);
end;

procedure TmaxBus.SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
var
  lTopic: TmaxTopicBase;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lTypeDict: TmaxTypeTopicDict;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lCreated: boolean;
begin
  lNameKey := aName;
  lMetric := NamedMetricName(lNameKey);
  lCreated := False;
  TMonitor.Enter(fNamedLock);
  try
    if not fNamed.TryGetValue(lNameKey, lTopic) then
    begin
      lTopic := TNamedTopic.Create;
      TNamedTopic(lTopic).SetMetricName(lMetric);
      fNamed.Add(lNameKey, lTopic);
      lCreated := True;
    end
    else if lTopic is TNamedTopic then
      TNamedTopic(lTopic).SetMetricName(lMetric);
  finally
    TMonitor.Exit(fNamedLock);
  end;
  if lCreated then
    PublishMetricNamedTopic(lNameKey, lTopic);
  lTopic.SetPolicy(aPolicy);

  TMonitor.Enter(fNamedTypedLock);
  try
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
      for lKvInner in lTypeDict do
      begin
        lKvInner.Value.SetMetricName(NamedTypeMetricName(lNameKey, lKvInner.Key));
        lKvInner.Value.SetPolicy(aPolicy);
      end;
  finally
    TMonitor.Exit(fNamedTypedLock);
  end;
end;

procedure TmaxBus.SetPolicyGuidOf<t>(const aPolicy: TmaxQueuePolicy);
var
  lGuid: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
  lTypeKey: PTypeInfo;
  lCreated: boolean;
begin
  lTypeKey := TypeInfo(t);
  lGuid := GetTypeData(lTypeKey)^.Guid;
  lMetric := GuidMetricName(lGuid);
  lCreated := False;
  TMonitor.Enter(fGuidLock);
  try
    if not fGuid.TryGetValue(lGuid, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      fGuid.Add(lGuid, lTopic);
      lCreated := True;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
  finally
    TMonitor.Exit(fGuidLock);
  end;
  if lCreated then
    PublishMetricGuidTopic(lGuid, lTopic);
  lTopic.SetPolicy(aPolicy);
end;

function TmaxBus.GetPolicyFor<t>: TmaxQueuePolicy;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lFound: boolean;
  lPreset: TmaxQueuePreset;
begin
  lKey := TypeInfo(t);
  TMonitor.Enter(fTypedLock);
  try
    lFound := fTyped.TryGetValue(lKey, lObj);
  finally
    TMonitor.Exit(fTypedLock);
  end;
  if lFound then
    Result := lObj.GetPolicy
  else
  begin
    Result := PolicyForPreset(TmaxQueuePreset.Unspecified);
    fConfigLock.BeginWrite;
    try
      lPreset := TmaxQueuePreset.Unspecified;
      if fPresetTypes.TryGetValue(lKey, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
        Result := PolicyForPreset(lPreset);
    finally
      fConfigLock.EndWrite;
    end;
  end;
end;

function TmaxBus.GetPolicyNamed(const aName: string): TmaxQueuePolicy;
var
  lTopic: TmaxTopicBase;
  lNameKey: TmaxString;
  lFound: boolean;
  lPreset: TmaxQueuePreset;
begin
  lNameKey := aName;
  TMonitor.Enter(fNamedLock);
  try
    lFound := fNamed.TryGetValue(lNameKey, lTopic);
  finally
    TMonitor.Exit(fNamedLock);
  end;
  if lFound then
    Result := lTopic.GetPolicy
  else
  begin
    Result := PolicyForPreset(TmaxQueuePreset.Unspecified);
    fConfigLock.BeginWrite;
    try
      lPreset := TmaxQueuePreset.Unspecified;
      if fPresetNames.TryGetValue(lNameKey, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
        Result := PolicyForPreset(lPreset);
    finally
      fConfigLock.EndWrite;
    end;
  end;
end;

function TmaxBus.GetPolicyGuidOf<t>: TmaxQueuePolicy;
var
  lGuid: TGuid;
  lObj: TmaxTopicBase;
  lFound: boolean;
  lTypeKey: PTypeInfo;
  lPreset: TmaxQueuePreset;
begin
  lTypeKey := TypeInfo(t);
  lGuid := GetTypeData(lTypeKey)^.Guid;
  TMonitor.Enter(fGuidLock);
  try
    lFound := fGuid.TryGetValue(lGuid, lObj);
  finally
    TMonitor.Exit(fGuidLock);
  end;
  if lFound then
    Result := lObj.GetPolicy
  else
  begin
    Result := PolicyForPreset(TmaxQueuePreset.Unspecified);
    fConfigLock.BeginWrite;
    try
      lPreset := TmaxQueuePreset.Unspecified;
      if fPresetGuids.TryGetValue(lGuid, lPreset) and (lPreset <> TmaxQueuePreset.Unspecified) then
        Result := PolicyForPreset(lPreset);
    finally
      fConfigLock.EndWrite;
    end;
  end;
end;

function TmaxBus.GetStatsFor<t>: TmaxTopicStats;
var
  lKey: PTypeInfo;
  lIndex: ImaxMetricsIndex;
begin
  lKey := TypeInfo(t);
  fMetricsLock.BeginRead;
  try
    lIndex := fMetricsIndex;
  finally
    fMetricsLock.EndRead;
  end;
  Result := lIndex.GetStatsForType(lKey);
end;

function TmaxBus.GetStatsGuidOf<t>: TmaxTopicStats;
var
  lGuid: TGuid;
  lTypeKey: PTypeInfo;
  lIndex: ImaxMetricsIndex;
begin
  lTypeKey := TypeInfo(t);
  lGuid := GetTypeData(lTypeKey)^.Guid;
  fMetricsLock.BeginRead;
  try
    lIndex := fMetricsIndex;
  finally
    fMetricsLock.EndRead;
  end;
  Result := lIndex.GetStatsGuid(lGuid);
end;

function TmaxBus.GetStatsNamed(const aName: string): TmaxTopicStats;
var
  lNameKey: TmaxString;
  lIndex: ImaxMetricsIndex;
begin
  lNameKey := aName;
  fMetricsLock.BeginRead;
  try
    lIndex := fMetricsIndex;
  finally
    fMetricsLock.EndRead;
  end;
  Result := lIndex.GetStatsNamed(lNameKey);
end;

function TmaxBus.GetTotals: TmaxTopicStats;
var
  lIndex: ImaxMetricsIndex;
begin
  fMetricsLock.BeginRead;
  try
    lIndex := fMetricsIndex;
  finally
    fMetricsLock.EndRead;
  end;
  Result := lIndex.GetTotals;
end;

function TmaxBus.GetSelf: TObject;
begin
  Result := self;
end;

function maxBusObj: TmaxBus;
var
  lBus: ImaxBus;
  lImpl: ImaxBusImpl;
begin
  lBus := maxBus;
  if not Supports(lBus, ImaxBusImpl, lImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(lImpl.GetSelf);
end;

function maxBusObj(const aIntf: IInterface): TmaxBus;
var
  lImpl: ImaxBusImpl;
begin
  if not Supports(aIntf, ImaxBusImpl, lImpl) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(lImpl.GetSelf);
end;

initialization
  gBusLock := TmaxMonitorObject.Create;
  if gMetricSampleIntervalMs = 0 then
    gMetricSampleIntervalTicks := 0
  else
  begin
    gMetricSampleIntervalTicks := (UInt64(gMetricSampleIntervalMs) * UInt64(TMaxStopwatch.Frequency)) div 1000;
    if gMetricSampleIntervalTicks = 0 then
      gMetricSampleIntervalTicks := 1;
  end;
  gDelphiWeakRegistry := TDelphiWeakRegistry.Create;

finalization
  FreeAndNil(gBusLock);
  FreeAndNil(gDelphiWeakRegistry);

end.
