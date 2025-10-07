unit maxLogic.EventNexus;

{$I fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE ML_FPC}
{$ELSE}
  {$DEFINE ML_DELPHI}
{$ENDIF}

interface

uses
  Classes, SysUtils,
  Generics.Collections, TypInfo, maxlogic.fpc.diagnostics
  {$IFDEF ML_FPC}, maxlogic.fpc.compatibility{$ENDIF}
  {$IFDEF ML_DELPHI}, Rtti, System.WeakReference{$ENDIF};

const
  ML_BUS_VERSION = '0.1.0';

type
  TMLString = type UnicodeString;

{$IFDEF ML_FPC}
  TMLProc = TProc;
  TMLProcOf<T> = TProc1<T>;
  TMLKeyFunc<T> = function(const aValue: T): TMLString is nested;
{$ELSE}
  TMLProc = reference to procedure;
  TMLProcOf<T> = reference to procedure(const aValue: T);
  TMLKeyFunc<T> = reference to function(const aValue: T): TMLString;
{$ENDIF}

  TMLProcQueue = TQueue<TMLProc>;
  TMLExceptionList = TObjectList<Exception>;

{$IFNDEF ML_FPC}
  TMLMonitorObject = TObject;
{$ENDIF}


  TMLDelivery = (Posting, Main, Async, Background);
  TMLOverflow = (DropNewest, DropOldest, Block, Deadline);

  IMLAsync = interface
    ['{02AB5A8B-8A3F-4F29-9C1E-1A31B8E7B6A9}']
    procedure RunAsync(const aProc: TMLProc);
    procedure RunOnMain(const aProc: TMLProc);
    procedure RunDelayed(const aProc: TMLProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

  IMLSubscription = interface
    ['{79C1B0D9-6A9E-4C6B-8E96-88A84E4F1E03}']
    procedure Unsubscribe;
    function IsActive: Boolean;
  end;

  IMLBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    function Subscribe<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
    procedure Post<T>(const aEvent: T);
    function TryPost<T>(const aEvent: T): Boolean; overload;

    function SubscribeNamed(const aName: TMLString; const aHandler: TMLProc; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
    procedure PostNamed(const aName: TMLString);
    function TryPostNamed(const aName: TMLString): Boolean; overload;

    function SubscribeNamedOf<T>(const aName: TMLString; const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
    procedure PostNamedOf<T>(const aName: TMLString; const aEvent: T);
    function TryPostNamedOf<T>(const aName: TMLString; const aEvent: T): Boolean; overload;

    function SubscribeGuidOf<T: IInterface>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
    procedure PostGuidOf<T: IInterface>(const aEvent: T);
    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
  end;

  IMLBusAdvanced = interface(IMLBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableSticky<T>(aEnable: Boolean);
    procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
    procedure EnableCoalesceOf<T>(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer = 0);
    procedure EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer = 0);
  end;

  TMLQueuePolicy = record
    MaxDepth: Integer;
    Overflow: TMLOverflow;
    DeadlineUs: Int64;
  end;

  IMLBusQueues = interface
    ['{E55F7B60-9B31-4C80-9B2C-8D1F0E26FF9C}']
    procedure SetPolicyFor<T>(const aPolicy: TMLQueuePolicy);
    procedure SetPolicyNamed(const aName: string; const aPolicy: TMLQueuePolicy);
    function GetPolicyFor<T>: TMLQueuePolicy;
  end;

  TMLTopicStats = record
    PostsTotal: UInt64;
    DeliveredTotal: UInt64;
    DroppedTotal: UInt64;
    ExceptionsTotal: UInt64;
    MaxQueueDepth: UInt32;
    CurrentQueueDepth: UInt32;
  end;

  IMLBusMetrics = interface
    ['{2C4B91E3-1C0A-4B5C-B8B0-0C1A5C3E6D10}']
    function GetStatsFor<T>: TMLTopicStats;
    function GetStatsNamed(const aName: string): TMLTopicStats;
    function GetTotals: TMLTopicStats;
  end;

  IMLSubscriptionState = interface
    ['{6B8BCC86-7AC3-4B6F-9CF9-2F3EE0A5F913}']
    function TryEnter: Boolean;
    procedure Leave;
    procedure Deactivate;
    function IsActive: Boolean;
  end;

  TMLSubscriptionState = class(TInterfacedObject, IMLSubscriptionState)
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

  EMLAggregateException = class(Exception)
  private
    fInner: TMLExceptionList;
  public
    constructor Create(const aInner: TMLExceptionList);
    destructor Destroy; override;
    property Inner: TMLExceptionList read fInner;
  end;

{$IFDEF ML_FPC}
  TOnAsyncError = procedure(const aTopic: string; const aE: Exception);
  TOnMetricSample = procedure(const aName: string; const aStats: TMLTopicStats);
{$ELSE}
  TOnAsyncError = reference to procedure(const aTopic: string; const aE: Exception);
  TOnMetricSample = reference to procedure(const aName: string; const aStats: TMLTopicStats);
{$ENDIF}
function MLBus: IMLBus;
procedure MLSetAsyncErrorHandler(const aHandler: TOnAsyncError);
procedure MLSetMetricCallback(const aSampler: TOnMetricSample);
procedure MLSetAsyncScheduler(const aScheduler: IMLAsync);
function MLGetAsyncScheduler: IMLAsync;


{$IFDEF ML_DELPHI}
type
  MLSubscribeAttribute = class(TCustomAttribute)
  public
    Name: string;
    Delivery: TMLDelivery;
    constructor Create(aDelivery: TMLDelivery); overload;
    constructor Create(const aName: string; aDelivery: TMLDelivery = TMLDelivery.Posting); overload;
  end;

procedure AutoSubscribe(const aInstance: TObject);
procedure AutoUnsubscribe(const aInstance: TObject);
{$ENDIF}

type
  TMLTopicBase = class(TMLMonitorObject)
  protected
    fQueue: TMLProcQueue;
    fProcessing: Boolean;
    fSticky: Boolean;
    fPolicy: TMLQueuePolicy;
    fStats: TMLTopicStats;
    fMetricName: TMLString;
    fWarnedHighWater: Boolean;
    procedure TouchMetrics; inline;
    procedure CheckHighWater; inline;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMetricName(const aName: TMLString); inline;
    function Enqueue(const aProc: TMLProc): Boolean;
    procedure RemoveByTarget(const aTarget: TObject); virtual; abstract;
    procedure SetSticky(aEnable: Boolean); virtual;
    procedure SetPolicy(const aPolicy: TMLQueuePolicy);
    function GetPolicy: TMLQueuePolicy;
    procedure AddPost; inline;
    procedure AddDelivered(aCount: Integer); inline;
    procedure AddDropped; inline;
    procedure AddException; inline;
    function GetStats: TMLTopicStats; inline;
  end;

  TMLTypeTopicDict = TObjectDictionary<PTypeInfo, TMLTopicBase>;
  TMLNameTopicDict = TObjectDictionary<TMLString, TMLTopicBase>;
  TMLNameTypeTopicDict = TObjectDictionary<TMLString, TObjectDictionary<PTypeInfo, TMLTopicBase>>;
  TMLGuidTopicDict = TObjectDictionary<TGuid, TMLTopicBase>;
  TMLBoolDictOfTypeInfo = TDictionary<PTypeInfo, Boolean>;
  TMLBoolDictOfString = TDictionary<TMLString, Boolean>;
  TMLSubList = TList<IMLSubscription>;
  TMLAutoSubDict = TObjectDictionary<TObject, TMLSubList>;

  TMLSubscriptionToken = UInt64;

  TMLWeakTarget = record
    Raw: TObject;
  {$IFDEF ML_DELPHI}
    WeakRef: IWeakReference;
  {$ENDIF}
    class function Create(const aObj: TObject): TMLWeakTarget; static;
    function Matches(const aObj: TObject): Boolean;
    function IsAlive: Boolean;
  end;

  TTypedSubscriber<T> = record
    Handler: TMLProcOf<T>;
    Mode: TMLDelivery;
    Token: TMLSubscriptionToken;
    Target: TMLWeakTarget;
    State: IMLSubscriptionState;
  end;

  TTypedTopic<T> = class(TMLTopicBase)
  private
    fSubs: TArray<TTypedSubscriber<T>>;
    fLast: T;
    fHasLast: Boolean;
    fCoalesce: Boolean;
    fKeyFunc: TMLKeyFunc<T>;
    fWindowUs: Integer;
    fPending: TDictionary<TMLString, T>;
    fPendingLock: TMLMonitorObject;
    fNextToken: TMLSubscriptionToken;
    procedure PruneDead;
  public
    constructor Create;
    function Add(const aHandler: TMLProcOf<T>; aMode: TMLDelivery; out aState: IMLSubscriptionState): TMLSubscriptionToken;
    procedure RemoveByToken(aToken: TMLSubscriptionToken);
    function Snapshot: TArray<TTypedSubscriber<T>>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: Boolean); override;
    procedure Cache(const aEvent: T);
    function TryGetCached(out aEvent: T): Boolean;
    procedure SetCoalesce(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer);
    function HasCoalesce: Boolean;
    function CoalesceKey(const aEvent: T): TMLString;
    function AddOrUpdatePending(const aKey: TMLString; const aEvent: T): Boolean;
    function PopPending(const aKey: TMLString; out aEvent: T): Boolean;
    function CoalesceWindow: Integer;
    destructor Destroy; override;
  end;


  TMLBus = class(TInterfacedObject, IMLBus, IMLBusAdvanced, IMLBusQueues, IMLBusMetrics)
  private
    fAsync: IMLAsync;
    fLock: TMLMonitorObject;
    fTyped: TMLTypeTopicDict;
    fNamed: TMLNameTopicDict;
    fNamedTyped: TMLNameTypeTopicDict;
    fGuid: TMLGuidTopicDict;
    fStickyTypes: TMLBoolDictOfTypeInfo;
    fStickyNames: TMLBoolDictOfString;
    function ScheduleTypedCoalesce<T>(const aTopicName: TMLString;
      aTopic: TTypedTopic<T>; const aSubs: TArray<TTypedSubscriber<T>>;
      const aKey: TMLString): Boolean;
  public
      function Subscribe<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
      procedure Post<T>(const aEvent: T);
      function TryPost<T>(const aEvent: T): Boolean; overload;

      function SubscribeNamed(const aName: TMLString; const aHandler: TMLProc; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
      procedure PostNamed(const aName: TMLString);
      function TryPostNamed(const aName: TMLString): Boolean; overload;

      function SubscribeNamedOf<T>(const aName: TMLString; const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
      procedure PostNamedOf<T>(const aName: TMLString; const aEvent: T);
      function TryPostNamedOf<T>(const aName: TMLString; const aEvent: T): Boolean; overload;

      function SubscribeGuidOf<T: IInterface>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery = TMLDelivery.Posting): IMLSubscription;
      procedure PostGuidOf<T: IInterface>(const aEvent: T);
      procedure UnsubscribeAllFor(const aTarget: TObject);
      procedure Clear;
      procedure EnableSticky<T>(aEnable: Boolean);
      procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
      procedure EnableCoalesceOf<T>(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer = 0);
      procedure EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer = 0);
      procedure SetPolicyFor<T>(const aPolicy: TMLQueuePolicy);
      procedure SetPolicyNamed(const aName: string; const aPolicy: TMLQueuePolicy);
      function GetPolicyFor<T>: TMLQueuePolicy;
      function GetStatsFor<T>: TMLTopicStats;
      function GetStatsNamed(const aName: string): TMLTopicStats;
      function GetTotals: TMLTopicStats;
  public
    constructor Create(const aAsync: IMLAsync);
    destructor Destroy; override;
    procedure Dispatch(const aTopic: TMLString; aDelivery: TMLDelivery; const aHandler: TMLProc; const aOnException: TMLProc = nil);
  end;

  TMLAsync = class(TInterfacedObject, IMLAsync)
  public
    procedure RunAsync(const aProc: TMLProc);
    procedure RunOnMain(const aProc: TMLProc);
    procedure RunDelayed(const aProc: TMLProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;

implementation

var
  gAsyncError: TOnAsyncError = nil;
  gMetricSample: TOnMetricSample = nil;
  gBus: IMLBus = nil;
  gAsyncScheduler: IMLAsync = nil;
  gAsyncFallback: IMLAsync = nil;

{$IFDEF ML_DELPHI}
var
  GAutoSubs: TMLAutoSubDict;

{ MLSubscribeAttribute }

constructor MLSubscribeAttribute.Create(aDelivery: TMLDelivery);
begin
  Name := '';
  Delivery := aDelivery;
end;

constructor MLSubscribeAttribute.Create(const aName: string; aDelivery: TMLDelivery);
begin
  Name := aName;
  Delivery := aDelivery;
end;

procedure AutoSubscribe(const aInstance: TObject);
var
  lCtx: TRttiContext;
  lType: TRttiType;
  lMeth: TRttiMethod;
  lAttr: TCustomAttribute;
  lSubAttr: MLSubscribeAttribute;
  lParams: TArray<TRttiParameter>;
  lBusType: TRttiType;
  lBusMeth: TRttiMethod;
  lHandlerType: TRttiType;
  lMethod: TMethod;
  lHandlerVal, lNameVal, lDeliveryVal: TValue;
  lSub: IMLSubscription;
  lList: TMLSubList;
begin
  if aInstance = nil then
    Exit;

  if GAutoSubs.TryGetValue(aInstance, lList) then
    AutoUnsubscribe(aInstance);

  lCtx := TRttiContext.Create;
  try
    lBusType := lCtx.GetType(TypeInfo(IMLBus));
    lType := lCtx.GetType(aInstance.ClassType);
    lList := TMLSubList.Create;
    for lMeth in lType.GetMethods do
      for lAttr in lMeth.GetAttributes do
        if lAttr is MLSubscribeAttribute then
        begin
          lSubAttr := MLSubscribeAttribute(lAttr);
          lParams := lMeth.GetParameters;

          if (lSubAttr.Name = '') and (Length(lParams) = 0) then
            continue;

          if lSubAttr.Name <> '' then
          begin
            if Length(lParams) = 0 then
              lBusMeth := lBusType.GetMethod('SubscribeNamed')
            else
              lBusMeth := lBusType.GetMethod('SubscribeNamedOf');
          end
          else if lParams[0].ParamType.TypeKind = tkInterface then
            lBusMeth := lBusType.GetMethod('SubscribeGuidOf')
          else
            lBusMeth := lBusType.GetMethod('Subscribe');

          if lBusMeth.IsGeneric then
            lBusMeth := lBusMeth.MakeGenericMethod([lParams[0].ParamType.Handle]);

          if lSubAttr.Name <> '' then
            lHandlerType := lBusMeth.GetParameters[1].ParamType
          else
            lHandlerType := lBusMeth.GetParameters[0].ParamType;

          lMethod.Code := lMeth.CodeAddress;
          lMethod.Data := aInstance;
          TValue.Make(@lMethod, lHandlerType.Handle, lHandlerVal);
          lDeliveryVal := TValue.From<TMLDelivery>(lSubAttr.Delivery);

          if lSubAttr.Name <> '' then
          begin
            lNameVal := TValue.From<TMLString>(lSubAttr.Name);
            lSub := lBusMeth.Invoke(TValue.From<IMLBus>(MLBus), [lNameVal, lHandlerVal, lDeliveryVal]).AsType<IMLSubscription>;
          end
          else
            lSub := lBusMeth.Invoke(TValue.From<IMLBus>(MLBus), [lHandlerVal, lDeliveryVal]).AsType<IMLSubscription>;

          lList.Add(lSub);
        end;

    if lList.Count > 0 then
      GAutoSubs.Add(aInstance, lList)
    else
      lList.Free;
  finally
    lCtx.Free;
  end;
end;

procedure AutoUnsubscribe(const aInstance: TObject);
var
  lList: TMLSubList;
  lSub: IMLSubscription;
begin
  if not GAutoSubs.TryGetValue(aInstance, lList) then
    Exit;
  for lSub in lList do
    lSub.Unsubscribe;
  GAutoSubs.Remove(aInstance);
end;
{$ENDIF}

{ EMLAggregateException }

constructor EMLAggregateException.Create(const aInner: TMLExceptionList);
begin
  fInner := aInner;
  inherited CreateFmt('%d exception(s) occurred', [fInner.Count]);
end;

destructor EMLAggregateException.Destroy;
begin
  fInner.Free;
  inherited Destroy;
end;

{ TMLWeakTarget }

class function TMLWeakTarget.Create(const aObj: TObject): TMLWeakTarget;
begin
  Result.Raw := aObj;
{$IFDEF ML_DELPHI}
  if aObj <> nil then
    Result.WeakRef := TWeakReference.Create(aObj)
  else
    Result.WeakRef := nil;
{$ENDIF}
end;

function TMLWeakTarget.Matches(const aObj: TObject): Boolean;
begin
  Result := (Raw <> nil) and (Raw = aObj);
end;

function TMLWeakTarget.IsAlive: Boolean;
{$IFDEF ML_DELPHI}
var
  lObj: TObject;
{$ENDIF}
begin
  if Raw = nil then
    Exit(True);
{$IFDEF ML_DELPHI}
  if WeakRef = nil then
    Exit(True);
  lObj := WeakRef.Target;
  Result := lObj <> nil;
{$ELSE}
  Result := True;
{$ENDIF}
end;

{ TMLSubscriptionState }

constructor TMLSubscriptionState.Create;
begin
  inherited Create;
  fActive := True;
  fInFlight := 0;
end;

function TMLSubscriptionState.TryEnter: Boolean;
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

procedure TMLSubscriptionState.Leave;
begin
  TMonitor.Enter(Self);
  try
    if fInFlight > 0 then
      Dec(fInFlight);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TMLSubscriptionState.Deactivate;
begin
  TMonitor.Enter(Self);
  try
    if fActive then
      fActive := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMLSubscriptionState.IsActive: Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := fActive;
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TMLTopicBase }

constructor TMLTopicBase.Create;
begin
  inherited Create;
  fQueue := TMLProcQueue.Create;
  fProcessing := False;
  fSticky := False;
  fPolicy.MaxDepth := 0;
  fPolicy.Overflow := DropNewest;
  fPolicy.DeadlineUs := 0;
  fMetricName := '';
  fWarnedHighWater := False;
  FillChar(fStats, SizeOf(fStats), 0);
end;

destructor TMLTopicBase.Destroy;
begin
  fQueue.Free;
  inherited Destroy;
end;

procedure TMLTopicBase.SetMetricName(const aName: TMLString);
begin
  if (fMetricName = '') and (aName <> '') then
    fMetricName := aName;
end;

procedure TMLTopicBase.SetPolicy(const aPolicy: TMLQueuePolicy);
begin
  fPolicy := aPolicy;
  fWarnedHighWater := False;
end;

function TMLTopicBase.GetPolicy: TMLQueuePolicy;
begin
  Result := fPolicy;
end;

procedure TMLTopicBase.TouchMetrics;
begin
  if (fMetricName <> '') and Assigned(gMetricSample) then
    gMetricSample(string(fMetricName), fStats);
end;

procedure TMLTopicBase.CheckHighWater;
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

procedure TMLTopicBase.AddPost;
begin
  Inc(fStats.PostsTotal);
  TouchMetrics;
end;

procedure TMLTopicBase.AddDelivered(aCount: Integer);
begin
  Inc(fStats.DeliveredTotal, aCount);
  TouchMetrics;
end;

procedure TMLTopicBase.AddDropped;
begin
  Inc(fStats.DroppedTotal);
  TouchMetrics;
end;

procedure TMLTopicBase.AddException;
begin
  Inc(fStats.ExceptionsTotal);
  TouchMetrics;
end;

function TMLTopicBase.GetStats: TMLTopicStats;
begin
  Result := fStats;
end;

function TMLTopicBase.Enqueue(const aProc: TMLProc): Boolean;
var
  lProc: TMLProc;
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
            TMonitor.Wait(Self);
        Deadline:
          if fPolicy.DeadlineUs <= 0 then
          begin
            while fQueue.Count >= fPolicy.MaxDepth do
              TMonitor.Wait(Self);
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

procedure TMLTopicBase.SetSticky(aEnable: Boolean);
begin
  fSticky := aEnable;
end;

  type
    TNamedSubscriber = record
      Handler: TMLProc;
      Mode: TMLDelivery;
      Token: TMLSubscriptionToken;
      Target: TMLWeakTarget;
      State: IMLSubscriptionState;
    end;

  TNamedTopic = class(TMLTopicBase)
  private
    fSubs: TArray<TNamedSubscriber>;
    fHasLast: Boolean;
    fNextToken: TMLSubscriptionToken;
    procedure PruneDead;
  public
    function Add(const aHandler: TMLProc; aMode: TMLDelivery; out aState: IMLSubscriptionState): TMLSubscriptionToken;
    procedure RemoveByToken(aToken: TMLSubscriptionToken);
    function Snapshot: TArray<TNamedSubscriber>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: Boolean); override;
    procedure Cache;
    function HasCached: Boolean;
  end;

  TMLSubscriptionBase = class(TInterfacedObject, IMLSubscription)
  protected
    fActive: Boolean;
    fState: IMLSubscriptionState;
  public
    constructor Create(const aState: IMLSubscriptionState);
    destructor Destroy; override;
    procedure Unsubscribe; virtual; abstract;
    function IsActive: Boolean;
  end;

  TMLTypedSubscription<T> = class(TMLSubscriptionBase)
  private
    fTopic: TTypedTopic<T>;
    fToken: TMLSubscriptionToken;
  public
    constructor Create(aTopic: TTypedTopic<T>; aToken: TMLSubscriptionToken; const aState: IMLSubscriptionState);
    procedure Unsubscribe; override;
  end;

  TMLNamedSubscription = class(TMLSubscriptionBase)
  private
    fTopic: TNamedTopic;
    fToken: TMLSubscriptionToken;
  public
    constructor Create(aTopic: TNamedTopic; aToken: TMLSubscriptionToken; const aState: IMLSubscriptionState);
    procedure Unsubscribe; override;
  end;

type
  TMLProcAdapter = class
  private
    fProc: TMLProc;
  public
    constructor Create(const aProc: TMLProc);
    procedure Invoke;
  end;

  TMLProcThread = class(TThread)
  private
    fProc: TMLProc;
    fDelayUs: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const aProc: TMLProc; aDelayUs: Integer);
    class procedure Start(const aProc: TMLProc; aDelayUs: Integer = 0); static;
  end;

