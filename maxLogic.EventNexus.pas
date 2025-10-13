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
  {$IFDEF max_FPC}
  Generics.Collections, TypInfo, maxLogic.EventNexus.Threading.Adapter, maxlogic.fpc.diagnostics, maxlogic.fpc.compatibility
  {$ELSE}
  System.Generics.Collections, System.TypInfo, maxLogic.EventNexus.Threading.Adapter, System.Diagnostics
  {$ENDIF};

const
  max_BUS_VERSION = '0.1.0';

type
  TmaxString = type UnicodeString;

{$IFDEF max_FPC}
  TmaxKeyFunc<T> = function(const aValue: T): TmaxString is nested;
{$ELSE}
  TmaxKeyFunc<T> = reference to function(const aValue: T): TmaxString;
{$ENDIF}

{$IFDEF max_FPC}
  type
    TmaxProc = procedure is nested;
    TmaxProcOf<T> = procedure(const aValue: T) is nested;
{$ELSE}
  type
    TmaxProc = reference to procedure;
    TmaxProcOf<T> = reference to procedure(const aValue: T);
{$ENDIF}

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
    function IsActive: Boolean;
  end;

  ImaxBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): Boolean; overload;
    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
  end;

  ImaxBusAdvanced = interface(ImaxBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
  end;

  TmaxQueuePolicy = record
    MaxDepth: Integer;
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

  ImaxSubscriptionState = interface
    ['{6B8BCC86-7AC3-4B6F-9CF9-2F3EE0A5F913}']
    function TryEnter: Boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: Boolean;
  end;

  TmaxSubscriptionState = class(TInterfacedObject, ImaxSubscriptionState)
  private
    fActive: Boolean;
    fInFlight: Integer;
  public
    constructor Create;
    function TryEnter: Boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: Boolean;
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
  protected
    fQueue: TmaxProcQueue;
    fProcessing: Boolean;
    fSticky: Boolean;
    fPolicy: TmaxQueuePolicy;
    fStats: TmaxTopicStats;
    fMetricName: TmaxString;
    fWarnedHighWater: Boolean;
    procedure TouchMetrics;
    procedure CheckHighWater; inline;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMetricName(const aName: TmaxString); inline;
    function Enqueue(const aProc: TmaxProc): Boolean;
    procedure RemoveByTarget(const aTarget: TObject); virtual; abstract;
    procedure SetSticky(aEnable: Boolean); virtual;
    procedure SetPolicy(const aPolicy: TmaxQueuePolicy);
    function GetPolicy: TmaxQueuePolicy;
    procedure AddPost; inline;
    procedure AddDelivered(aCount: Integer); inline;
    procedure AddDropped; inline;
    procedure AddException; inline;
    function GetStats: TmaxTopicStats; inline;
  end;

{$IFDEF max_FPC}
  TmaxTypeTopicBaseDict = specialize TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxTypeTopicDict = specialize TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxNameTopicDict = specialize TObjectDictionary<TmaxString, TmaxTopicBase>;
  TmaxNameTypeTopicDict = specialize TObjectDictionary<TmaxString, TmaxTypeTopicBaseDict>;
  TmaxGuidTopicDict = specialize TObjectDictionary<TGuid, TmaxTopicBase>;
  TmaxBoolDictOfTypeInfo = specialize TDictionary<PTypeInfo, Boolean>;
  TmaxBoolDictOfString = specialize TDictionary<TmaxString, Boolean>;
  TmaxSubList = specialize TList<ImaxSubscription>;
  TmaxAutoSubDict = specialize TObjectDictionary<TObject, TmaxSubList>;
{$ELSE}
  TmaxTypeTopicDict = TObjectDictionary<PTypeInfo, TmaxTopicBase>;
  TmaxNameTopicDict = TObjectDictionary<TmaxString, TmaxTopicBase>;
  TmaxNameTypeTopicDict = TObjectDictionary<TmaxString, TObjectDictionary<PTypeInfo, TmaxTopicBase>>;
  TmaxGuidTopicDict = TObjectDictionary<TGuid, TmaxTopicBase>;
  TmaxBoolDictOfTypeInfo = TDictionary<PTypeInfo, Boolean>;
  TmaxBoolDictOfString = TDictionary<TmaxString, Boolean>;
  TmaxSubList = TList<ImaxSubscription>;
  TmaxAutoSubDict = TObjectDictionary<TObject, TmaxSubList>;
{$ENDIF}

  TmaxSubscriptionToken = UInt64;

  TmaxWeakTarget = record
    Raw: TObject;
{$IFDEF max_DELPHI}
    // no extra fields on Delphi; fallback to raw pointer only
{$ELSE}
    Generation: UInt32;
{$ENDIF}
    class function Create(const aObj: TObject): TmaxWeakTarget; static;
    function Matches(const aObj: TObject): Boolean;
    function IsAlive: Boolean;
  end;

  TTypedSubscriber<T> = record
    Handler: TmaxProcOf<T>;
    Mode: TmaxDelivery;
    Token: TmaxSubscriptionToken;
    Target: TmaxWeakTarget;
    State: ImaxSubscriptionState;
  end;

  TTypedTopic<T> = class(TmaxTopicBase)
  private
    fSubs: TArray<TTypedSubscriber<T>>;
    fLast: T;
    fHasLast: Boolean;
    fCoalesce: Boolean;
    fKeyFunc: TmaxKeyFunc<T>;
    fWindowUs: Integer;
    fPending: {$IFDEF max_FPC}specialize{$ENDIF} TDictionary<TmaxString, T>;
    fPendingLock: TmaxMonitorObject;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDead;
  public
    constructor Create;
    function Add(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TTypedSubscriber<T>>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: Boolean); override;
    procedure Cache(const aEvent: T);
    function TryGetCached(out aEvent: T): Boolean;
    procedure SetCoalesce(const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer);
    function HasCoalesce: Boolean;
    function CoalesceKey(const aEvent: T): TmaxString;
    function AddOrUpdatePending(const aKey: TmaxString; const aEvent: T): Boolean;
    function PopPending(const aKey: TmaxString; out aEvent: T): Boolean;
    function CoalesceWindow: Integer;
    destructor Destroy; override;
  end;


  TmaxBus = class(TInterfacedObject, ImaxBus, ImaxBusAdvanced, ImaxBusQueues, ImaxBusMetrics)
  private
    fAsync: IEventNexusScheduler;
    fLock: TmaxMonitorObject;
    fTyped: TmaxTypeTopicDict;
    fNamed: TmaxNameTopicDict;
    fNamedTyped: TmaxNameTypeTopicDict;
    fGuid: TmaxGuidTopicDict;
    fStickyTypes: TmaxBoolDictOfTypeInfo;
    fStickyNames: TmaxBoolDictOfString;
    function ScheduleTypedCoalesce<T>(const aTopicName: TmaxString;
      aTopic: TTypedTopic<T>; const aSubs: TArray<TTypedSubscriber<T>>;
      const aKey: TmaxString): Boolean;
  public
      function Subscribe<T>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
      procedure Post<T>(const aEvent: T);
      function TryPost<T>(const aEvent: T): Boolean; overload;

      function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
      procedure PostNamed(const aName: TmaxString);
      function TryPostNamed(const aName: TmaxString): Boolean; overload;

      function SubscribeNamedOf<T>(const aName: TmaxString; const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
      procedure PostNamedOf<T>(const aName: TmaxString; const aEvent: T);
      function TryPostNamedOf<T>(const aName: TmaxString; const aEvent: T): Boolean; overload;

      function SubscribeGuidOf<T: IInterface>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = TmaxDelivery.Posting): ImaxSubscription;
      procedure PostGuidOf<T: IInterface>(const aEvent: T);
      procedure UnsubscribeAllFor(const aTarget: TObject);
      procedure Clear;
      procedure EnableSticky<T>(aEnable: Boolean);
      procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
      procedure EnableCoalesceOf<T>(const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer = 0);
      procedure EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer = 0);
      procedure SetPolicyFor<T>(const aPolicy: TmaxQueuePolicy);
      procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
      function GetPolicyFor<T>: TmaxQueuePolicy;
      function GetPolicyNamed(const aName: string): TmaxQueuePolicy;
      function GetStatsFor<T>: TmaxTopicStats;
      function GetStatsNamed(const aName: string): TmaxTopicStats;
      function GetTotals: TmaxTopicStats;
  public
    constructor Create(const aAsync: IEventNexusScheduler);
    destructor Destroy; override;
    procedure Dispatch(const aTopic: TmaxString; aDelivery: TmaxDelivery; const aHandler: TmaxProc; const aOnException: TmaxProc = nil);
  end;

