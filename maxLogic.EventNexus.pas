unit maxLogic.EventNexus;

{$I fpc_delphimode.inc}

{$IFDEF FPC}
{$DEFINE max_FPC}
{$ELSE}
{$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  Classes, SysUtils,
  {$IFDEF max_DELPHI}
  System.Diagnostics, System.Generics.Collections, System.SyncObjs, System.TypInfo,
  {$ELSE}
  Generics.Collections, TypInfo, maxLogic.fpc.compatibility, maxLogic.fpc.diagnostics,
  {$ENDIF}
  maxLogic.EventNexus.Threading.Adapter;

const
  max_BUS_VERSION = '0.1.0';

type
  TmaxString = type UnicodeString;

  {$IFDEF max_FPC}
  TmaxKeyFunc<t> = function(const aValue: t): TmaxString;
  {$ELSE}
  TmaxKeyFunc<t> = reference to function(const aValue: t): TmaxString;
  {$ENDIF}

  {$IFDEF max_FPC}
type
  TmaxProc = procedure;
  TmaxProcOf<t> = procedure(const aValue: t);
  {$ELSE}
type
  TmaxProc = reference to procedure;
  TmaxProcOf<t> = reference to procedure(const aValue: t);
  {$ENDIF}

type
  TmaxObjProcOf<t> = procedure(const aValue: t) of object;

  {$IFDEF max_FPC}
  TmaxProcQueue = specialize TQueue<TmaxProc>;
  TmaxExceptionList = specialize TObjectList<Exception>;
  {$ELSE}
  TmaxProcQueue = TQueue<TmaxProc>;
  TmaxExceptionList = TObjectList<Exception>;
  {$ENDIF}

  TmaxMonitorObject = TObject;

  TmaxDelivery = (Posting, Main, Async, Background);
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);

  ImaxSubscription = interface
    ['{79C1B0D9-6A9E-4C6B-8E96-88A84E4F1E03}']
    procedure Unsubscribe;
    function IsActive: boolean;
  end;

  ImaxBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): boolean;

    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
  end;

  ImaxBusAdvanced = interface(ImaxBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableStickyNamed(const aName: string; aEnable: boolean);
  end;

  TmaxQueuePolicy = record
    MaxDepth: integer;
    Overflow: TmaxOverflow;
    DeadlineUs: Int64;
  end;

  ImaxBusQueues = interface
    ['{E55F7B60-9B31-4C80-9B2C-8D1F0E26FF9C}']
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    function GetPolicyNamed(const aName: string): TmaxQueuePolicy;
  end;

  TmaxTopicStats = record
    PostsTotal: UInt64;
    DeliveredTotal: UInt64;
    DroppedTotal: UInt64;
    ExceptionsTotal: UInt64;
    MaxQueueDepth: UInt32;
    CurrentQueueDepth: UInt32;
  end;

  ImaxBusMetrics = interface
    ['{2C4B91E3-1C0A-4B5C-B8B0-0C1A5C3E6D10}']
    function GetStatsNamed(const aName: string): TmaxTopicStats;
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
    fActive: boolean;
    fInFlight: integer;
  public
    constructor Create;
    function TryEnter: boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: boolean;
  end;

  EmaxAggregateException = class(Exception)
  private
    fInner: TmaxExceptionList;
  public
    constructor Create(const aInner: TmaxExceptionList);
    destructor Destroy; override;
    property Inner: TmaxExceptionList read fInner;
  end;

  {$IFDEF max_FPC}
  TOnAsyncError = procedure(const aTopic: string; const aE: Exception);
  TOnMetricSample = procedure(const aName: string; const aStats: TmaxTopicStats);
  {$ELSE}
  TOnAsyncError = reference to procedure(const aTopic: string; const aE: Exception);
  TOnMetricSample = reference to procedure(const aName: string; const aStats: TmaxTopicStats);
  {$ENDIF}
function maxBus: ImaxBus;
procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
procedure maxSetMetricCallback(const aSampler: TOnMetricSample);
procedure maxSetAsyncScheduler(const aScheduler: IEventNexusScheduler);
function maxGetAsyncScheduler: IEventNexusScheduler;

{$IFDEF max_DELPHI}
function maxAsBus(const aIntf: IInterface): TObject;
{$ENDIF}

{$IFDEF max_DELPHI}
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
{$ENDIF}

type
  TmaxTopicBase = class(TmaxMonitorObject)
  private
    fDropActive: Integer; // number of active-item drops requested
  protected
    fQueue: TmaxProcQueue;
    fProcessing: boolean;
    fSticky: boolean;
    fPolicy: TmaxQueuePolicy;
    fStats: TmaxTopicStats;
    fMetricName: TmaxString;
    fWarnedHighWater: boolean;
    procedure TouchMetrics;
    procedure CheckHighWater; inline;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMetricName(const aName: TmaxString); inline;
    function Enqueue(const aProc: TmaxProc): boolean;
    procedure RemoveByTarget(const aTarget: TObject); virtual; abstract;
    procedure SetSticky(aEnable: boolean); virtual;
    procedure SetPolicy(const aPolicy: TmaxQueuePolicy);
    function GetPolicy: TmaxQueuePolicy;
    procedure AddPost; inline;
    procedure AddDelivered(aCount: integer); inline;
    procedure AddDropped; inline;
    procedure AddException; inline;
    function GetStats: TmaxTopicStats; inline;
    procedure RequestDropActive; inline;
    function ConsumeDropActive: Boolean; inline;
  end;

  {$IFDEF max_FPC}
  TmaxTypeTopicBaseDict = specialize TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxTypeTopicDict = specialize TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxNameTopicDict = specialize TObjectDictionary<TmaxString, TmaxTopicBase>;
  TmaxNameTypeTopicDict = specialize TObjectDictionary<TmaxString, TmaxTypeTopicBaseDict>;
  TmaxGuidTopicDict = specialize TObjectDictionary<TGuid, TmaxTopicBase>;
  TmaxBoolDictOfTypeInfo = specialize TDictionary<PTypeInfo, boolean>;
  TmaxBoolDictOfString = specialize TDictionary<TmaxString, boolean>;
  TmaxSubList = specialize TList<ImaxSubscription>;
  TmaxAutoSubDict = specialize TObjectDictionary<TObject, TmaxSubList>;
  {$ELSE}
  TmaxTypeTopicDict = TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxNameTopicDict = TObjectDictionary<TmaxString, TmaxTopicBase>;
  TmaxNameTypeTopicDict = TObjectDictionary<TmaxString, TObjectDictionary<PTypeInfo, TmaxTopicBase>>;
  TmaxGuidTopicDict = TObjectDictionary<TGuid, TmaxTopicBase>;
  TmaxBoolDictOfTypeInfo = TDictionary<PTypeInfo, boolean>;
  TmaxBoolDictOfString = TDictionary<TmaxString, boolean>;
  TmaxSubList = TList<ImaxSubscription>;
  TmaxAutoSubDict = TObjectDictionary<TObject, TmaxSubList>;
  {$ENDIF}

  TmaxSubscriptionToken = uInt64;

  TmaxWeakTarget = record
    Raw: TObject;
    {$IFDEF max_DELPHI}
    // no extra fields on Delphi; fallback to raw pointer only
    {$ELSE}
    Generation: UInt32;
    {$ENDIF}
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

  TTypedTopic<t> = class(TmaxTopicBase)
  private
    fSubs: TArray<TTypedSubscriber<t>>;
    fLast: t;
    fHasLast: boolean;
    fCoalesce: boolean;
    fKeyFunc: TmaxKeyFunc<t>;
    fWindowUs: integer;
    fPending: {$IFDEF max_FPC}specialize {$ENDIF}TDictionary<TmaxString, t>;
    fPendingLock: TmaxMonitorObject;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDead;
  public
    constructor Create;
    function Add(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState; const aTarget: TObject = nil): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TTypedSubscriber<t>>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: boolean); override;
    procedure Cache(const aEvent: t);
    function TryGetCached(out aEvent: t): boolean;
    procedure SetCoalesce(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
    function HasCoalesce: boolean;
    function CoalesceKey(const aEvent: t): TmaxString;
    function AddOrUpdatePending(const aKey: TmaxString; const aEvent: t): boolean;
    function PopPending(const aKey: TmaxString; out aEvent: t): boolean;
    function CoalesceWindow: integer;
    destructor Destroy; override;
  end;

  TmaxBus = class(TInterfacedObject, ImaxBus, ImaxBusAdvanced, ImaxBusQueues, ImaxBusMetrics, ImaxBusImpl)
  private
    fAsync: IEventNexusScheduler;
    fLock: TmaxMonitorObject;
    fTyped: TmaxTypeTopicDict;
    fNamed: TmaxNameTopicDict;
    fNamedTyped: TmaxNameTypeTopicDict;
    fGuid: TmaxGuidTopicDict;
    fStickyTypes: TmaxBoolDictOfTypeInfo;
    fStickyNames: TmaxBoolDictOfString;
    fMainThreadId: TThreadID;
    function ScheduleTypedCoalesce<t>(const aTopicName: TmaxString;
      aTopic: TTypedTopic<t>; const aSubs: TArray < TTypedSubscriber<t> > ;
      const aKey: TmaxString): boolean;
  public
    function Subscribe<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    function Subscribe<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    procedure Post<t>(const aEvent: t);
    function TryPost<t>(const aEvent: t): boolean; overload;

    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): boolean;

    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    procedure PostNamedOf<t>(const aName: TmaxString; const aEvent: t);
    function TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean; overload;

    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; overload;
    procedure PostGuidOf<t: IInterface>(const aEvent: t);
    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
    procedure EnableSticky<t>(aEnable: boolean);
    procedure EnableStickyNamed(const aName: string; aEnable: boolean);
    procedure EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0);
    procedure EnableCoalesceNamedOf<t>(const aName: string; const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0);
    procedure SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    function GetPolicyFor<t>: TmaxQueuePolicy;
    function GetPolicyNamed(const aName: string): TmaxQueuePolicy;
    function GetStatsFor<t>: TmaxTopicStats;
    function GetStatsNamed(const aName: string): TmaxTopicStats;
    function GetTotals: TmaxTopicStats;
  public
    function GetSelf: TObject;
    constructor Create(const aAsync: IEventNexusScheduler);
    destructor Destroy; override;
    procedure Dispatch(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc; const aOnException: TmaxProc = nil);
  end;

  {$IFDEF max_FPC}
  ImaxBusHelper = class helper for ImaxBus
  private
    function Impl: TmaxBus; inline;
  public
    function Subscribe<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    procedure Post<t>(const aEvent: t); inline;
    function TryPost<t>(const aEvent: t): boolean; inline;
    function Subscribe<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    function SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    procedure PostNamedOf<t>(const aName: TmaxString; const aEvent: t); inline;
    function TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean; inline;
    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    function SubscribeGuidOf<t: IInterface>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription; inline;
    procedure PostGuidOf<t: IInterface>(const aEvent: t); inline;
    procedure EnableSticky<t>(aEnable: boolean); inline;
  end;

  ImaxBusAdvancedHelper = record helper for ImaxBusAdvanced
  private
    function Impl: TmaxBus; inline;
  public
    procedure EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0); inline;
    procedure EnableCoalesceNamedOf<t>(const aName: string; const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer = 0); inline;
  end;

  ImaxBusQueuesHelper = record helper for ImaxBusQueues
  private
    function Impl: TmaxBus; inline;
  public
    procedure SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy); inline;
    function GetPolicyFor<t>: TmaxQueuePolicy; inline;
  end;

  ImaxBusMetricsHelper = record helper for ImaxBusMetrics
  private
    function Impl: TmaxBus; inline;
  public
    function GetStatsFor<t>: TmaxTopicStats; inline;
  end;
  {$ENDIF}

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
    fHasLast: boolean;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDead;
  public
    function Add(const aHandler: TmaxProc; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TNamedSubscriber>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: boolean); override;
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