function ProcAssigned(const aProc: TMLProc): Boolean; inline;

function NormalizeName(const aName: TMLString): TMLString; inline;
begin
  Result := TMLString(UpperCase(UnicodeString(aName)));
end;

function ProcAssigned(const aProc: TMLProc): Boolean;
var
  m: TMethod;
begin
  m := TMethod(aProc);
  Result := m.Code <> nil;
end;

function TypeMetricName(const aInfo: PTypeInfo): TMLString; inline;
begin
  Result := TMLString(GetTypeName(aInfo));
end;

function NamedMetricName(const aName: TMLString): TMLString; inline;
begin
  Result := aName;
end;

function NamedTypeMetricName(const aName: TMLString; const aInfo: PTypeInfo): TMLString; inline;
begin
  Result := aName + ':' + TMLString(GetTypeName(aInfo));
end;

function GuidMetricName(const aGuid: TGuid): TMLString; inline;
begin
  Result := TMLString(GuidToString(aGuid));
end;

{ TMLProcAdapter }

constructor TMLProcAdapter.Create(const aProc: TMLProc);
begin
  inherited Create;
  fProc := aProc;
end;

procedure TMLProcAdapter.Invoke;
var
  lProc: TMLProc;
begin
  lProc := fProc;
  try
    if ProcAssigned(lProc) then
      lProc();
  finally
    Free;
  end;