implementation
uses
  maxLogic.EventNexus.Threading.RawThread
  {$IFDEF max_FPC}, SyncObjs{$ENDIF};

{$IFDEF max_DELPHI}
type
  TProcThunk = class
  private
    FProc: TmaxProc;
  public
    constructor Create(const AProc: TmaxProc);
    procedure Invoke;
  end;

constructor TProcThunk.Create(const AProc: TmaxProc);
begin
  inherited Create;
  FProc := AProc;
end;

procedure TProcThunk.Invoke;
begin
  try
    FProc();
  finally
    Free;
  end;
end;
{$ENDIF}

var
  gAsyncError: TOnAsyncError = nil;
  gMetricSample: TOnMetricSample = nil;
  gBus: ImaxBus = nil;
  gAsyncScheduler: IEventNexusScheduler = nil;
  gAsyncFallback: IEventNexusScheduler = nil;

{$IFDEF max_FPC}
type
  TFpcWeakEntry = record
    Generation: UInt32;
    Alive: Boolean;
  end;

  TmaxObjectAccess = class(TObject);

  TFpcWeakRegistry = class
  private
    type
      TFreeInstanceThunk = procedure(Self: TObject);
    fEntries: specialize TDictionary<TObject, TFpcWeakEntry>;
    fHooks: specialize TDictionary<TClass, Pointer>;
    fLock: TCriticalSection;
    function EnsureHook(const aObj: TObject): Boolean;
    function LocateFreeInstanceSlot(const aClass: TClass; const aOrig: Pointer): PPointer;
    function PrepareFreeInstance(const aObj: TObject): Pointer;
  public
    constructor Create;
    destructor Destroy; override;
    function Observe(const aObj: TObject): UInt32;
    function IsAlive(const aObj: TObject; const aGeneration: UInt32): Boolean;
    class function Instance: TFpcWeakRegistry; static;
  end;

var
  gFpcWeakRegistry: TFpcWeakRegistry = nil;

procedure FpcWeakFreeInstanceHook(Self: TObject); forward;
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
  lIdx: Integer;
const
  SEARCH_LIMIT = 128;
begin
  lVmt := PPointer(aClass);
  for lIdx := 0 to SEARCH_LIMIT do
  begin
    if (lVmt + lIdx)^ = aOrig then
      Exit(lVmt + lIdx);
  end;
  Result := nil;
end;

function TFpcWeakRegistry.EnsureHook(const aObj: TObject): Boolean;
var
  lClass: TClass;
  lMethod: procedure of object;
  lOrig: Pointer;
  lSlot: PPointer;
begin
  Result := False;
  if aObj = nil then
    Exit;
  lClass := aObj.ClassType;
  fLock.Enter;
  try
    if fHooks.ContainsKey(lClass) then
      Exit(True);
  finally
    fLock.Leave;
  end;

  lMethod := TmaxObjectAccess(aObj).FreeInstance;
  lOrig := TMethod(lMethod).Code;
  if lOrig = @FpcWeakFreeInstanceHook then
    Exit(True);

  lSlot := LocateFreeInstanceSlot(lClass, lOrig);
  if lSlot = nil then
    Exit(False);

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
    Exit;
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
    Exit(0);
  if not EnsureHook(aObj) then
    Exit(0);
  fLock.Enter;
  try
    if fEntries.TryGetValue(aObj, lEntry) then
    begin
      lEntry.Alive := True;
      fEntries.AddOrSetValue(aObj, lEntry);
      Exit(lEntry.Generation);
    end;
    lEntry.Generation := 1;
    lEntry.Alive := True;
    fEntries.Add(aObj, lEntry);
    Result := lEntry.Generation;
  finally
    fLock.Leave;
  end;