var
  gAsyncError: TOnAsyncError = nil;

implementation
uses
  {$IFDEF max_FPC} SyncObjs, {$ENDIF}
  maxLogic.EventNexus.Threading.RawThread;

resourcestring
  SAggregateOccurred = '%d exception(s) occurred';
  SInvalidBusImplementation = 'Invalid bus implementation';


var
  gMetricSample: TOnMetricSample = nil;
  gBus: ImaxBus = nil;
  gAsyncScheduler: IEventNexusScheduler = nil;
  gAsyncFallback: IEventNexusScheduler = nil;

  {$IFDEF max_FPC}
type
  TFpcWeakEntry = record
    Generation: UInt32;
    Alive: boolean;
  end;

  TmaxObjectAccess = class(TObject);

  TFpcWeakRegistry = class
  private
    type
      TFreeInstanceThunk = procedure(aSelf: TObject);
    fEntries: specialize TDictionary<TObject, TFpcWeakEntry>;
    fHooks: specialize TDictionary<TClass, Pointer>;
    fLock: TCriticalSection;
    function EnsureHook(const aObj: TObject): boolean;
    function LocateFreeInstanceSlot(const aClass: TClass; const aOrig: Pointer): PPointer;
    function PrepareFreeInstance(const aObj: TObject): Pointer;
  public
    constructor Create;
    destructor Destroy; override;
    function Observe(const aObj: TObject): UInt32;
    function IsAlive(const aObj: TObject; const aGeneration: UInt32): boolean;
    class function Instance: TFpcWeakRegistry; static;
  end;

var
  gFpcWeakRegistry: TFpcWeakRegistry = nil;

procedure FpcWeakFreeInstanceHook(aSelf: TObject); forward;
{$ENDIF}

{$IFDEF max_FPC}

{ TFpcWeakRegistry }

constructor TFpcWeakRegistry.Create;
begin
  inherited Create;
  fEntries := specialize TDictionary<TObject, TFpcWeakEntry>.Create;
  fHooks := specialize TDictionary<TClass, Pointer>.Create;
  fLock := TCriticalSection.Create;
end;

destructor TFpcWeakRegistry.Destroy;
begin
  fLock.Free;
  fEntries.Free;
  fHooks.Free;
  inherited Destroy;
end;