end;

{ TMLProcThread }

constructor TMLProcThread.Create(const aProc: TMLProc; aDelayUs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  fProc := aProc;
  if aDelayUs > 0 then
    fDelayUs := aDelayUs
  else
    fDelayUs := 0;
end;

procedure TMLProcThread.Execute;
var
  lProc: TMLProc;
  lDelayMs: Integer;
begin
  lProc := fProc;
  fProc := nil;
  if fDelayUs > 0 then
  begin
    lDelayMs := fDelayUs div 1000;
    if lDelayMs > 0 then
      TThread.Sleep(lDelayMs);
  end;
  if ProcAssigned(lProc) then
    lProc();
end;

class procedure TMLProcThread.Start(const aProc: TMLProc; aDelayUs: Integer);
var
  lThread: TMLProcThread;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lThread := TMLProcThread.Create(aProc, aDelayUs);
  lThread.Start;
end;

{ TTypedTopic<T> }

constructor TTypedTopic<T>.Create;
begin
  inherited Create;
  fPendingLock := TMLMonitorObject.Create;
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

function TTypedTopic<T>.Add(const aHandler: TMLProcOf<T>; aMode: TMLDelivery; out aState: IMLSubscriptionState): TMLSubscriptionToken;
var
  lMethod: TMethod;
  lNew: TArray<TTypedSubscriber<T>>;
  lSub: TTypedSubscriber<T>;
begin
  if fNextToken = 0 then
    fNextToken := 1;
  lMethod := TMethod(aHandler);
  lSub.Handler := aHandler;
  lSub.Mode := aMode;
  lSub.Token := fNextToken;
  lSub.Target := TMLWeakTarget.Create(TObject(lMethod.Data));
  lSub.State := TMLSubscriptionState.Create;
  aState := lSub.State;
  Inc(fNextToken);
  lNew := Copy(fSubs);
  SetLength(lNew, Length(lNew) + 1);
  lNew[High(lNew)] := lSub;
  fSubs := lNew;
  Result := lSub.Token;
end;

procedure TTypedTopic<T>.RemoveByToken(aToken: TMLSubscriptionToken);
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

procedure TTypedTopic<T>.SetCoalesce(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer);
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
        fPending := TDictionary<TMLString, T>.Create;
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

function TTypedTopic<T>.CoalesceKey(const aEvent: T): TMLString;
begin
  if Assigned(fKeyFunc) then
    Result := fKeyFunc(aEvent)
  else
    Result := '';
end;

function TTypedTopic<T>.AddOrUpdatePending(const aKey: TMLString; const aEvent: T): Boolean;
begin
  TMonitor.Enter(fPendingLock);
  try
    if fPending = nil then
      fPending := TDictionary<TMLString, T>.Create;
    Result := not fPending.ContainsKey(aKey);
    fPending.AddOrSetValue(aKey, aEvent);
  finally
    TMonitor.Exit(fPendingLock);
  end;
end;

function TTypedTopic<T>.PopPending(const aKey: TMLString; out aEvent: T): Boolean;
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

function TNamedTopic.Add(const aHandler: TMLProc; aMode: TMLDelivery; out aState: IMLSubscriptionState): TMLSubscriptionToken;
var
  lMethod: TMethod;
  lSub: TNamedSubscriber;
  lNew: TArray<TNamedSubscriber>;
begin
  if fNextToken = 0 then
    fNextToken := 1;
  lMethod := TMethod(aHandler);
  lSub.Handler := aHandler;
  lSub.Mode := aMode;
  lSub.Token := fNextToken;
  lSub.Target := TMLWeakTarget.Create(TObject(lMethod.Data));
  lSub.State := TMLSubscriptionState.Create;
  aState := lSub.State;
  Inc(fNextToken);
  lNew := Copy(fSubs);
  SetLength(lNew, Length(lNew) + 1);
  lNew[High(lNew)] := lSub;
  fSubs := lNew;
  Result := lSub.Token;
end;

procedure TNamedTopic.RemoveByToken(aToken: TMLSubscriptionToken);
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

{ TMLSubscriptionBase }

constructor TMLSubscriptionBase.Create(const aState: IMLSubscriptionState);
begin
  inherited Create;
  fActive := True;
  fState := aState;
end;

destructor TMLSubscriptionBase.Destroy;
begin
  if fActive then
    Unsubscribe;
  fState := nil;
  inherited Destroy;
end;

function TMLSubscriptionBase.IsActive: Boolean;
begin
  Result := fActive and Assigned(fState) and fState.IsActive;
end;

{ TMLTypedSubscription<T> }

constructor TMLTypedSubscription<T>.Create(aTopic: TTypedTopic<T>; aToken: TMLSubscriptionToken; const aState: IMLSubscriptionState);
begin
  inherited Create(aState);
  fTopic := aTopic;
  fToken := aToken;
end;

procedure TMLTypedSubscription<T>.Unsubscribe;
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

{ TMLNamedSubscription }

constructor TMLNamedSubscription.Create(aTopic: TNamedTopic; aToken: TMLSubscriptionToken; const aState: IMLSubscriptionState);
begin
  inherited Create(aState);
  fTopic := aTopic;
  fToken := aToken;
end;

procedure TMLNamedSubscription.Unsubscribe;
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

function DefaultAsync: IMLAsync;
begin
  if gAsyncScheduler <> nil then
    Exit(gAsyncScheduler);
  if gAsyncFallback = nil then
    gAsyncFallback := TMLAsync.Create;
  Result := gAsyncFallback;
end;

function MLBus: IMLBus;
begin
  if gBus = nil then
    gBus := TMLBus.Create(DefaultAsync);
  Result := gBus;
end;

procedure MLSetAsyncErrorHandler(const aHandler: TOnAsyncError);
begin
  gAsyncError := aHandler;
end;

procedure MLSetMetricCallback(const aSampler: TOnMetricSample);
begin
  gMetricSample := aSampler;
end;

procedure MLSetAsyncScheduler(const aScheduler: IMLAsync);
begin
  gAsyncScheduler := aScheduler;
end;

function MLGetAsyncScheduler: IMLAsync;
begin
  if gAsyncScheduler <> nil then
    Result := gAsyncScheduler
  else
    Result := DefaultAsync;
end;

{ TMLAsync }

procedure TMLAsync.RunAsync(const aProc: TMLProc);
begin
  TMLProcThread.Start(aProc);
end;

procedure TMLAsync.RunOnMain(const aProc: TMLProc);
var
  lAdapter: TMLProcAdapter;
begin
  if not ProcAssigned(aProc) then
    Exit;
  lAdapter := TMLProcAdapter.Create(aProc);
  try
    TThread.Queue(nil, lAdapter.Invoke);
  except
    lAdapter.Free;
    raise;
  end;
end;

procedure TMLAsync.RunDelayed(const aProc: TMLProc; aDelayUs: Integer);
var
  lDelay: Integer;
begin
  if aDelayUs < 0 then
    lDelay := 0
  else
    lDelay := aDelayUs;
  TMLProcThread.Start(aProc, lDelay);
end;

function TMLAsync.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

function TMLBus.ScheduleTypedCoalesce<T>(const aTopicName: TMLString;
  aTopic: TTypedTopic<T>; const aSubs: TArray<TTypedSubscriber<T>>;
  const aKey: TMLString): Boolean;
var
  lKeyCopy: TMLString;
begin
  lKeyCopy := aKey;
  Result := aTopic.Enqueue(
    procedure
    var
      lPendingKey: TMLString;
    begin
      lPendingKey := lKeyCopy;
      fAsync.RunDelayed(
        procedure
        var
          lSub: TTypedSubscriber<T>;
          lInner: T;
          lErrs: TMLExceptionList;
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
                    lErrs := TMLExceptionList.Create(True);
                  lErrs.Add(e);
                end;
              end;
            finally
              lSub.State.Leave;
            end;
          end;
          if lErrs <> nil then
            raise EMLAggregateException.Create(lErrs);
        end,
        aTopic.CoalesceWindow);
    end);
end;

{ TMLBus }

constructor TMLBus.Create(const aAsync: IMLAsync);
begin
  inherited Create;
  fAsync := aAsync;
  fLock := TMLMonitorObject.Create;
  fTyped := TMLTypeTopicDict.Create([doOwnsValues]);
  fNamed := TMLNameTopicDict.Create([doOwnsValues]);
  fNamedTyped := TMLNameTypeTopicDict.Create([doOwnsValues]);
  fGuid := TMLGuidTopicDict.Create([doOwnsValues]);
  fStickyTypes := TMLBoolDictOfTypeInfo.Create;
  fStickyNames := TMLBoolDictOfString.Create;
end;

destructor TMLBus.Destroy;
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

procedure TMLBus.Dispatch(const aTopic: TMLString; aDelivery: TMLDelivery; const aHandler: TMLProc; const aOnException: TMLProc);
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
                gAsyncError(string(aTopic), e);
            end;
          end;
        end);
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
                gAsyncError(string(aTopic), e);
            end;
          end;
        end);
    Background:
      if fAsync.IsMainThread then
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
                  gAsyncError(string(aTopic), e);
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
              gAsyncError(string(aTopic), e);
          end;
        end;
  end;
