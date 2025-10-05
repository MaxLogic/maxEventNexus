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
  {$IFDEF ML_DELPHI}, Rtti{$ENDIF};

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
  public
    constructor Create;
    destructor Destroy; override;
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

  TTypedSubscriber<T> = record
    Handler: TMLProcOf<T>;
    Mode: TMLDelivery;
    Target: TObject;
  end;

  TTypedTopic<T> = class(TMLTopicBase)
  private
    fSubs: array of TTypedSubscriber<T>;
    fLast: T;
    fHasLast: Boolean;
    fCoalesce: Boolean;
    fKeyFunc: TMLKeyFunc<T>;
    fWindowUs: Integer;
    fPending: TDictionary<TMLString, T>;
    fPendingLock: TMLMonitorObject;
  public
    constructor Create;
    function Add(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): Integer;
    procedure Remove(aIndex: Integer);
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
end;

destructor TMLTopicBase.Destroy;
begin
  fQueue.Free;
  inherited Destroy;
end;

procedure TMLTopicBase.SetPolicy(const aPolicy: TMLQueuePolicy);
begin
  fPolicy := aPolicy;
end;

function TMLTopicBase.GetPolicy: TMLQueuePolicy;
begin
  Result := fPolicy;
end;

procedure TMLTopicBase.AddPost;
begin
  Inc(fStats.PostsTotal);
end;

procedure TMLTopicBase.AddDelivered(aCount: Integer);
begin
  Inc(fStats.DeliveredTotal, aCount);
end;

procedure TMLTopicBase.AddDropped;
begin
  Inc(fStats.DroppedTotal);
end;

procedure TMLTopicBase.AddException;
begin
  Inc(fStats.ExceptionsTotal);
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
        Exit;
      end;
      lProc := fQueue.Dequeue;
      if fStats.CurrentQueueDepth > 0 then
        Dec(fStats.CurrentQueueDepth);
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
      Target: TObject;
    end;

  TNamedTopic = class(TMLTopicBase)
  private
    fSubs: array of TNamedSubscriber;
    fHasLast: Boolean;
  public
    function Add(const aHandler: TMLProc; aMode: TMLDelivery): Integer;
    procedure Remove(aIndex: Integer);
    function Snapshot: TArray<TNamedSubscriber>;
    procedure RemoveByTarget(const aTarget: TObject); override;
    procedure SetSticky(aEnable: Boolean); override;
    procedure Cache;
    function HasCached: Boolean;
  end;

  TMLSubscriptionBase = class(TInterfacedObject, IMLSubscription)
  protected
    fActive: Boolean;
  public
    constructor Create;
    procedure Unsubscribe; virtual; abstract;
    function IsActive: Boolean;
  end;

  TMLTypedSubscription<T> = class(TMLSubscriptionBase)
  private
    fTopic: TTypedTopic<T>;
    fIndex: Integer;
  public
    constructor Create(aTopic: TTypedTopic<T>; aIndex: Integer);
    procedure Unsubscribe; override;
  end;

  TMLNamedSubscription = class(TMLSubscriptionBase)
  private
    fTopic: TNamedTopic;
    fIndex: Integer;
  public
    constructor Create(aTopic: TNamedTopic; aIndex: Integer);
    procedure Unsubscribe; override;
  end;

var
  gAsyncError: TOnAsyncError = nil;
  gMetricSample: TOnMetricSample = nil;
  gBus: IMLBus = nil;

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
end;

function TTypedTopic<T>.Add(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): Integer;
var
  m: TMethod;
begin
  Result := Length(fSubs);
  SetLength(fSubs, Result + 1);
  fSubs[Result].Handler := aHandler;
  fSubs[Result].Mode := aMode;
  m := TMethod(aHandler);
  fSubs[Result].Target := TObject(m.Data);
end;

procedure TTypedTopic<T>.Remove(aIndex: Integer);
var
  L: Integer;
begin
  L := Length(fSubs);
  if (aIndex < 0) or (aIndex >= L) then
    Exit;
  fSubs[aIndex] := fSubs[L - 1];
  SetLength(fSubs, L - 1);
end;

function TTypedTopic<T>.Snapshot: TArray<TTypedSubscriber<T>>;
begin
  Result := Copy(fSubs);
end;