class function TFpcWeakRegistry.Instance: TFpcWeakRegistry;
begin
  if gFpcWeakRegistry = nil then
    gFpcWeakRegistry := TFpcWeakRegistry.Create;
  Result := gFpcWeakRegistry;
end;

function TFpcWeakRegistry.LocateFreeInstanceSlot(const aClass: TClass;
  const aOrig: Pointer): PPointer;
var
  lVmt: PPointer;
  lIdx: integer;
const
  SEARCH_LIMIT = 128;
begin
  lVmt := PPointer(aClass);
  for lIdx := 0 to SEARCH_LIMIT do
  begin
    if (lVmt + lIdx)^ = aOrig then
      exit(lVmt + lIdx);
  end;
  Result := nil;
end;

function TFpcWeakRegistry.EnsureHook(const aObj: TObject): boolean;
var
  lClass: TClass;
  lMethod: procedure of object;
  lOrig: Pointer;
  lSlot: PPointer;
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

  lMethod := TmaxObjectAccess(aObj).FreeInstance;
  lOrig := TMethod(lMethod).Code;
  if lOrig = @FpcWeakFreeInstanceHook then
    exit(True);

  lSlot := LocateFreeInstanceSlot(lClass, lOrig);
  if lSlot = nil then
    exit(False);

  fLock.Enter;
  try
    if not fHooks.ContainsKey(lClass) then
    begin
      fHooks.Add(lClass, lOrig);
      lSlot^ := @FpcWeakFreeInstanceHook;
    end;
    Result := True;
  finally
    fLock.Leave;
  end;
end;

function TFpcWeakRegistry.PrepareFreeInstance(const aObj: TObject): Pointer;
var
  lEntry: TFpcWeakEntry;
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

function TFpcWeakRegistry.Observe(const aObj: TObject): UInt32;
var
  lEntry: TFpcWeakEntry;
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

function TFpcWeakRegistry.IsAlive(const aObj: TObject; const aGeneration: UInt32): boolean;
var
  lEntry: TFpcWeakEntry;
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

procedure FpcWeakFreeInstanceHook(aSelf: TObject);
var
  lOrig: Pointer;
begin
  lOrig := TFpcWeakRegistry.Instance.PrepareFreeInstance(aSelf);
  if lOrig <> nil then
    TFpcWeakRegistry.TFreeInstanceThunk(lOrig)(aSelf);
end;

{$ENDIF}

{$IFDEF max_DELPHI}

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
begin
  // Delphi RTTI-based auto-subscribe is not implemented yet on this branch.
end;

procedure AutoUnsubscribe(const aInstance: TObject);
begin
  // No-op; explicit unsubscribe via tokens is still supported.
end;
{$ENDIF}

{ EmaxAggregateException }

constructor EmaxAggregateException.Create(const aInner: TmaxExceptionList);
begin
  fInner := aInner;
  inherited CreateFmt(SAggregateOccurred, [fInner.Count]);
end;

destructor EmaxAggregateException.Destroy;
begin
  fInner.Free;
  inherited Destroy;
end;

{ TmaxWeakTarget }

class function TmaxWeakTarget.Create(const aObj: TObject): TmaxWeakTarget;
begin
  Result.Raw := aObj;
  {$IFDEF max_DELPHI}
  // no-op; use Raw only on Delphi
  {$ELSE}
  if aObj <> nil then
    Result.Generation := TFpcWeakRegistry.Instance.Observe(aObj)
  else
    Result.Generation := 0;
  {$ENDIF}
end;

function TmaxWeakTarget.Matches(const aObj: TObject): boolean;
begin
  Result := (Raw <> nil) and (Raw = aObj);
end;

function TmaxWeakTarget.IsAlive: boolean;
begin
  if Raw = nil then
    exit(True);
  {$IFDEF max_DELPHI}
  Result := assigned(Raw);
  {$ELSE}
  Result := TFpcWeakRegistry.Instance.IsAlive(Raw, Generation);
  {$ENDIF}
end;

{ TmaxSubscriptionState }

constructor TmaxSubscriptionState.Create;
begin
  inherited Create;
  fActive := True;
  fInFlight := 0;
end;

function TmaxSubscriptionState.TryEnter: boolean;
begin
  TMonitor.Enter(self);
  try
    if not fActive then
      exit(False);
    Inc(fInFlight);
    Result := True;
  finally
    TMonitor.exit(self);
  end;
end;

procedure TmaxSubscriptionState.Leave;
begin
  TMonitor.Enter(self);
  try
    if fInFlight > 0 then
      Dec(fInFlight);
  finally
    TMonitor.exit(self);
  end;
end;

procedure TmaxSubscriptionState.Deactivate;
begin
  TMonitor.Enter(self);
  try
    if fActive then
      fActive := False;
  finally
    TMonitor.exit(self);
  end;
end;

function TmaxSubscriptionState.IsActive: boolean;
begin
  TMonitor.Enter(self);
  try
    Result := fActive;
  finally
    TMonitor.exit(self);
  end;
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
  fMetricName := '';
  fWarnedHighWater := False;
  fDropActive := 0;
  FillChar(fStats, SizeOf(fStats), 0);
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

procedure TmaxTopicBase.SetPolicy(const aPolicy: TmaxQueuePolicy);
begin
  fPolicy := aPolicy;
  fWarnedHighWater := False;
end;

function TmaxTopicBase.GetPolicy: TmaxQueuePolicy;
begin
  Result := fPolicy;
end;

procedure TmaxTopicBase.TouchMetrics;
begin
  if (fMetricName <> '') and Assigned(gMetricSample) then
    gMetricSample(UnicodeString(fMetricName), fStats);
end;

procedure TmaxTopicBase.CheckHighWater;
begin
  if fPolicy.MaxDepth = 0 then
  begin
    if (not fWarnedHighWater) and (fStats.CurrentQueueDepth > 10000) then
    begin
      fWarnedHighWater := True;
      TouchMetrics;
    end
    else if fWarnedHighWater and (fStats.CurrentQueueDepth <= 5000) then
      fWarnedHighWater := False;
  end;
end;

procedure TmaxTopicBase.AddPost;
begin
  Inc(fStats.PostsTotal);
  TouchMetrics;
end;

procedure TmaxTopicBase.AddDelivered(aCount: integer);
begin
  Inc(fStats.DeliveredTotal, aCount);
  TouchMetrics;
end;

procedure TmaxTopicBase.AddDropped;
begin
  Inc(fStats.DroppedTotal);
  TouchMetrics;
end;

procedure TmaxTopicBase.AddException;
begin
  Inc(fStats.ExceptionsTotal);
  TouchMetrics;
end;

function TmaxTopicBase.GetStats: TmaxTopicStats;
begin
  Result := fStats;
end;

procedure TmaxTopicBase.RequestDropActive;
begin
  Inc(fDropActive);
end;

function TmaxTopicBase.ConsumeDropActive: Boolean;
begin
  Result := False;
  TMonitor.Enter(self);
  try
    if fDropActive > 0 then
    begin
      Dec(fDropActive);
      AddDropped; // count as a drop
      Result := True;
    end;
  finally
    TMonitor.exit(self);
  end;
end;

function TmaxTopicBase.Enqueue(const aProc: TmaxProc): boolean;
var
  lProc: TmaxProc;
  lTimer: TStopWatch;
  lDeadlineMs: Cardinal;
  lRemaining: integer;
  lElapsedMs: Int64;
  used: integer;