end;

function TMLBus.Subscribe<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: PTypeInfo;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  token: TMLSubscriptionToken;
  send: Boolean;
  last: T;
  metricName: TMLString;
  lState: IMLSubscriptionState;
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
  Result := TMLTypedSubscription<T>.Create(topic, token, lState);
end;

procedure TMLBus.Post<T>(const aEvent: T);
var
  lKey: PTypeInfo;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDropVal: T;
  lMetric: TMLString;
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;

function TMLBus.TryPost<T>(const aEvent: T): Boolean;
var
  lKey: PTypeInfo;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDropVal: T;
  lMetric: TMLString;
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end);
  if not Result then
    lTopic.AddDropped;
end;

function TMLBus.SubscribeNamed(const aName: TMLString; const aHandler: TMLProc; aMode: TMLDelivery): IMLSubscription;
var
  obj: TMLTopicBase;
  topic: TNamedTopic;
  token: TMLSubscriptionToken;
  send: Boolean;
  lNameKey: TMLString;
  lMetric: TMLString;
  lState: IMLSubscriptionState;
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
  Result := TMLNamedSubscription.Create(topic, token, lState);
end;


procedure TMLBus.PostNamed(const aName: TMLString);
var
  obj: TMLTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TMLString;
  lMetric: TMLString;
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          sub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    topic.AddDropped;
end;