procedure TTypedTopic<T>.RemoveByTarget(const aTarget: TObject);
var
  i: Integer;
begin
  for i := High(fSubs) downto 0 do
    if fSubs[i].Target = aTarget then
      Remove(i);
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
  Result := fKeyFunc(aEvent);
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

function TNamedTopic.Add(const aHandler: TMLProc; aMode: TMLDelivery): Integer;
var
  m: TMethod;
begin
  Result := Length(fSubs);
  SetLength(fSubs, Result + 1);
  fSubs[Result].Handler := aHandler;
  fSubs[Result].Mode := aMode;
  m := TMethod(aHandler);
  fSubs[Result].Target := TObject(m.Data);
end;

procedure TNamedTopic.Remove(aIndex: Integer);
var
  L: Integer;
begin
  L := Length(fSubs);
  if (aIndex < 0) or (aIndex >= L) then
    Exit;
  fSubs[aIndex] := fSubs[L - 1];
  SetLength(fSubs, L - 1);
end;

function TNamedTopic.Snapshot: TArray<TNamedSubscriber>;
begin
  Result := Copy(fSubs);
end;

procedure TNamedTopic.RemoveByTarget(const aTarget: TObject);
var
  i: Integer;
begin
  for i := High(fSubs) downto 0 do
    if fSubs[i].Target = aTarget then
      Remove(i);
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

constructor TMLSubscriptionBase.Create;
begin
  inherited Create;
  fActive := True;
end;

function TMLSubscriptionBase.IsActive: Boolean;
begin
  Result := fActive;
end;

{ TMLTypedSubscription<T> }

constructor TMLTypedSubscription<T>.Create(aTopic: TTypedTopic<T>; aIndex: Integer);
begin
  inherited Create;
  fTopic := aTopic;
  fIndex := aIndex;
end;

procedure TMLTypedSubscription<T>.Unsubscribe;
begin
  if fActive then
  begin
    fTopic.Remove(fIndex);
    fActive := False;
  end;
end;

{ TMLNamedSubscription }

constructor TMLNamedSubscription.Create(aTopic: TNamedTopic; aIndex: Integer);
begin
  inherited Create;
  fTopic := aTopic;
  fIndex := aIndex;
end;

procedure TMLNamedSubscription.Unsubscribe;
begin
  if fActive then
  begin
    fTopic.Remove(fIndex);
    fActive := False;
  end;
end;