begin
  Result := True;
  TMonitor.Enter(self);
  try
    used := fQueue.Count;
    if fProcessing then
      Inc(used); // count the in-flight item towards capacity
    if (fPolicy.MaxDepth > 0) and (used >= fPolicy.MaxDepth) then
    begin
      case fPolicy.Overflow of
        DropNewest:
          begin
            AddDropped;
            exit(False);
          end;
        DropOldest:
          begin
            // Drop the oldest across queued+in-flight:
            if fQueue.Count > 0 then
            begin
              fQueue.Dequeue;
              if fStats.CurrentQueueDepth > 0 then
                Dec(fStats.CurrentQueueDepth);
              AddDropped;
              Result := False; // signal a drop happened
            end
            else
            begin
              // queue is empty but an item is in-flight; request to drop the active one
              RequestDropActive;
              Result := False; // signal a drop happened
            end;
          end;
        Block:
          while True do
          begin
            used := fQueue.Count;
            if fProcessing then Inc(used);
            if used < fPolicy.MaxDepth then break;
            TMonitor.Wait(self, Cardinal(-1));
          end;
        Deadline:
          if fPolicy.DeadlineUs <= 0 then
          begin
            while True do
            begin
              used := fQueue.Count;
              if fProcessing then Inc(used);
              if used < fPolicy.MaxDepth then break;
              TMonitor.Wait(self, Cardinal(-1));
            end;
          end
          else
          begin
            lDeadlineMs := Cardinal(fPolicy.DeadlineUs div 1000);
            lTimer := TStopWatch.StartNew;
            while True do
            begin
              used := fQueue.Count;
              if fProcessing then Inc(used);
              if used < fPolicy.MaxDepth then break;
              lElapsedMs := lTimer.ElapsedMilliseconds;
              lRemaining := integer(Int64(lDeadlineMs) - lElapsedMs);
              if lRemaining <= 0 then
              begin
                AddDropped;
                exit(False);
              end;
              TMonitor.Wait(self, Cardinal(lRemaining));
            end;
          end;
      end;
    end;
    fQueue.Enqueue(aProc);
    Inc(fStats.CurrentQueueDepth);
    if fStats.CurrentQueueDepth > fStats.MaxQueueDepth then
      fStats.MaxQueueDepth := fStats.CurrentQueueDepth;
    CheckHighWater;
    TouchMetrics;
    if fProcessing then
      exit(True);
    fProcessing := True;
  finally
    TMonitor.exit(self);
  end;
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
      if fStats.CurrentQueueDepth > 0 then
        Dec(fStats.CurrentQueueDepth);
      CheckHighWater;
      TouchMetrics;
      TMonitor.Pulse(self);
    finally
      TMonitor.exit(self);
    end;
    lProc();
  end;
end;

procedure TmaxTopicBase.SetSticky(aEnable: boolean);
begin
  fSticky := aEnable;
end;

function NormalizeName(const aName: TmaxString): TmaxString; inline;
begin
  Result := TmaxString(UpperCase(UnicodeString(aName)));
end;

function TypeMetricName(const aInfo: PTypeInfo): TmaxString; inline;
begin
  Result := TmaxString(GetTypeName(aInfo));
end;

function NamedMetricName(const aName: TmaxString): TmaxString; inline;
begin
  Result := aName;
end;

function NamedTypeMetricName(const aName: TmaxString; const aInfo: PTypeInfo): TmaxString; inline;
begin
  Result := TmaxString(UnicodeString(aName) + ':' + UnicodeString(GetTypeName(aInfo)));
end;

function GuidMetricName(const aGuid: TGuid): TmaxString; inline;
begin
  Result := TmaxString(GuidToString(aGuid));
end;

{ TTypedTopic<T> }

constructor TTypedTopic<t>.Create;
begin
  inherited Create;
  fPendingLock := TmaxMonitorObject.Create;
  fNextToken := 1;
  SetLength(fSubs, 0);
end;

procedure TTypedTopic<t>.PruneDead;
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
end;

function TTypedTopic<t>.Add(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState; const aTarget: TObject = nil): TmaxSubscriptionToken;
var
  lNew: TArray<TTypedSubscriber<t>>;
  lSub: TTypedSubscriber<t>;
begin
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
  Result := lSub.Token;
end;

procedure TTypedTopic<t>.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TTypedSubscriber<t>>;
begin
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
end;

function TTypedTopic<t>.Snapshot: TArray<TTypedSubscriber<t>>;
begin
  PruneDead;
  Result := copy(fSubs);
end;

procedure TTypedTopic<t>.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TTypedSubscriber<t>>;
begin
  if aTarget = nil then
    exit;
  PruneDead;
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
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

procedure TTypedTopic<t>.SetSticky(aEnable: boolean);
begin
  inherited SetSticky(aEnable);
  if not aEnable then
    fHasLast := False;
end;

procedure TTypedTopic<t>.Cache(const aEvent: t);
begin
  if fSticky then
  begin
    fLast := aEvent;
    fHasLast := True;
  end;
end;

function TTypedTopic<t>.TryGetCached(out aEvent: t): boolean;
begin
  Result := fSticky and fHasLast;
  if Result then
    aEvent := fLast;
end;