end;

function TFpcWeakRegistry.IsAlive(const aObj: TObject; const aGeneration: UInt32): Boolean;
var
  lEntry: TFpcWeakEntry;
begin
  if (aObj = nil) or (aGeneration = 0) then
    Exit(True);
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

procedure FpcWeakFreeInstanceHook(Self: TObject);
var
  lOrig: Pointer;
begin
  lOrig := TFpcWeakRegistry.Instance.PrepareFreeInstance(Self);
  if lOrig <> nil then
    TFpcWeakRegistry.TFreeInstanceThunk(lOrig)(Self);
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
  inherited CreateFmt('%d exception(s) occurred', [fInner.Count]);
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

function TmaxWeakTarget.Matches(const aObj: TObject): Boolean;
begin
  Result := (Raw <> nil) and (Raw = aObj);
end;

function TmaxWeakTarget.IsAlive: Boolean;
begin
  if Raw = nil then
    Exit(True);
{$IFDEF max_DELPHI}
  Result := Assigned(Raw);
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

function TmaxSubscriptionState.TryEnter: Boolean;
begin
  TMonitor.Enter(Self);
  try
    if not fActive then
      Exit(False);
    Inc(fInFlight);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TmaxSubscriptionState.Leave;
begin
  TMonitor.Enter(Self);
  try
    if fInFlight > 0 then
      Dec(fInFlight);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TmaxSubscriptionState.Deactivate;
begin
  TMonitor.Enter(Self);
  try
    if fActive then
      fActive := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TmaxSubscriptionState.IsActive: Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fActive;
  finally
    TMonitor.Exit(Self);
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

procedure TmaxTopicBase.AddDelivered(aCount: Integer);
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

function TmaxTopicBase.Enqueue(const aProc: TmaxProc): Boolean;
var
  lProc: TmaxProc;
  lTimer: TStopwatch;
  lDeadlineMs: Cardinal;
  lRemaining: Integer;
  lElapsedMs: Int64;
begin
  Result := True;
  TMonitor.Enter(Self);
  try
    if (fPolicy.MaxDepth > 0) and (fQueue.Count >= fPolicy.MaxDepth) then
    begin
      case fPolicy.Overflow of
        DropNewest:
        begin
          AddDropped;
          Exit(False);
        end;
        DropOldest:
        begin
          fQueue.Dequeue;
          if fStats.CurrentQueueDepth > 0 then
            Dec(fStats.CurrentQueueDepth);
          AddDropped;
        end;
        Block:
          while fQueue.Count >= fPolicy.MaxDepth do
            TMonitor.Wait(Self, Cardinal(-1));
        Deadline:
          if fPolicy.DeadlineUs <= 0 then
          begin
            while fQueue.Count >= fPolicy.MaxDepth do
              TMonitor.Wait(Self, Cardinal(-1));
          end
          else
          begin
            lDeadlineMs := Cardinal(fPolicy.DeadlineUs div 1000);
            lTimer := TStopwatch.StartNew;
            while fQueue.Count >= fPolicy.MaxDepth do
            begin
              lElapsedMs := lTimer.ElapsedMilliseconds;
              lRemaining := Integer(Int64(lDeadlineMs) - lElapsedMs);
              if lRemaining <= 0 then
              begin
                AddDropped;
                Exit(False);
              end;
              TMonitor.Wait(Self, Cardinal(lRemaining));
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
      Exit(True);
    fProcessing := True;
  finally
    TMonitor.Exit(Self);
  end;
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
      lProc := fQueue.Dequeue;
      if fStats.CurrentQueueDepth > 0 then
        Dec(fStats.CurrentQueueDepth);
      CheckHighWater;
      TouchMetrics;
      TMonitor.Pulse(Self);
    finally
      TMonitor.Exit(Self);
    end;
    lProc();
  end;
end;