function TMLBus.TryPostNamed(const aName: TMLString): Boolean;
var
  obj: TMLTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TMLString;
  lMetric: TMLString;
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          sub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
  begin
    topic.AddDropped;
    Result := False;
  end;
end;


function TMLBus.SubscribeNamedOf<T>(const aName: TMLString; const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  typeDict: TMLTypeTopicDict;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  token: TMLSubscriptionToken;
  key: PTypeInfo;
  send: Boolean;
  last: T;
  lNameKey: TMLString;
  lMetric: TMLString;
  lState: IMLSubscriptionState;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  lMetric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, typeDict) then
    begin
      typeDict := TMLTypeTopicDict.Create([doOwnsValues]);
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
  Result := TMLTypedSubscription<T>.Create(topic, token, lState);
end;


procedure TMLBus.PostNamedOf<T>(const aName: TMLString; const aEvent: T);
var
  lTypeDict: TMLTypeTopicDict;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDropVal: T;
  lNameKey: TMLString;
  lMetric: TMLString;
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
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;


function TMLBus.TryPostNamedOf<T>(const aName: TMLString; const aEvent: T): Boolean;
var
  lTypeDict: TMLTypeTopicDict;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDropVal: T;
  lNameKey: TMLString;
  lMetric: TMLString;
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
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
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
      lErrs: TMLExceptionList;
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
                lErrs := TMLExceptionList.Create(True);
              lErrs.Add(e);
            end;
          end;
        finally
          lSub.State.Leave;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end);
  if not Result then
    lTopic.AddDropped;