procedure TTypedTopic<t>.SetCoalesce(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
begin
  fCoalesce := assigned(aKeyOf);
  fKeyFunc := aKeyOf;
  if aWindowUs < 0 then
    fWindowUs := 0
  else
    fWindowUs := aWindowUs;
  TMonitor.Enter(fPendingLock);
  try
    if fCoalesce then
    begin
      if fPending = nil then
      begin
        {$IFDEF max_FPC}
        fPending := specialize TDictionary<TmaxString, t>.Create;
        {$ELSE}
        fPending := TDictionary<TmaxString, t>.Create;
        {$ENDIF}
      end;
    end
    else if fPending <> nil then
    begin
      fPending.Free;
      fPending := nil;
    end;
  finally
    TMonitor.exit(fPendingLock);
  end;
end;

function TTypedTopic<t>.HasCoalesce: boolean;
begin
  Result := fCoalesce;
end;

function TTypedTopic<t>.CoalesceKey(const aEvent: t): TmaxString;
begin
  if assigned(fKeyFunc) then
    Result := fKeyFunc(aEvent)
  else
    Result := '';
end;

function TTypedTopic<t>.AddOrUpdatePending(const aKey: TmaxString; const aEvent: t): boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending = nil then
    begin
      {$IFDEF max_FPC}
      fPending := specialize TDictionary<TmaxString, t>.Create;
      {$ELSE}
      fPending := TDictionary<TmaxString, t>.Create;
      {$ENDIF}
    end;
    Result := not fPending.ContainsKey(aKey);
    fPending.AddOrSetValue(aKey, aEvent);
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

function TTypedTopic<t>.CoalesceWindow: integer;
begin
  Result := fWindowUs;
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
  Result := lSub.Token;
end;

procedure TNamedTopic.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TNamedSubscriber>;
begin
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
end;

procedure TNamedTopic.PruneDead;
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
end;

function TNamedTopic.Snapshot: TArray<TNamedSubscriber>;
begin
  PruneDead;
  Result := copy(fSubs);
end;

procedure TNamedTopic.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: integer;
  lNew: TArray<TNamedSubscriber>;
begin
  if aTarget = nil then
    exit;
  PruneDead;
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
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

procedure TNamedTopic.SetSticky(aEnable: boolean);
begin
  inherited SetSticky(aEnable);
  if not aEnable then
    fHasLast := False;
end;

procedure TNamedTopic.Cache;
begin
  if fSticky then
    fHasLast := True;
end;

function TNamedTopic.HasCached: boolean;
begin
  Result := fSticky and fHasLast;
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
    gBus := TmaxBus.Create(DefaultAsync);
  Result := gBus;
end;

procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
begin
  gAsyncError := aHandler;
end;

procedure maxSetMetricCallback(const aSampler: TOnMetricSample);
begin
  gMetricSample := aSampler;
end;

procedure maxSetAsyncScheduler(const aScheduler: IEventNexusScheduler);
begin
  gAsyncScheduler := aScheduler;
end;

function maxGetAsyncScheduler: IEventNexusScheduler;
begin
  if gAsyncScheduler <> nil then
    Result := gAsyncScheduler
  else
    Result := DefaultAsync;
end;
{ TmaxBus }

function TmaxBus.ScheduleTypedCoalesce<t>(const aTopicName: TmaxString;
  aTopic: TTypedTopic<t>; const aSubs: TArray<TTypedSubscriber<t>>;
  const aKey: TmaxString): boolean;
var
  lKeyCopy: TmaxString;
begin
  lKeyCopy := aKey;
  fAsync.RunDelayed(
    procedure
    var
      lInner: t;
      lErrs: TmaxExceptionList;
      ex: EmaxAggregateException;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if not aTopic.PopPending(lKeyCopy, lInner) then
        exit;
      lErrs := nil;

      for i := 0 to High(aSubs) do
      begin
        lHandler := aSubs[i].Handler;
        lMode := aSubs[i].Mode;
        lToken := aSubs[i].Token;
        lState := aSubs[i].State;

        if (lState <> nil) and not lState.TryEnter then
          continue;

        if not aSubs[i].Target.IsAlive then
        begin
          aTopic.RemoveByToken(lToken);
          if lState <> nil then
            lState.Leave;
          continue;
        end;

        try
          Dispatch(aTopicName, lMode,
            procedure
            begin
              try
                try
                  lHandler(lInner);
                  aTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      aTopic.RemoveByToken(lToken);
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
              aTopic.AddException;
            end);
        except
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;

      if lErrs <> nil then
      begin
        if Assigned(gAsyncError) then
        begin
          ex := EmaxAggregateException.Create(lErrs);
          try
            gAsyncError(UnicodeString(aTopicName), ex);
          finally
            ex.Free;
          end;
        end
        else
          lErrs.Free;
      end;
    end,
    aTopic.CoalesceWindow);
  Result := True;
end;

{ TmaxBus }

constructor TmaxBus.Create(const aAsync: IEventNexusScheduler);
begin
  inherited Create;
  fAsync := aAsync;
  fLock := TmaxMonitorObject.Create;
  fTyped := TmaxTypeTopicDict.Create([doOwnsValues]);
  fNamed := TmaxNameTopicDict.Create([doOwnsValues]);
  fNamedTyped := TmaxNameTypeTopicDict.Create([doOwnsValues]);
  fGuid := TmaxGuidTopicDict.Create([doOwnsValues]);
  fStickyTypes := TmaxBoolDictOfTypeInfo.Create;
  fStickyNames := TmaxBoolDictOfString.Create;
  fMainThreadId := TThread.CurrentThread.ThreadID;
end;

destructor TmaxBus.Destroy;
begin
  fTyped.Free;
  fNamedTyped.Free;
  fNamed.Free;
  fGuid.Free;
  fStickyTypes.Free;
  fStickyNames.Free;
  fLock.Free;
  inherited Destroy;
end;

procedure TmaxBus.Dispatch(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc; const aOnException: TmaxProc);
begin
  case aDelivery of
    Posting:
      try
        aHandler();
      except
        on e: Exception do
        begin
          if Assigned(aOnException) then
            aOnException();
          raise;
        end;
      end;
    Main:
      if (TThread.CurrentThread.ThreadID = fMainThreadId) or fAsync.IsMainThread then
      begin
        try
          aHandler();
        except
          on e: Exception do
          begin
            if Assigned(aOnException) then
              aOnException();
            if Assigned(gAsyncError) then
              gAsyncError(UnicodeString(aTopic), e);
          end;
        end;
      end
      else
      begin
        // No reliable message pump in console tests: degrade to Async to guarantee progress
        fAsync.RunAsync(
          procedure
          begin
            try
              aHandler();
            except
              on e: Exception do
              begin
                if Assigned(aOnException) then
                  aOnException();
                if Assigned(gAsyncError) then
                  gAsyncError(UnicodeString(aTopic), e);
              end;
            end;
          end);
      end;
    Async:
      fAsync.RunAsync(
        procedure
        begin
          try
            aHandler();
          except
            on e: Exception do
            begin
              if Assigned(aOnException) then
                aOnException();
              if Assigned(gAsyncError) then
                gAsyncError(UnicodeString(aTopic), e);
            end;
          end;
        end);
    Background:
      if (TThread.CurrentThread.ThreadID = fMainThreadId) or fAsync.IsMainThread then
        fAsync.RunAsync(
          procedure
          begin
            try
              aHandler();
            except
              on e: Exception do
              begin
                if Assigned(aOnException) then
                  aOnException();
                if Assigned(gAsyncError) then
                  gAsyncError(UnicodeString(aTopic), e);
              end;
            end;
          end)
      else
      try
        aHandler();
      except
        on e: Exception do
        begin
          if Assigned(aOnException) then
            aOnException();
          if Assigned(gAsyncError) then
            gAsyncError(UnicodeString(aTopic), e);
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
begin
  lKey := TypeInfo(t);
  lMetricName := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetricName);
      if fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetricName);
    lToken := lTopic.Add(aHandler, aMode, lState);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
begin
  lKey := TypeInfo(t);
  lMetricName := TypeMetricName(lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetricName);
      if fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetricName);
    lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.Post<t>(const aEvent: t);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lIsNew: boolean;
  lKeyStr: TmaxString;
  lDropVal: t;
  lMetric: TmaxString;