function MLBus: IMLBus;
begin
  if gBus = nil then
    gBus := TMLBus.Create(TMLAsync.Create);
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
begin
  Result := True;
  fAsync.RunDelayed(
    procedure
    var
      lK: TMLString;
      lVal: T;
    begin
      lK := aKey;
      if not aTopic.Enqueue(
        procedure
        var
          lSub: TTypedSubscriber<T>;
          lInner: T;
          lErrs: TMLExceptionList;
        begin
          if not aTopic.PopPending(lK, lInner) then
            Exit;
          lErrs := nil;
          for lSub in aSubs do
            try
              Dispatch(aTopicName, lSub.Mode,
                procedure
                begin
                  lSub.Handler(lInner);
                  aTopic.AddDelivered(1);
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
          if lErrs <> nil then
            raise EMLAggregateException.Create(lErrs);
        end) then
      begin
        aTopic.AddDropped;
        aTopic.PopPending(lK, lVal);
      end;
    end,
    aTopic.CoalesceWindow);
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

{$IFDEF ML_FPC}
function TMLBus.Subscribe<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: PTypeInfo;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  send: Boolean;
  last: T;
begin
  key := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      fTyped.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(TMLString(GetTypeName(TypeInfo(T))), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
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
begin
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
begin
  Result := False;
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
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
    Result := ScheduleTypedCoalesce<T>(TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else
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
          try
            Dispatch(TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
              procedure
              begin
                lSub.Handler(lVal);
                lTopic.AddDelivered(1);
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
  idx: Integer;
  send: Boolean;
  lNameKey: TMLString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      topic := TNamedTopic.Create;
      if fStickyNames.ContainsKey(lNameKey) then
        topic.SetSticky(True);
      fNamed.Add(lNameKey, topic);
    end
    else
      topic := TNamedTopic(obj);
    idx := topic.Add(aHandler, aMode);
    send := topic.HasCached;
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      begin
        Dispatch(aName, aMode,
          procedure
          begin
            aHandler();
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLNamedSubscription.Create(topic, idx);
end;

procedure TMLBus.PostNamed(const aName: TMLString);
var
  obj: TMLTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TMLString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
      end
      else
        Exit;
    end
    else
      topic := TNamedTopic(obj);
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
        try
          Dispatch(aName, sub.Mode,
            procedure
            begin
              sub.Handler();
              topic.AddDelivered(1);
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
begin
  Result := False;
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
        topic.Cache;
      end;
      Exit;
    end;
    topic := TNamedTopic(obj);
    subs := topic.Snapshot;
    topic.Cache;
  finally
    TMonitor.Exit(fLock);
  end;
  topic.AddPost;
  if Length(subs) = 0 then
    Exit;
  Result := True;
  if not topic.Enqueue(
    procedure
    var
      sub: TNamedSubscriber;
      lErrs: TMLExceptionList;
    begin
      lErrs := nil;
      for sub in subs do
        try
          Dispatch(aName, sub.Mode,
            procedure
            begin
              sub.Handler();
              topic.AddDelivered(1);
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
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    topic.AddDropped;
end;

function TMLBus.SubscribeNamedOf<T>(const aName: TMLString; const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  typeDict: TMLTypeTopicDict;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  key: PTypeInfo;
  send: Boolean;
  last: T;
  lNameKey: TMLString;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
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
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      typeDict.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
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
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end
      else
        Exit;
    end;
    if not lTypeDict.TryGetValue(TypeInfo(T), lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        lTypeDict.Add(TypeInfo(T), lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(aName + ':' + TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
begin
  Result := False;
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end;
      Exit;
    end;
    if not lTypeDict.TryGetValue(TypeInfo(T), lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        lTypeDict.Add(TypeInfo(T), lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
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
    Result := ScheduleTypedCoalesce<T>(aName + ':' + TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else
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
          try
            Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
              procedure
              begin
                lSub.Handler(lVal);
                lTopic.AddDelivered(1);
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
        if lErrs <> nil then
          raise EMLAggregateException.Create(lErrs);
      end);
  if not Result then
    lTopic.AddDropped;
end;

function TMLBus.SubscribeGuidOf<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: TGuid;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  send: Boolean;
  last: T;
begin
  key := GetTypeData(TypeInfo(T))^.Guid;
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
        topic.SetSticky(True);
      fGuid.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(GuidToString(key), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
end;

procedure TMLBus.PostGuidOf<T>(const aEvent: T);
var
  lKey: TGuid;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDrop: T;
begin
  lKey := GetTypeData(TypeInfo(T))^.Guid;
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fGuid.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(GuidToString(lKey), lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDrop);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(GuidToString(lKey), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;
{$ELSE}
function TMLBus.Subscribe<T>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: PTypeInfo;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  send: Boolean;
  last: T;
begin
  key := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      fTyped.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(TMLString(GetTypeName(TypeInfo(T))), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
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
begin
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
begin
  Result := False;
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(lKey) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fTyped.Add(lKey, lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
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
    Result := ScheduleTypedCoalesce<T>(TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else
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
          try
            Dispatch(TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
              procedure
              begin
                lSub.Handler(lVal);
                lTopic.AddDelivered(1);
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
  idx: Integer;
  send: Boolean;
  lNameKey: TMLString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      topic := TNamedTopic.Create;
      if fStickyNames.ContainsKey(lNameKey) then
        topic.SetSticky(True);
      fNamed.Add(lNameKey, topic);
    end
    else
      topic := TNamedTopic(obj);
    idx := topic.Add(aHandler, aMode);
    send := topic.HasCached;
  finally
    TMonitor.Exit(fLock);
  end;
  if send then
    topic.Enqueue(
      procedure
      begin
        Dispatch(aName, aMode,
          procedure
          begin
            aHandler();
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLNamedSubscription.Create(topic, idx);
end;

procedure TMLBus.PostNamed(const aName: TMLString);
var
  obj: TMLTopicBase;
  topic: TNamedTopic;
  subs: TArray<TNamedSubscriber>;
  lNameKey: TMLString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
      end
      else
        Exit;
    end
    else
      topic := TNamedTopic(obj);
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
        try
          Dispatch(aName, sub.Mode,
            procedure
            begin
              sub.Handler();
              topic.AddDelivered(1);
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
begin
  Result := False;
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, obj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) then
      begin
        topic := TNamedTopic.Create;
        topic.SetSticky(True);
        fNamed.Add(lNameKey, topic);
        topic.Cache;
      end;
      Exit;
    end;
    topic := TNamedTopic(obj);
    subs := topic.Snapshot;
    topic.Cache;
  finally
    TMonitor.Exit(fLock);
  end;
  topic.AddPost;
  if Length(subs) = 0 then
    Exit;
  Result := topic.Enqueue(
    procedure
    var
      sub: TNamedSubscriber;
      lErrs: TMLExceptionList;
    begin
      lErrs := nil;
      for sub in subs do
        try
          Dispatch(aName, sub.Mode,
            procedure
            begin
              sub.Handler();
              topic.AddDelivered(1);
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
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end);
  if not Result then
    topic.AddDropped;
end;

function TMLBus.SubscribeNamedOf<T>(const aName: TMLString; const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  typeDict: TMLTypeTopicDict;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  key: PTypeInfo;
  send: Boolean;
  last: T;
  lNameKey: TMLString;
begin
  key := TypeInfo(T);
  lNameKey := NormalizeName(aName);
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
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      typeDict.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
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
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end
      else
        Exit;
    end;
    if not lTypeDict.TryGetValue(TypeInfo(T), lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        lTypeDict.Add(TypeInfo(T), lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(aName + ':' + TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
begin
  Result := False;
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, lTypeDict) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTypeDict := TMLTypeTopicDict.Create([doOwnsValues]);
        fNamedTyped.Add(lNameKey, lTypeDict);
      end;
      Exit;
    end;
    if not lTypeDict.TryGetValue(TypeInfo(T), lObj) then
    begin
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        lTypeDict.Add(TypeInfo(T), lTopic);
        lTopic.Cache(aEvent);
      end;
      Exit;
    end;
    lTopic := TTypedTopic<T>(lObj);
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
    Result := ScheduleTypedCoalesce<T>(aName + ':' + TMLString(GetTypeName(TypeInfo(T))),
      lTopic, lSubs, lKeyStr);
    if not Result then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDropVal);
    end;
  end
  else
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
          try
            Dispatch(aName + ':' + TMLString(GetTypeName(TypeInfo(T))), lSub.Mode,
              procedure
              begin
                lSub.Handler(lVal);
                lTopic.AddDelivered(1);
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
        if lErrs <> nil then
          raise EMLAggregateException.Create(lErrs);
      end);
  if not Result then
    lTopic.AddDropped;
end;

function TMLBus.SubscribeGuidOf<T: IInterface>(const aHandler: TMLProcOf<T>; aMode: TMLDelivery): IMLSubscription;
var
  key: TGuid;
  obj: TMLTopicBase;
  topic: TTypedTopic<T>;
  idx: Integer;
  send: Boolean;
  last: T;
begin
  key := GetTypeData(TypeInfo(T))^.Guid;
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
        topic.SetSticky(True);
      fGuid.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
    idx := topic.Add(aHandler, aMode);
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
        Dispatch(GuidToString(key), aMode,
          procedure
          begin
            aHandler(val);
            topic.AddDelivered(1);
          end,
          procedure
          begin
            topic.AddException;
          end);
      end);
  Result := TMLTypedSubscription<T>.Create(topic, idx);
end;

procedure TMLBus.PostGuidOf<T: IInterface>(const aEvent: T);
var
  lKey: TGuid;
  lObj: TMLTopicBase;
  lTopic: TTypedTopic<T>;
  lSubs: TArray<TTypedSubscriber<T>>;
  lIsNew: Boolean;
  lKeyStr: TMLString;
  lDrop: T;
begin
  lKey := GetTypeData(TypeInfo(T))^.Guid;
  TMonitor.Enter(fLock);
  try
    if not fGuid.TryGetValue(lKey, lObj) then
    begin
      if fStickyTypes.ContainsKey(TypeInfo(T)) then
      begin
        lTopic := TTypedTopic<T>.Create;
        lTopic.SetSticky(True);
        fGuid.Add(lKey, lTopic);
      end
      else
        Exit;
    end
    else
      lTopic := TTypedTopic<T>(lObj);
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
    if not ScheduleTypedCoalesce<T>(GuidToString(lKey), lTopic, lSubs, lKeyStr) then
    begin
      lTopic.AddDropped;
      lTopic.PopPending(lKeyStr, lDrop);
    end;
  end
  else if not lTopic.Enqueue(
    procedure
    var
      lSub: TTypedSubscriber<T>;
      lVal: T;
      lErrs: TMLExceptionList;
    begin
      lVal := aEvent;
      lErrs := nil;
      for lSub in lSubs do
        try
          Dispatch(GuidToString(lKey), lSub.Mode,
            procedure
            begin
              lSub.Handler(lVal);
              lTopic.AddDelivered(1);
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
      if lErrs <> nil then
        raise EMLAggregateException.Create(lErrs);
    end) then
    lTopic.AddDropped;
end;
{$ENDIF}

  procedure TMLBus.EnableSticky<T>(aEnable: Boolean);
var
  key: PTypeInfo;
  obj: TMLTopicBase;
    kvName: TPair<TMLString, TMLTypeTopicDict>;
  typeDict: TMLTypeTopicDict;
  guid: TGuid;
begin
  key := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyTypes.AddOrSetValue(key, True)
    else
      fStickyTypes.Remove(key);
    if fTyped.TryGetValue(key, obj) then
      obj.SetSticky(aEnable);
    for kvName in fNamedTyped do
      if kvName.Value.TryGetValue(key, obj) then
        obj.SetSticky(aEnable);
    guid := GetTypeData(key)^.Guid;
    if fGuid.TryGetValue(guid, obj) then
      obj.SetSticky(aEnable);
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
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if aEnable then
      fStickyNames.AddOrSetValue(lNameKey, True)
    else
      fStickyNames.Remove(lNameKey);
    if fNamed.TryGetValue(lNameKey, obj) then
      obj.SetSticky(aEnable);
    if fNamedTyped.TryGetValue(lNameKey, typeDict) then
      for kvInner in typeDict do
        kvInner.Value.SetSticky(aEnable);
  finally
    TMonitor.Exit(fLock);
  end;
end;

  procedure TMLBus.EnableCoalesceOf<T>(const aKeyOf: TMLKeyFunc<T>; aWindowUs: Integer);
var
  key: PTypeInfo;
  obj: TMLTopicBase;
    topic: TTypedTopic<T>;
begin
  key := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(key, obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyTypes.ContainsKey(key) then
        topic.SetSticky(True);
      fTyped.Add(key, topic);
    end
    else
      topic := TTypedTopic<T>(obj);
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
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamedTyped.TryGetValue(lNameKey, typeDict) then
    begin
      typeDict := TMLTypeTopicDict.Create([doOwnsValues]);
      fNamedTyped.Add(lNameKey, typeDict);
    end;
    if not typeDict.TryGetValue(TypeInfo(T), obj) then
    begin
      topic := TTypedTopic<T>.Create;
      if fStickyNames.ContainsKey(lNameKey) or fStickyTypes.ContainsKey(TypeInfo(T)) then
        topic.SetSticky(True);
      typeDict.Add(TypeInfo(T), topic);
    end
    else
      topic := TTypedTopic<T>(obj);
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
begin
  lKey := TypeInfo(T);
  TMonitor.Enter(fLock);
  try
    if not fTyped.TryGetValue(lKey, lObj) then
    begin
      lTopic := TTypedTopic<T>.Create;
      fTyped.Add(lKey, lTopic);
    end
    else
      lTopic := TTypedTopic<T>(lObj);
    lTopic.SetPolicy(aPolicy);
  finally
    TMonitor.Exit(fLock);
  end;
end;

procedure TMLBus.SetPolicyNamed(const aName: string; const aPolicy: TMLQueuePolicy);
var
  lTopic: TMLTopicBase;
  lNameKey: TMLString;
begin
  lNameKey := NormalizeName(aName);
  TMonitor.Enter(fLock);
  try
    if not fNamed.TryGetValue(lNameKey, lTopic) then
    begin
      lTopic := TNamedTopic.Create;
      fNamed.Add(lNameKey, lTopic);
    end;
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