end;


function TMLBus.SubscribeGuidOf<T{$IFDEF ML_DELPHI}: IInterface{$ENDIF}>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: TGuid;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  token: TMLSubscriptionToken;
  send: Boolean;
  last: T;
  lMetric: TMLString;
  lState: IMLSubscriptionState;
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
  Result := TMLTypedSubscription<T>.Create(topic, token, lState);
end;


procedure TMLBus.PostGuidOf<T{$IFDEF ML_DELPHI}: IInterface{$ENDIF}>(const aEvent: T);
var
  lKey: TGuid;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDrop: T;
  lMetric: TMLString;
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
      lErrs: TMLExceptionList;
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
              lErrs := TMLExceptionList.Create(True);
            lErrs.Add(e);
          end;
        end;
      end;
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;

procedure TMLBus.EnableSticky<T>(aEnable: Boolean);
var
  key: PTypeInfo;
  obj: TMLTopicBase;
  kvName: TPair<TMLString, TMLTypeTopicDict>;
  kvInner: TPair<PTypeInfo, TMLTopicBase>;
  guid: TGuid;
  metric: TMLString;
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

procedure TMLBus.EnableStickyNamed(const aName: string; aEnable: Boolean);
var
  obj: TMLTopicBase;
  typeDict: TMLTypeTopicDict;
  kvInner: TPair<PTypeInfo, TMLTopicBase>;
  lNameKey: TMLString;
  metric: TMLString;
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