begin
  lIsNew := False; // prevent compiler warning: variable might not have been initialized

  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
      end
      else
        exit;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      exit;
    if not ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    exit;
  end;
  lTopic.Enqueue(
    procedure
    var
      lVal: t;
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lVal := aEvent;
      lErrs := nil;

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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
end;

function TmaxBus.TryPost<t>(const aEvent: t): boolean;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lIsNew: boolean;
  lKeyStr: TmaxString;
  lDropVal: t;
  lMetric: TmaxString;
begin
  lIsNew := False; // prevent compiler warning: variable might not have been initialized

  Result := True;
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lTopic.Cache(aEvent);
      end;
      exit;
    end;
    lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      exit;
    Result := ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    exit;
  end;
  Result := lTopic.Enqueue(
    procedure
    var
      lVal: t;
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lVal := aEvent;
      lErrs := nil;

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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
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
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lObj) then
    begin
      lTopic := TNamedTopic.Create;
      lTopic.SetMetricName(lMetric);
      if fStickyNames.ContainsKey(lNameKey) then
        lTopic.SetSticky(True);
      fNamed.Add(lNameKey, lTopic);
    end
    else
      lTopic := TNamedTopic(lObj);
    lTopic.SetMetricName(lMetric);
    lToken := lTopic.Add(aHandler, aMode, lState);
    lSend := lTopic.HasCached;
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
      end);
  Result := TmaxNamedSubscription.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.PostNamed(const aName: TmaxString);
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lSubs: TArray<TNamedSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        lTopic := TNamedTopic.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fNamed.Add(lNameKey, lTopic);
      end
      else
        exit;
    end
    else
      lTopic := TNamedTopic(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  lTopic.Enqueue(
    procedure
    var
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProc;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lErrs := nil;

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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler();
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
end;

function TmaxBus.TryPostNamed(const aName: TmaxString): boolean;
var
  lObj: TmaxTopicBase;
  lTopic: TNamedTopic;
  lSubs: TArray<TNamedSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  Result := True;
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        lTopic := TNamedTopic.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fNamed.Add(lNameKey, lTopic);
        lTopic.Cache;
      end;
      exit;
    end;
    lTopic := TNamedTopic(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  Result := lTopic.Enqueue(
    procedure
    var
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProc;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lErrs := nil;

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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler();
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
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
begin
  lKey := TypeInfo(t);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  TMonitor.Enter(fLock);
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
      if fNamed.TryGetValue(lNameKey, lBase) then
        lTopic.SetPolicy(lBase.GetPolicy);
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lToken := lTopic.Add(aHandler, aMode, lState);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
begin
  lKey := TypeInfo(t);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

  TMonitor.Enter(fLock);
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
      if fNamed.TryGetValue(lNameKey, lBase) then
        lTopic.SetPolicy(lBase.GetPolicy);
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.PostNamedOf<t>(const aName: TmaxString; const aEvent: t);
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lIsNew: boolean;
  lKeyStr: TmaxString;
  lDropVal: t;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lBase: TmaxTopicBase;
  lKey: PTypeInfo;
begin
  lIsNew := False; // prevent compiler warning: variable might not have been initialized

  lKey := TypeInfo(t);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
      begin
        lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end
      else
        exit;
    end;
    if not lTypeDict.TryGetValue(lKey, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        if fNamed.TryGetValue(lNameKey, lBase) then
          lTopic.SetPolicy(lBase.GetPolicy);
        lTopic.SetSticky(True);
        lTypeDict.Add(lKey, lTopic);
      end
      else
        exit;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      exit;
    if not ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    exit;
  end;
  lTopic.Enqueue(
    procedure
    var
      lVal: t;
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lVal := aEvent;
      lErrs := nil;
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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
end;

function TmaxBus.TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lIsNew: boolean;
  lKeyStr: TmaxString;
  lDropVal: t;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lBase: TmaxTopicBase;
  lKey: PTypeInfo;
begin
  lIsNew := False; // prevent compiler warning: variable might not have been initialized

  Result := True;
  lKey := TypeInfo(t);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
      begin
        lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end;
      exit;
    end;
    if not lTypeDict.TryGetValue(lKey, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        if fNamed.TryGetValue(lNameKey, lBase) then
          lTopic.SetPolicy(lBase.GetPolicy);
        lTopic.SetSticky(True);
        lTypeDict.Add(lKey, lTopic);
        lTopic.Cache(aEvent);
      end;
      exit;
    end;
    lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      exit;
    Result := ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    exit;
  end;
  Result := lTopic.Enqueue(
    procedure
    var
      lVal: t;
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lVal := aEvent;
      lErrs := nil;
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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
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
begin
  lKey := GetTypeData(TypeInfo(t))^.Guid;
  lMetric := GuidMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if fStickyTypes.ContainsKey(TypeInfo(t)) then
        lTopic.SetSticky(True);
      fGuid.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lToken := lTopic.Add(aHandler, aMode, lState);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
begin
  lKey := GetTypeData(TypeInfo(t))^.Guid;
  lMetric := GuidMetricName(lKey);
  lTarget := TObject(TMethod(aHandler).Data);
  lWrapper :=
    procedure(const v: t)
  begin
    aHandler(v);
  end;

  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if fStickyTypes.ContainsKey(TypeInfo(t)) then
        lTopic.SetSticky(True);
      fGuid.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lToken := lTopic.Add(lWrapper, aMode, lState, lTarget);
    lSend := lTopic.TryGetCached(lLast);
  finally
    TMonitor.exit(fLock);
  end;
  if lSend then
    lTopic.Enqueue(
      procedure
      var
        lVal: t;
      begin
        if lTopic.ConsumeDropActive then
          Exit;
        lVal := lLast;
        if (lState = nil) or not lState.TryEnter then
          exit;
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
                    lTopic.RemoveByToken(lToken);
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
      end);
  Result := TmaxTypedSubscription<t>.Create(lTopic, lToken, lState);
end;

procedure TmaxBus.PostGuidOf<t>(const aEvent: t);
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lSubs: TArray<TTypedSubscriber<t>>;
  lIsNew: boolean;
  lKeyStr: TmaxString;
  lDrop: t;
  lMetric: TmaxString;
begin
  lIsNew := False; // prevent compiler warning: variable might not have been initialized

  lKey := GetTypeData(TypeInfo(t))^.Guid;
  lMetric := GuidMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(TypeInfo(t)) then
      begin
        lTopic := TTypedTopic<t>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fGuid.Add(lKey, lTopic);
      end
      else
        exit;
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.exit(fLock);
  end;
  lTopic.AddPost;
  if length(lSubs) = 0 then
    exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      exit;
    if not ScheduleTypedCoalesce<t>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.PopPending(lKeyStr, lDrop);
    end;
    exit;
  end;
  lTopic.Enqueue(
    procedure
    var
      lVal: t;
      lErrs: TmaxExceptionList;
      i: Integer;
      lHandler: TmaxProcOf<t>;
      lMode: TmaxDelivery;
      lToken: TmaxSubscriptionToken;
      lState: ImaxSubscriptionState;
    begin
      if lTopic.ConsumeDropActive then
        Exit;
      lVal := aEvent;
      lErrs := nil;
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
          Dispatch(lMetric, lMode,
            procedure
            begin
              try
                try
                  lHandler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lToken);
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
          on e: Exception do
          begin
            if lErrs = nil then
              lErrs := TmaxExceptionList.Create(True);
            {$IFDEF max_DELPHI}
            lErrs.Add(Exception(AcquireExceptionObject));
            {$ELSE}
            lErrs.Add(e);
            {$ENDIF}
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
end;

procedure TmaxBus.EnableSticky<t>(aEnable: boolean);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  {$IFDEF max_FPC}
  lKvName: specialize TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
  {$ELSE}
  lKvName: TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  {$ENDIF}
  lGuid: TGuid;
  lMetric: TmaxString;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyTypes.AddOrSetValue(lKey, True)
    else
      fStickyTypes.Remove(lKey);
    if fTyped.TryGetValue(lKey, lObj) then
    begin
      lObj.SetMetricName(lMetric);
      lObj.SetSticky(aEnable);
    end;
    for lKvName in fNamedTyped do
      if lKvName.Value.TryGetValue(lKey, lObj) then
      begin
        lObj.SetMetricName(NamedTypeMetricName(lKvName.Key, lKey));
        lObj.SetSticky(aEnable);
      end;
    lGuid := GetTypeData(lKey)^.Guid;
    if fGuid.TryGetValue(lGuid, lObj) then
    begin
      lObj.SetMetricName(GuidMetricName(lGuid));
      lObj.SetSticky(aEnable);
    end;
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.EnableStickyNamed(const aName: string; aEnable: boolean);
var
  lObj: TmaxTopicBase;
  lTypeDict: TmaxTypeTopicDict;
  {$IFDEF max_FPC}
  lKvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
  {$ELSE}
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  {$ENDIF}
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyNames.AddOrSetValue(lNameKey, True)
    else
      fStickyNames.Remove(lNameKey);
    if fNamed.TryGetValue(lNameKey, lObj) then
    begin
      lObj.SetMetricName(lMetric);
      lObj.SetSticky(aEnable);
    end;
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
      for lKvInner in lTypeDict do
      begin
        lKvInner.Value.SetMetricName(NamedTypeMetricName(lNameKey, lKvInner.Key));
        lKvInner.Value.SetSticky(aEnable);
      end;
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      if fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lTopic.SetCoalesce(aKeyOf, aWindowUs);
  finally
    TMonitor.exit(fLock);
  end;
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
begin
  lKey := TypeInfo(t);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, lKey);
  TMonitor.Enter(fLock);
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
      if fNamed.TryGetValue(lNameKey, lBase) then
        lTopic.SetPolicy(lBase.GetPolicy);
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(lKey) then
        lTopic.SetSticky(True);
      lTypeDict.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lTopic.SetCoalesce(aKeyOf, aWindowUs);
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.UnsubscribeAllFor(const aTarget: TObject);
var
  {$IFDEF max_FPC}
  lKvTyped: specialize TPair<PTypeInfo, TmaxTopicBase>;
  lKvNamed: specialize TPair<TmaxString, TmaxTopicBase>;
  lKvName:  specialize TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
  lKvGuid:  specialize TPair<TGuid, TmaxTopicBase>;
  {$ELSE}
  lKvTyped: TPair<PTypeInfo, TmaxTopicBase>;
  lKvNamed: TPair<TmaxString, TmaxTopicBase>;
  lKvName:  TPair<TmaxString, TmaxTypeTopicDict>;
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  lKvGuid:  TPair<TGuid, TmaxTopicBase>;
  {$ENDIF}
begin
  if aTarget = nil then
    exit;
  TMonitor.Enter(fLock);
  try
    for lKvTyped in fTyped do
      lKvTyped.Value.RemoveByTarget(aTarget);
    for lKvNamed in fNamed do
      lKvNamed.Value.RemoveByTarget(aTarget);
    for lKvName in fNamedTyped do
      for lKvInner in lKvName.Value do
        lKvInner.Value.RemoveByTarget(aTarget);
    for lKvGuid in fGuid do
      lKvGuid.Value.RemoveByTarget(aTarget);
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.Clear;
begin
  TMonitor.Enter(fLock);
  try
    fTyped.Clear;
    fNamed.Clear;
    fNamedTyped.Clear;
    fGuid.Clear;
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<t>;
  lMetric: TmaxString;
begin
  lKey := TypeInfo(t);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<t>.Create;
      lTopic.SetMetricName(lMetric);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<t>(lObj);
    lTopic.SetMetricName(lMetric);
    lTopic.SetPolicy(aPolicy);
  finally
    TMonitor.exit(fLock);
  end;
end;

procedure TmaxBus.SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
var
  lTopic: TmaxTopicBase;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lTypeDict: TmaxTypeTopicDict;
  {$IFDEF max_FPC}
  lKvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
  {$ELSE}
  lKvInner: TPair<PTypeInfo, TmaxTopicBase>;
  {$ENDIF}
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lTopic) then
    begin
      lTopic := TNamedTopic.Create;
      TNamedTopic(lTopic).SetMetricName(lMetric);
      fNamed.Add(lNameKey, lTopic);
    end
    else if lTopic is TNamedTopic then
      TNamedTopic(lTopic).SetMetricName(lMetric);
    lTopic.SetPolicy(aPolicy);
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
      for lKvInner in lTypeDict do
      begin
        lKvInner.Value.SetMetricName(NamedTypeMetricName(lNameKey, lKvInner.Key));
        lKvInner.Value.SetPolicy(aPolicy);
      end;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetPolicyFor<t>: TmaxQueuePolicy;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
begin
  lKey := TypeInfo(t);
  TMonitor.Enter(fLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      Result := lObj.GetPolicy
    else
    begin
      Result.MaxDepth := 0;
      Result.Overflow := DropNewest;
      Result.DeadlineUs := 0;
    end;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetPolicyNamed(const aName: string): TmaxQueuePolicy;
var
  lTopic: TmaxTopicBase;
  lNameKey: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if fNamed.TryGetValue(lNameKey, lTopic) then
      Result := lTopic.GetPolicy
    else begin
      Result.MaxDepth := 0;
      Result.Overflow := DropNewest;
      Result.DeadlineUs := 0;
    end;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetStatsFor<t>: TmaxTopicStats;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
begin
  FillChar(Result, SizeOf(Result), 0);
  lKey := TypeInfo(t);
  TMonitor.Enter(fLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      Result := lObj.GetStats;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetStatsNamed(const aName: string): TmaxTopicStats;
var
  lObj: TmaxTopicBase;
  lNameKey: TmaxString;
  lTypeDict: TmaxTypeTopicDict;
  lInner: TmaxTopicBase;
begin
  FillChar(Result, SizeOf(Result), 0);
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
      Result := lObj.GetStats;
    if fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
      for lInner in lTypeDict.Values do
      begin
        Inc(Result.PostsTotal, lInner.GetStats.PostsTotal);
        Inc(Result.DeliveredTotal, lInner.GetStats.DeliveredTotal);
        Inc(Result.DroppedTotal, lInner.GetStats.DroppedTotal);
        Inc(Result.ExceptionsTotal, lInner.GetStats.ExceptionsTotal);
        if lInner.GetStats.MaxQueueDepth > Result.MaxQueueDepth then
          Result.MaxQueueDepth := lInner.GetStats.MaxQueueDepth;
        Inc(Result.CurrentQueueDepth, lInner.GetStats.CurrentQueueDepth);
      end;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetTotals: TmaxTopicStats;
var
  lObj: TmaxTopicBase;
  lTypeDict: TmaxTypeTopicDict;
  lInner: TmaxTopicBase;
  lGuidObj: TmaxTopicBase;
begin
  FillChar(Result, SizeOf(Result), 0);
  TMonitor.Enter(fLock);
  try
    for lObj in fTyped.Values do
    begin
      Inc(Result.PostsTotal, lObj.GetStats.PostsTotal);
      Inc(Result.DeliveredTotal, lObj.GetStats.DeliveredTotal);
      Inc(Result.DroppedTotal, lObj.GetStats.DroppedTotal);
      Inc(Result.ExceptionsTotal, lObj.GetStats.ExceptionsTotal);
      if lObj.GetStats.MaxQueueDepth > Result.MaxQueueDepth then
        Result.MaxQueueDepth := lObj.GetStats.MaxQueueDepth;
      Inc(Result.CurrentQueueDepth, lObj.GetStats.CurrentQueueDepth);
    end;
    for lObj in fNamed.Values do
    begin
      Inc(Result.PostsTotal, lObj.GetStats.PostsTotal);
      Inc(Result.DeliveredTotal, lObj.GetStats.DeliveredTotal);
      Inc(Result.DroppedTotal, lObj.GetStats.DroppedTotal);
      Inc(Result.ExceptionsTotal, lObj.GetStats.ExceptionsTotal);
      if lObj.GetStats.MaxQueueDepth > Result.MaxQueueDepth then
        Result.MaxQueueDepth := lObj.GetStats.MaxQueueDepth;
      Inc(Result.CurrentQueueDepth, lObj.GetStats.CurrentQueueDepth);
    end;
    for lTypeDict in fNamedTyped.Values do
      for lInner in lTypeDict.Values do
      begin
        Inc(Result.PostsTotal, lInner.GetStats.PostsTotal);
        Inc(Result.DeliveredTotal, lInner.GetStats.DeliveredTotal);
        Inc(Result.DroppedTotal, lInner.GetStats.DroppedTotal);
        Inc(Result.ExceptionsTotal, lInner.GetStats.ExceptionsTotal);
        if lInner.GetStats.MaxQueueDepth > Result.MaxQueueDepth then
          Result.MaxQueueDepth := lInner.GetStats.MaxQueueDepth;
        Inc(Result.CurrentQueueDepth, lInner.GetStats.CurrentQueueDepth);
      end;
    for lGuidObj in fGuid.Values do
    begin
      Inc(Result.PostsTotal, lGuidObj.GetStats.PostsTotal);
      Inc(Result.DeliveredTotal, lGuidObj.GetStats.DeliveredTotal);
      Inc(Result.DroppedTotal, lGuidObj.GetStats.DroppedTotal);
      Inc(Result.ExceptionsTotal, lGuidObj.GetStats.ExceptionsTotal);
      if lGuidObj.GetStats.MaxQueueDepth > Result.MaxQueueDepth then
        Result.MaxQueueDepth := lGuidObj.GetStats.MaxQueueDepth;
      Inc(Result.CurrentQueueDepth, lGuidObj.GetStats.CurrentQueueDepth);
    end;
  finally
    TMonitor.exit(fLock);
  end;
end;

function TmaxBus.GetSelf: TObject;
begin
  Result := self;
end;

{$IFDEF max_FPC}
function ImaxBusHelper.Impl: TmaxBus;
var
  X: ImaxBusImpl;
begin
  if not Supports(self, ImaxBusImpl, X) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(X.GetSelf);
end;

function ImaxBusHelper.Subscribe<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.Subscribe<t>(aHandler, aMode);
end;

function ImaxBusHelper.Subscribe<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.Subscribe<t>(aHandler, aMode);
end;

procedure ImaxBusHelper.Post<t>(const aEvent: t);
begin
  Impl.Post<t>(aEvent);
end;

function ImaxBusHelper.TryPost<t>(const aEvent: t): boolean;
begin
  Result := Impl.TryPost<t>(aEvent);
end;

function ImaxBusHelper.SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.SubscribeNamedOf<t>(aName, aHandler, aMode);
end;

function ImaxBusHelper.SubscribeNamedOf<t>(const aName: TmaxString; const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.SubscribeNamedOf<t>(aName, aHandler, aMode);
end;

procedure ImaxBusHelper.PostNamedOf<t>(const aName: TmaxString; const aEvent: t);
begin
  Impl.PostNamedOf<t>(aName, aEvent);
end;

function ImaxBusHelper.TryPostNamedOf<t>(const aName: TmaxString; const aEvent: t): boolean;
begin
  Result := Impl.TryPostNamedOf<t>(aName, aEvent);
end;

function ImaxBusHelper.SubscribeGuidOf<t>(const aHandler: TmaxProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.SubscribeGuidOf<t>(aHandler, aMode);
end;

function ImaxBusHelper.SubscribeGuidOf<t>(const aHandler: TmaxObjProcOf<t>; aMode: TmaxDelivery): ImaxSubscription;
begin
  Result := Impl.SubscribeGuidOf<t>(aHandler, aMode);
end;

procedure ImaxBusHelper.PostGuidOf<t>(const aEvent: t);
begin
  Impl.PostGuidOf<t>(aEvent);
end;

procedure ImaxBusHelper.EnableSticky<t>(aEnable: boolean);
begin
  Impl.EnableSticky<t>(aEnable);
end;

function ImaxBusAdvancedHelper.Impl: TmaxBus;
var
  X: ImaxBusImpl;
begin
  if not Supports(self, ImaxBusImpl, X) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(X.GetSelf);
end;

procedure ImaxBusAdvancedHelper.EnableCoalesceOf<t>(const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
begin
  Impl.EnableCoalesceOf<t>(aKeyOf, aWindowUs);
end;

procedure ImaxBusAdvancedHelper.EnableCoalesceNamedOf<t>(const aName: string; const aKeyOf: TmaxKeyFunc<t>; aWindowUs: integer);
begin
  Impl.EnableCoalesceNamedOf<t>(aName, aKeyOf, aWindowUs);
end;

function ImaxBusQueuesHelper.Impl: TmaxBus;
var
  X: ImaxBusImpl;
begin
  if not Supports(self, ImaxBusImpl, X) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(X.GetSelf);
end;

procedure ImaxBusQueuesHelper.SetPolicyFor<t>(const aPolicy: TmaxQueuePolicy);
begin
  Impl.SetPolicyFor<t>(aPolicy);
end;

function ImaxBusQueuesHelper.GetPolicyFor<t>: TmaxQueuePolicy;
begin
  Result := Impl.GetPolicyFor<t>;
end;

function ImaxBusMetricsHelper.Impl: TmaxBus;
var
  X: ImaxBusImpl;
begin
  if not Supports(self, ImaxBusImpl, X) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := TmaxBus(X.GetSelf);
end;

function ImaxBusMetricsHelper.GetStatsFor<t>: TmaxTopicStats;
begin
  Result := Impl.GetStatsFor<t>;
end;
{$ENDIF}

{$IFDEF max_DELPHI}
function maxAsBus(const aIntf: IInterface): TObject;
var
  X: ImaxBusImpl;
begin
  if not Supports(aIntf, ImaxBusImpl, X) then
    raise Exception.Create(SInvalidBusImplementation);
  Result := X.GetSelf;
end;
{$ENDIF}

initialization
  {$IFDEF max_FPC}
  gFpcWeakRegistry := TFpcWeakRegistry.Create;
  {$ENDIF}

finalization
  {$IFDEF max_FPC}
  FreeAndNil(gFpcWeakRegistry);
  {$ENDIF}

end.