procedure TmaxTopicBase.SetSticky(aEnable: Boolean);
begin
  fSticky := aEnable;
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
    fHasLast: Boolean;
    fNextToken: TmaxSubscriptionToken;
    procedure PruneDead;
  public
    function Add(const aHandler: TmaxProc; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
    procedure RemoveByToken(aToken: TmaxSubscriptionToken);
    function Snapshot: TArray<TNamedSubscriber>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: Boolean); override;
    procedure Cache;
    function HasCached: Boolean;
  end;

  TmaxSubscriptionBase = class(TInterfacedObject, ImaxSubscription)
  protected
    fActive: Boolean;
    fState: ImaxSubscriptionState;
  public
    constructor Create(const aState: ImaxSubscriptionState);
    destructor Destroy; override;
    procedure Unsubscribe; virtual; abstract;
    function IsActive: Boolean;
  end;

  TmaxTypedSubscription<T> = class(TmaxSubscriptionBase)
  private
    fTopic: TTypedTopic<T>;
    fToken: TmaxSubscriptionToken;
  public
    constructor Create(aTopic: TTypedTopic<T>; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
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
  Result := aName + ':' + TmaxString(GetTypeName(aInfo));
end;

function GuidMetricName(const aGuid: TGuid): TmaxString; inline;
begin
  Result := TmaxString(GuidToString(aGuid));
end;

{ TTypedTopic<T> }

constructor TTypedTopic<T>.Create;
begin
  inherited Create;
  fPendingLock := TmaxMonitorObject.Create;
  fNextToken := 1;
  SetLength(fSubs, 0);
end;

procedure TTypedTopic<T>.PruneDead;
var
  lNeedsPrune: Boolean;
  lIdx, lCount, lOut: Integer;
  lCopy: TArray<TTypedSubscriber<T>>;
  lKeep: Boolean;
begin
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNeedsPrune := False;
  for lIdx := 0 to lCount - 1 do
    if (not fSubs[lIdx].Target.IsAlive) or
       (Assigned(fSubs[lIdx].State) and not fSubs[lIdx].State.IsActive) then
    begin
      lNeedsPrune := True;
      Break;
    end;
  if not lNeedsPrune then
    Exit;
  SetLength(lCopy, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
  begin
    lKeep := fSubs[lIdx].Target.IsAlive;
    if lKeep and Assigned(fSubs[lIdx].State) then
      lKeep := fSubs[lIdx].State.IsActive;
    if lKeep then
    begin
      lCopy[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  end;
  SetLength(lCopy, lOut);
  fSubs := lCopy;
end;

function TTypedTopic<T>.Add(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery; out aState: ImaxSubscriptionState): TmaxSubscriptionToken;
var
  lNew: TArray<TTypedSubscriber<T>>;
  lSub: TTypedSubscriber<T>;
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
  lNew := Copy(fSubs);
  SetLength(lNew, Length(lNew) + 1);
  lNew[High(lNew)] := lSub;
  fSubs := lNew;
  Result := lSub.Token;
end;

procedure TTypedTopic<T>.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: Integer;
  lNew: TArray<TTypedSubscriber<T>>;
begin
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNew := nil;
  SetLength(lNew, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
    if fSubs[lIdx].Token <> aToken then
    begin
      lNew[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  if lOut = lCount then
  begin
    SetLength(lNew, 0);
    Exit;
  end;
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

function TTypedTopic<T>.Snapshot: TArray<TTypedSubscriber<T>>;
begin
  PruneDead;
  Result := Copy(fSubs);
end;

procedure TTypedTopic<T>.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: Integer;
  lNew: TArray<TTypedSubscriber<T>>;
begin
  if aTarget = nil then
    Exit;
  PruneDead;
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNew := nil;
  SetLength(lNew, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
    if not fSubs[lIdx].Target.Matches(aTarget) then
    begin
      lNew[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

procedure TTypedTopic<T>.SetSticky(aEnable: Boolean);
begin
  inherited SetSticky(aEnable);
  if not aEnable then
    fHasLast := False;
end;

procedure TTypedTopic<T>.Cache(const aEvent: T);
begin
  if fSticky then
  begin
    fLast := aEvent;
    fHasLast := True;
  end;
end;

function TTypedTopic<T>.TryGetCached(out aEvent: T): Boolean;
begin
  Result := fSticky and fHasLast;
  if Result then
    aEvent := fLast;
end;

procedure TTypedTopic<T>.SetCoalesce(const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer);
begin
  fCoalesce := Assigned(aKeyOf);
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
        fPending := specialize TDictionary<TmaxString, T>.Create;
        {$ELSE}
        fPending := TDictionary<TmaxString, T>.Create;
        {$ENDIF}
      end;
    end
    else if fPending <> nil then
    begin
      fPending.Free;
      fPending := nil;
    end;
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

function TTypedTopic<T>.HasCoalesce: Boolean;
begin
  Result := fCoalesce;
end;

function TTypedTopic<T>.CoalesceKey(const aEvent: T): TmaxString;
begin
  if Assigned(fKeyFunc) then
    Result := fKeyFunc(aEvent)
  else
    Result := '';
end;

function TTypedTopic<T>.AddOrUpdatePending(const aKey: TmaxString; const aEvent: T): Boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending = nil then
    begin
      {$IFDEF max_FPC}
      fPending := specialize TDictionary<TmaxString, T>.Create;
      {$ELSE}
      fPending := TDictionary<TmaxString, T>.Create;
      {$ENDIF}
    end;
    Result := not fPending.ContainsKey(aKey);
    fPending.AddOrSetValue(aKey, aEvent);
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

function TTypedTopic<T>.PopPending(const aKey: TmaxString; out aEvent: T): Boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    Result := False;
    if fPending = nil then
      Exit;
    if fPending.TryGetValue(aKey, aEvent) then
    begin
      fPending.Remove(aKey);
      Result := True;
    end;
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

function TTypedTopic<T>.CoalesceWindow: Integer;
begin
  Result := fWindowUs;
end;

destructor TTypedTopic<T>.Destroy;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending <> nil then
      fPending.Free;
    fPending := nil;
  finally
    TMonitor.Exit(fPendingLock);
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
  lNew := Copy(fSubs);
  SetLength(lNew, Length(lNew) + 1);
  lNew[High(lNew)] := lSub;
  fSubs := lNew;
  Result := lSub.Token;
end;

procedure TNamedTopic.RemoveByToken(aToken: TmaxSubscriptionToken);
var
  lCount, lIdx, lOut: Integer;
  lNew: TArray<TNamedSubscriber>;
begin
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNew := nil;
  SetLength(lNew, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
    if fSubs[lIdx].Token <> aToken then
    begin
      lNew[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  if lOut = lCount then
  begin
    SetLength(lNew, 0);
    Exit;
  end;
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

procedure TNamedTopic.PruneDead;
var
  lNeedsPrune: Boolean;
  lIdx, lCount, lOut: Integer;
  lCopy: TArray<TNamedSubscriber>;
  lKeep: Boolean;
begin
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNeedsPrune := False;
  for lIdx := 0 to lCount - 1 do
    if (not fSubs[lIdx].Target.IsAlive) or
       (Assigned(fSubs[lIdx].State) and not fSubs[lIdx].State.IsActive) then
    begin
      lNeedsPrune := True;
      Break;
    end;
  if not lNeedsPrune then
    Exit;
  SetLength(lCopy, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
  begin
    lKeep := fSubs[lIdx].Target.IsAlive;
    if lKeep and Assigned(fSubs[lIdx].State) then
      lKeep := fSubs[lIdx].State.IsActive;
    if lKeep then
    begin
      lCopy[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  end;
  SetLength(lCopy, lOut);
  fSubs := lCopy;
end;

function TNamedTopic.Snapshot: TArray<TNamedSubscriber>;
begin
  PruneDead;
  Result := Copy(fSubs);
end;

procedure TNamedTopic.RemoveByTarget(const aTarget: TObject);
var
  lCount, lIdx, lOut: Integer;
  lNew: TArray<TNamedSubscriber>;
begin
  if aTarget = nil then
    Exit;
  PruneDead;
  lCount := Length(fSubs);
  if lCount = 0 then
    Exit;
  lNew := nil;
  SetLength(lNew, lCount);
  lOut := 0;
  for lIdx := 0 to lCount - 1 do
    if not fSubs[lIdx].Target.Matches(aTarget) then
    begin
      lNew[lOut] := fSubs[lIdx];
      Inc(lOut);
    end
    else if Assigned(fSubs[lIdx].State) then
      fSubs[lIdx].State.Deactivate;
  SetLength(lNew, lOut);
  fSubs := lNew;
end;

procedure TNamedTopic.SetSticky(aEnable: Boolean);
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

function TNamedTopic.HasCached: Boolean;
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

function TmaxSubscriptionBase.IsActive: Boolean;
begin
  Result := fActive and Assigned(fState) and fState.IsActive;
end;

{ TmaxTypedSubscription<T> }

constructor TmaxTypedSubscription<T>.Create(aTopic: TTypedTopic<T>; aToken: TmaxSubscriptionToken; const aState: ImaxSubscriptionState);
begin
  inherited Create(aState);
  fTopic := aTopic;
  fToken := aToken;
end;

procedure TmaxTypedSubscription<T>.Unsubscribe;
begin
  if fActive then
  begin
    if Assigned(fState) then
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
    if Assigned(fState) then
      fState.Deactivate;
    fTopic.RemoveByToken(fToken);
    fState := nil;
    fActive := False;
  end;
end;

function DefaultAsync: IEventNexusScheduler;
begin
  if gAsyncScheduler <> nil then
    Exit(gAsyncScheduler);
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


function TmaxBus.ScheduleTypedCoalesce<T>(const aTopicName: TmaxString;
  aTopic: TTypedTopic<T>; const aSubs: TArray<TTypedSubscriber<T>>;
  const aKey: TmaxString): Boolean;
var
  lKeyCopy: TmaxString;
begin
  lKeyCopy := aKey;
  Result := aTopic.Enqueue(
    procedure
    var
      lPendingKey: TmaxString;
    begin
      lPendingKey := lKeyCopy;
{$IFDEF max_DELPHI}
      fAsync.RunDelayed(
        TProcThunk.Create(
          procedure
          var
            lSub: TTypedSubscriber<T>;
            lInner: T;
            lErrs: TmaxExceptionList;
            ex: EmaxAggregateException;
          begin
            if not aTopic.PopPending(lPendingKey, lInner) then
              Exit;
            lErrs := nil;
            for lSub in aSubs do
            begin
              if (lSub.State = nil) or not lSub.State.TryEnter then
                Continue;
              try
                if not lSub.Target.IsAlive then
                begin
                  aTopic.RemoveByToken(lSub.Token);
                  Continue;
                end;
                try
                  Dispatch(aTopicName, lSub.Mode,
                    procedure
                    begin
                      try
                        lSub.Handler(lInner);
                        aTopic.AddDelivered(1);
                      except
                        on e: Exception do
                        begin
                          if (e is EAccessViolation) or (e is EInvalidPointer) then
                            aTopic.RemoveByToken(lSub.Token);
                          raise;
                        end;
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
                    lErrs.Add(e);
                  end;
                end;
              finally
                lSub.State.Leave;
              end;
            end;
            if lErrs <> nil then
            begin
              // Forward async errors via global hook; avoid unhandled exception in scheduler thread.
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
          end).Invoke,
        aTopic.CoalesceWindow);
{$ELSE}
      fAsync.RunDelayed(
        procedure
        var
          lSub: TTypedSubscriber<T>;
          lInner: T;
          lErrs: TmaxExceptionList;
          ex: EmaxAggregateException;
        begin
          if not aTopic.PopPending(lPendingKey, lInner) then
            Exit;
          lErrs := nil;
          for lSub in aSubs do
          begin
            if (lSub.State = nil) or not lSub.State.TryEnter then
              Continue;
            try
              if not lSub.Target.IsAlive then
              begin
                aTopic.RemoveByToken(lSub.Token);
                Continue;
              end;
              try
                Dispatch(aTopicName, lSub.Mode,
                  procedure
                  begin
                    try
                      lSub.Handler(lInner);
                      aTopic.AddDelivered(1);
                    except
                      on e: Exception do
                      begin
                        if (e is EAccessViolation) or (e is EInvalidPointer) then
                          aTopic.RemoveByToken(lSub.Token);
                        raise;
                      end;
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
                  lErrs.Add(e);
                end;
              end;
            finally
              lSub.State.Leave;
            end;
          end;
          if lErrs <> nil then
          begin
            // Forward async errors via global hook; avoid unhandled exception in scheduler thread.
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
{$ENDIF}
    end);
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
{$IFDEF max_DELPHI}
      fAsync.RunOnMain(
        TProcThunk.Create(
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
          end).Invoke);
{$ELSE}
      fAsync.RunOnMain(
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
{$ENDIF}
    Async:
{$IFDEF max_DELPHI}
      fAsync.RunAsync(
        TProcThunk.Create(
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
          end).Invoke);
{$ELSE}
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
{$ENDIF}
    Background:
      if fAsync.IsMainThread then
{$IFDEF max_DELPHI}
        fAsync.RunAsync(
          TProcThunk.Create(
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
            end).Invoke)
{$ELSE}
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
{$ENDIF}
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

function TmaxBus.Subscribe<T>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery): ImaxSubscription;
var
  key: PTypeInfo;
  obj: TmaxTopicBase;
  topic: TTypedTopic<T>;
  token: TmaxSubscriptionToken;
  send: Boolean;
  last: T;
  metricName: TmaxString;
  lState: ImaxSubscriptionState;
begin
  key := TypeInfo(T);
  metricName := TypeMetricName(key);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      topic.SetMetricName(metricName);
      if fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      fTyped.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    topic.SetMetricName(metricName);
    token := topic.Add(aHandler, aMode, lState);
    send := topic.TryGetCached(last);
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      var
        val: T;
      begin
        val := last;
        if (lState = nil) or not lState.TryEnter then
          Exit;
        try
          Dispatch(metricName, aMode,
            procedure
            begin
              try
                aHandler(val);
                topic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                    topic.RemoveByToken(token);
                  raise;
                end;
              end;
            end,
            procedure
            begin
              topic.AddException;
            end);
        finally
          lState.Leave;
        end;
      end);
  Result := TmaxTypedSubscription<T>.Create(topic, token, lState);
end;

procedure TmaxBus.Post<T>(const aEvent: T);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TmaxString;
  lDropVal: T;
  lMetric: TmaxString;
begin
  lKey := TypeInfo(T);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
  lTopic.AddPost;
  if Length(lSubs) = 0 then
    Exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      Exit;
    if not ScheduleTypedCoalesce<T>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    Exit;
  end;
  if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TmaxExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
      begin
        if (lSub.State = nil) or not lSub.State.TryEnter then
          Continue;
        try
          if not lSub.Target.IsAlive then
          begin
            lTopic.RemoveByToken(lSub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, lSub.Mode,
              procedure
              begin
                try
                  lSub.Handler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lSub.Token);
                    raise;
                  end;
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
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;

function TmaxBus.TryPost<T>(const aEvent: T): Boolean;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TmaxString;
  lDropVal: T;
  lMetric: TmaxString;
begin
  Result := True;
  lKey := TypeInfo(T);
  lMetric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
  lTopic.AddPost;
  if Length(lSubs) = 0 then
    Exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      Exit;
    Result := ScheduleTypedCoalesce<T>(lMetric, lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    Exit;
  end;
  Result := lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TmaxExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
      begin
        if (lSub.State = nil) or not lSub.State.TryEnter then
          Continue;
        try
          if not lSub.Target.IsAlive then
          begin
            lTopic.RemoveByToken(lSub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, lSub.Mode,
              procedure
              begin
                try
                  lSub.Handler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lSub.Token);
                    raise;
                  end;
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
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
  if not Result then
    lTopic.AddDropped;
end;

function TmaxBus.SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery): ImaxSubscription;
var
  obj: TmaxTopicBase;
  topic: TNamedTopic;
  token: TmaxSubscriptionToken;
  send: Boolean;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      topic := TNamedTopic.Create;
      topic.SetMetricName(lMetric);
      if fStickyNames.ContainsKey(lNameKey) then
        topic.SetSticky(True);
      fNamed.Add(lNameKey, topic);
    end
    else
      topic := TNamedTopic(obj);
    topic.SetMetricName(lMetric);
    token := topic.Add(aHandler, aMode, lState);
    send := topic.HasCached;
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      begin
        if (lState = nil) or not lState.TryEnter then
          Exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                aHandler();
                topic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                    topic.RemoveByToken(token);
                  raise;
                end;
              end;
            end,
            procedure
            begin
              topic.AddException;
            end);
        finally
          lState.Leave;
        end;
      end);
  Result := TmaxNamedSubscription.Create(topic, token, lState);
end;


procedure TmaxBus.PostNamed(const aName: TmaxString);
var
  obj: TmaxTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetMetricName(lMetric);
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
      end
      else
        Exit;
    end
    else
      topic := TNamedTopic(obj);
    topic.SetMetricName(lMetric);
    subs := topic.Snapshot;
    topic.Cache;
  finally
    TMonitor.Exit(fLock);
  end;
  topic.AddPost;
  if Length(subs) = 0 then
    Exit;
  if not topic.Enqueue(
    procedure
    var
      sub: TNamedSubscriber;
      lErrs: TmaxExceptionList;
    begin
      lErrs := nil;
      for sub in subs do
      begin
        if (sub.State = nil) or not sub.State.TryEnter then
          Continue;
        try
          if not sub.Target.IsAlive then
          begin
            topic.RemoveByToken(sub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, sub.Mode,
              procedure
              begin
                try
                  sub.Handler();
                  topic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      topic.RemoveByToken(sub.Token);
                    raise;
                  end;
                end;
              end,
              procedure
              begin
                topic.AddException;
              end);
          except
            on e: Exception do
            begin
              if lErrs = nil then
                lErrs := TmaxExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          sub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end) then
    topic.AddDropped;
end;


function TmaxBus.TryPostNamed(const aName: TmaxString): Boolean;
var
  obj: TmaxTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TmaxString;
  lMetric: TmaxString;
begin
  Result := True;
  lNameKey := NormalizeName(aName);
  lMetric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetMetricName(lMetric);
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
        topic.Cache;
      end;
      Exit;
    end;
    topic := TNamedTopic(obj);
    topic.SetMetricName(lMetric);
    subs := topic.Snapshot;
    topic.Cache;
  finally
    TMonitor.Exit(fLock);
  end;
  topic.AddPost;
  if Length(subs) = 0 then
    Exit;
  if not topic.Enqueue(
    procedure
    var
      sub: TNamedSubscriber;
      lErrs: TmaxExceptionList;
    begin
      lErrs := nil;
      for sub in subs do
      begin
        if (sub.State = nil) or not sub.State.TryEnter then
          Continue;
        try
          if not sub.Target.IsAlive then
          begin
            topic.RemoveByToken(sub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, sub.Mode,
              procedure
              begin
                try
                  sub.Handler();
                  topic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      topic.RemoveByToken(sub.Token);
                    raise;
                  end;
                end;
              end,
              procedure
              begin
                topic.AddException;
              end);
          except
            on e: Exception do
            begin
              if lErrs = nil then
                lErrs := TmaxExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          sub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end) then
  begin
    topic.AddDropped;
    Result := False;
  end;
end;


function TmaxBus.SubscribeNamedOf<T>(const aName: TmaxString; const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery): ImaxSubscription;
var
  typeDict: TmaxTypeTopicDict;
  obj: TmaxTopicBase;
  topic: TTypedTopic<T>;
  token: TmaxSubscriptionToken;
  key: PTypeInfo;
  send: Boolean;
  last: T;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, typeDict) then
    begin
      typeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, typeDict);
    end;
    if not typeDict.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      topic.SetMetricName(lMetric);
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      typeDict.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    topic.SetMetricName(lMetric);
    token := topic.Add(aHandler, aMode, lState);
    send := topic.TryGetCached(last);
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      var
        val: T;
      begin
        val := last;
        if (lState = nil) or not lState.TryEnter then
          Exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                aHandler(val);
                topic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                    topic.RemoveByToken(token);
                  raise;
                end;
              end;
            end,
            procedure
            begin
              topic.AddException;
            end);
        finally
          lState.Leave;
        end;
      end);
  Result := TmaxTypedSubscription<T>.Create(topic, token, lState);
end;


procedure TmaxBus.PostNamedOf<T>(const aName: TmaxString; const aEvent: T);
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TmaxString;
  lDropVal: T;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  key: PTypeInfo;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
      begin
        lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end
      else
        Exit;
    end;
    if not lTypeDict.TryGetValue(key, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        lTypeDict.Add(key, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
  lTopic.AddPost;
  if Length(lSubs) = 0 then
    Exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      Exit;
    if not ScheduleTypedCoalesce<T>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    Exit;
  end;
  if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TmaxExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
      begin
        if (lSub.State = nil) or not lSub.State.TryEnter then
          Continue;
        try
          if not lSub.Target.IsAlive then
          begin
            lTopic.RemoveByToken(lSub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, lSub.Mode,
              procedure
              begin
                try
                  lSub.Handler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lSub.Token);
                    raise;
                  end;
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
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;


function TmaxBus.TryPostNamedOf<T>(const aName: TmaxString; const aEvent: T): Boolean;
var
  lTypeDict: TmaxTypeTopicDict;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TmaxString;
  lDropVal: T;
  lNameKey: TmaxString;
  lMetric: TmaxString;
  key: PTypeInfo;
begin
  Result := True;
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
      begin
        lTypeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end;
      Exit;
    end;
    if not lTypeDict.TryGetValue(key, lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        lTypeDict.Add(key, lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
  lTopic.AddPost;
  if Length(lSubs) = 0 then
    Exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      Exit;
    Result := ScheduleTypedCoalesce<T>(lMetric, lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
    Exit;
  end;
  Result := lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TmaxExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
      begin
        if (lSub.State = nil) or not lSub.State.TryEnter then
          Continue;
        try
          if not lSub.Target.IsAlive then
          begin
            lTopic.RemoveByToken(lSub.Token);
            Continue;
          end;
          try
            Dispatch(lMetric, lSub.Mode,
              procedure
              begin
                try
                  lSub.Handler(lVal);
                  lTopic.AddDelivered(1);
                except
                  on e: Exception do
                  begin
                    if (e is EAccessViolation) or (e is EInvalidPointer) then
                      lTopic.RemoveByToken(lSub.Token);
                    raise;
                  end;
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
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end);
  if not Result then
    lTopic.AddDropped;
end;


function TmaxBus.SubscribeGuidOf<T>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery): ImaxSubscription;
var
  key: TGuid;
  obj: TmaxTopicBase;
  topic: TTypedTopic<T>;
  token: TmaxSubscriptionToken;
  send: Boolean;
  last: T;
  lMetric: TmaxString;
  lState: ImaxSubscriptionState;
begin
  key := GetTypeData(TypeInfo(T))^.Guid;
  lMetric := GuidMetricName(key);
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      topic.SetMetricName(lMetric);
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
        topic.SetSticky(True);
      fGuid.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    topic.SetMetricName(lMetric);
    token := topic.Add(aHandler, aMode, lState);
    send := topic.TryGetCached(last);
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      var
        val: T;
      begin
        val := last;
        if (lState = nil) or not lState.TryEnter then
          Exit;
        try
          Dispatch(lMetric, aMode,
            procedure
            begin
              try
                aHandler(val);
                topic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                    topic.RemoveByToken(token);
                  raise;
                end;
              end;
            end,
            procedure
            begin
              topic.AddException;
            end);
        finally
          lState.Leave;
        end;
      end);
  Result := TmaxTypedSubscription<T>.Create(topic, token, lState);
end;


procedure TmaxBus.PostGuidOf<T>(const aEvent: T);
var
  lKey: TGuid;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TmaxString;
  lDrop: T;
  lMetric: TmaxString;
begin
  lKey := GetTypeData(TypeInfo(T))^.Guid;
  lMetric := GuidMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetMetricName(lMetric);
        lTopic.SetSticky(True);
        fGuid.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(lMetric);
    lSubs := lTopic.Snapshot;
    lTopic.Cache(aEvent);
    if lTopic.HasCoalesce then
    begin
      lKeyStr := lTopic.CoalesceKey(aEvent);
      lIsNew := lTopic.AddOrUpdatePending(lKeyStr, aEvent);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
  lTopic.AddPost;
  if Length(lSubs) = 0 then
    Exit;
  if lTopic.HasCoalesce then
  begin
    if not lIsNew then
      Exit;
    if not ScheduleTypedCoalesce<T>(lMetric, lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDrop);
    end;
    Exit;
  end;
  if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TmaxExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
      begin
        if not lSub.Target.IsAlive then
        begin
          lTopic.RemoveByToken(lSub.Token);
          Continue;
        end;
        try
          Dispatch(lMetric, lSub.Mode,
            procedure
            begin
              try
                lSub.Handler(lVal);
                lTopic.AddDelivered(1);
              except
                on e: Exception do
                begin
                  if (e is EAccessViolation) or (e is EInvalidPointer) then
                    lTopic.RemoveByToken(lSub.Token);
                  raise;
                end;
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
            lErrs.Add(e);
          end;
        end;
      end;
      if lErrs <> nil then
        raise EmaxAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;

procedure TmaxBus.EnableSticky<T>(aEnable: Boolean);
var
  key: PTypeInfo;
  obj: TmaxTopicBase;
{$IFDEF max_FPC}
  kvName: specialize TPair<TmaxString, TmaxTypeTopicDict>;
  kvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
{$ELSE}
  kvName: TPair<TmaxString, TmaxTypeTopicDict>;
  kvInner: TPair<PTypeInfo, TmaxTopicBase>;
{$ENDIF}
  guid: TGuid;
  metric: TmaxString;
begin
  key := TypeInfo(T);
  metric := TypeMetricName(key);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyTypes.AddOrSetValue(key, True)
    else
      fStickyTypes.Remove(key);
    if fTyped.TryGetValue(key, obj) then
    begin
      obj.SetMetricName(metric);
      obj.SetSticky(aEnable);
    end;
    for kvName in fNamedTyped do
      if kvName.Value.TryGetValue(key, obj) then
      begin
        obj.SetMetricName(NamedTypeMetricName(kvName.Key, key));
        obj.SetSticky(aEnable);
      end;
    guid := GetTypeData(key)^.Guid;
    if fGuid.TryGetValue(guid, obj) then
    begin
      obj.SetMetricName(GuidMetricName(guid));
      obj.SetSticky(aEnable);
    end;
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.EnableStickyNamed(const aName: string; aEnable: Boolean);
var
  obj: TmaxTopicBase;
  typeDict: TmaxTypeTopicDict;
{$IFDEF max_FPC}
  kvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
{$ELSE}
  kvInner: TPair<PTypeInfo, TmaxTopicBase>;
{$ENDIF}
  lNameKey: TmaxString;
  metric: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  metric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyNames.AddOrSetValue(lNameKey, True)
    else
      fStickyNames.Remove(lNameKey);
    if fNamed.TryGetValue(lNameKey, obj) then
    begin
      obj.SetMetricName(metric);
      obj.SetSticky(aEnable);
    end;
    if fNamedTyped.TryGetValue(lNameKey, typeDict) then
      for kvInner in typeDict do
      begin
        kvInner.Value.SetMetricName(NamedTypeMetricName(lNameKey, kvInner.Key));
        kvInner.Value.SetSticky(aEnable);
      end;
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.EnableCoalesceOf<T>(const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer);
var
  key: PTypeInfo;
  obj: TmaxTopicBase;
  topic: TTypedTopic<T>;
  metric: TmaxString;
begin
  key := TypeInfo(T);
  metric := TypeMetricName(key);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      topic.SetMetricName(metric);
      if fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      fTyped.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    topic.SetMetricName(metric);
    topic.SetCoalesce(aKeyOf, aWindowUs);
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TmaxKeyFunc<T>; aWindowUs: Integer);
var
  typeDict: TmaxTypeTopicDict;
  obj: TmaxTopicBase;
  topic: TTypedTopic<T>;
  lNameKey: TmaxString;
  metric: TmaxString;
  key: PTypeInfo;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  metric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, typeDict) then
    begin
      typeDict := TmaxTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, typeDict);
    end;
    if not typeDict.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      topic.SetMetricName(metric);
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      typeDict.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    topic.SetMetricName(metric);
    topic.SetCoalesce(aKeyOf, aWindowUs);
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.UnsubscribeAllFor(const aTarget: TObject);
var
{$IFDEF max_FPC}
  kvTyped: specialize TPair<PTypeInfo, TmaxTopicBase>;
  kvNamed: specialize TPair<TmaxString, TmaxTopicBase>;
  kvName: specialize TPair<TmaxString, TmaxTypeTopicDict>;
  kvInner: specialize TPair<PTypeInfo, TmaxTopicBase>;
  kvGuid: specialize TPair<TGuid, TmaxTopicBase>;
{$ELSE}
  kvTyped: TPair<PTypeInfo, TmaxTopicBase>;
  kvNamed: TPair<TmaxString, TmaxTopicBase>;
  kvName: TPair<TmaxString, TmaxTypeTopicDict>;
  kvInner: TPair<PTypeInfo, TmaxTopicBase>;
  kvGuid: TPair<TGuid, TmaxTopicBase>;
{$ENDIF}
begin
  if aTarget = nil then
    Exit;
  TMonitor.Enter(fLock);
  try
    for kvTyped in fTyped do
      kvTyped.Value.RemoveByTarget(aTarget);
    for kvNamed in fNamed do
      kvNamed.Value.RemoveByTarget(aTarget);
    for kvName in fNamedTyped do
      for kvInner in kvName.Value do
        kvInner.Value.RemoveByTarget(aTarget);
    for kvGuid in fGuid do
      kvGuid.Value.RemoveByTarget(aTarget);
  finally
    TMonitor.Exit(fLock);
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
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.SetPolicyFor<T>(const aPolicy: TmaxQueuePolicy);
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
  lTopic: TTypedTopic<T>;
  metric: TmaxString;
begin
  lKey := TypeInfo(T);
  metric := TypeMetricName(lKey);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<T>.Create;
      lTopic.SetMetricName(metric);
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<T>(lObj);
    lTopic.SetMetricName(metric);
    lTopic.SetPolicy(aPolicy);
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TmaxBus.SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
var
  lTopic: TmaxTopicBase;
  lNameKey: TmaxString;
  metric: TmaxString;
begin
  lNameKey := NormalizeName(aName);
  metric := NamedMetricName(lNameKey);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lTopic) then
    begin
      lTopic := TNamedTopic.Create;
      TNamedTopic(lTopic).SetMetricName(metric);
      fNamed.Add(lNameKey, lTopic);
    end
    else if lTopic is TNamedTopic then
      TNamedTopic(lTopic).SetMetricName(metric);
    lTopic.SetPolicy(aPolicy);
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxBus.GetPolicyFor<T>: TmaxQueuePolicy;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
begin
  lKey := TypeInfo(T);
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
    TMonitor.Exit(fLock);
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
    TMonitor.Exit(fLock);
  end;
end;

function TmaxBus.GetStatsFor<T>: TmaxTopicStats;
var
  lKey: PTypeInfo;
  lObj: TmaxTopicBase;
begin
  FillChar(Result, SizeOf(Result), 0);
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if fTyped.TryGetValue(lKey, lObj) then
      Result := lObj.GetStats;
  finally
    TMonitor.Exit(fLock);
  end;
end;

function TmaxBus.GetStatsNamed(const aName: string): TmaxTopicStats;
var
  lObj: TmaxTopicBase;
  lNameKey: TmaxString;
begin
  FillChar(Result, SizeOf(Result), 0);
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if fNamed.TryGetValue(lNameKey, lObj) then
      Result := lObj.GetStats;
  finally
    TMonitor.Exit(fLock);
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
    TMonitor.Exit(fLock);
  end;
end;


initialization
{$IFDEF max_FPC}
  gFpcWeakRegistry := TFpcWeakRegistry.Create;
{$ENDIF}

finalization
{$IFDEF max_FPC}
  FreeAndNil(gFpcWeakRegistry);
{$ENDIF}

end.