procedure TMLBus.EnableCoalesceOf<T>(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer);
var
  key: PTypeInfo;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  metric: TMLString;
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

procedure TMLBus.EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer);
var
  typeDict: TMLTypeTopicDict;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  lNameKey: TMLString;
  metric: TMLString;
  key: PTypeInfo;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
  metric := NamedTypeMetricName(lNameKey, key);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, typeDict) then
    begin
      typeDict := TMLTypeTopicDict.Create([doOwnsValues]);
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

procedure TMLBus.UnsubscribeAllFor(const aTarget: TObject);
var
  kvTyped: TPair<PTypeInfo, TMLTopicBase>;
  kvNamed: TPair<TMLString, TMLTopicBase>;
  kvName: TPair<TMLString, TMLTypeTopicDict>;
  kvInner: TPair<PTypeInfo, TMLTopicBase>;
  kvGuid: TPair<TGuid, TMLTopicBase>;
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

procedure TMLBus.Clear;
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

procedure TMLBus.SetPolicyFor<T>(const aPolicy: TMLQueuePolicy);
var
  lKey: PTypeInfo;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  metric: TMLString;
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

procedure TMLBus.SetPolicyNamed(const aName: string; const aPolicy: TMLQueuePolicy);
var
  lTopic: TMLTopicBase;
  lNameKey: TMLString;
  metric: TMLString;
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

function TMLBus.GetPolicyFor<T>: TMLQueuePolicy;
var
  lKey: PTypeInfo;
  lObj: TMLTopicBase;
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

function TMLBus.GetStatsFor<T>: TMLTopicStats;
var
  lKey: PTypeInfo;
  lObj: TMLTopicBase;
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

function TMLBus.GetStatsNamed(const aName: string): TMLTopicStats;
var
  lObj: TMLTopicBase;
  lNameKey: TMLString;
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

function TMLBus.GetTotals: TMLTopicStats;
var
  lObj: TMLTopicBase;
  lTypeDict: TMLTypeTopicDict;
  lInner: TMLTopicBase;
  lGuidObj: TMLTopicBase;
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


{$IFDEF ML_DELPHI}
initialization
  GAutoSubs := TMLAutoSubDict.Create([doOwnsValues]);
finalization
  GAutoSubs.Free;
{$ENDIF}

end.
