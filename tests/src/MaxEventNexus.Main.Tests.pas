unit MaxEventNexus.Main.Tests;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
{$DEFINE max_FPC}
{$ELSE}
{$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  // RTL
  Classes, SysUtils, SyncObjs,
  {$IFDEF max_DELPHI} System.Generics.Collections, {$ELSE} Generics.Collections, {$ENDIF}
  // Third-party
  mormot.core.Test,
  // Project
  {$IFDEF max_FPC}
  maxLogic_EventNexus_Threading_Adapter, maxLogic_EventNexus_Threading_RawThread, maxLogic_EventNexus;
  {$ELSE}
  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.RawThread,
  {$IFDEF max_DELPHI} maxLogic.EventNexus.Threading.MaxAsync, maxLogic.EventNexus.Threading.TTask, {$ENDIF}
  maxLogic.EventNexus;
  {$ENDIF}

type
  TKeyed = record
    Key: string;
    Value: integer;
  end;

type
  TTestAggregateException = class(TSynTestCase)
  published
    procedure AggregatesMultiple;
  end;

  TTestAsyncDelivery = class(TSynTestCase)
  published
    procedure AsyncAndBackgroundRunOffPostingThread;
  end;

  TTestCoalesce = class(TSynTestCase)
  published
    procedure DropsIntermediateDeliversLatest;
    procedure ZeroWindowBatchesPosts;
  end;

  TTestFuzz = class(TSynTestCase)
  published
    procedure RandomDeliveryNoDeadlock;
  end;

  TPostBurstThread = class(TThread)
  public
    fBus: ImaxBus;
    fCount: integer;
    constructor Create(const aBus: ImaxBus; aCount: integer);
  protected
    procedure Execute; override;
  end;

  TTestMetrics = class(TSynTestCase)
  published
    procedure CountsPostsAndDelivered;
    procedure CountsDropped;
    procedure CountsExceptions;
  end;

  TPostThread = class(TThread)
  public
    fBus: ImaxBus;
    fValue: integer;
    constructor Create(const aBus: ImaxBus; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TTestNamedTopics = class(TSynTestCase)
  published
    procedure StickyAndCoalesceNamed;
    procedure QueuePolicyAndMetricsNamed;
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

  TTestSticky = class(TSynTestCase)
  published
    procedure LateSubscriberGetsLastEvent;
  end;

  TTarget = class
  private
    fCount: integer;
  public
    procedure Handle(const aValue: integer);
    property Count: integer read fCount;
  end;

  TTestUnsubscribeAll = class(TSynTestCase)
  published
    procedure RemovesAllHandlers;
  end;

  TTestSchedulers = class(TSynTestCase)
  private
    function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): boolean;
    procedure ExerciseScheduler(const aScheduler: IEventNexusScheduler; const aName: string);
  published
    procedure RawThreadScheduler;
    {$IFDEF max_DELPHI}
    procedure MaxAsyncScheduler;
    procedure TTaskScheduler;
    {$ENDIF}
  end;

  TTestGuidTopics = class(TSynTestCase)
  published
    procedure GuidPublishDelivers;
    procedure StickyGuidDeliversLast;
  end;

  {$IFDEF max_DELPHI}
  TTestAutoSubscribe = class(TSynTestCase)
  published
    procedure RegistersTypedNamedAndInherited;
    procedure AutoUnsubscribeClearsHandlers;
    procedure InvalidSignatureRaises;
  end;
  {$ENDIF}

  IIntEvent = interface
    ['{E0A90F15-6C16-4BD7-9057-CC95B2E98F03}']
    function GetValue: integer;
  end;

  TIntEvent = class(TInterfacedObject, IIntEvent)
  private
    fVal: integer;
  public
    constructor Create(aValue: integer);
    function GetValue: integer;
  end;

  TTestQueuePolicy = class(TSynTestCase)
  published
    procedure DropNewestDrops;
    procedure DropOldestRemoves;
    procedure BlockWaits;
    procedure DeadlineDrops;
  end;

  TTestSubscribeOrdering = class(TSynTestCase)
  published
    procedure PreservesOrderAndHandlesChurn;
  end;

  TTestInterfaceGenerics = class(TSynTestCase)
  published
    procedure UsesInterfaceGenerics;
  end;

implementation

uses
  {$IFDEF max_DELPHI} System.IOUtils, {$ENDIF}
  maxLogic.Utils
  {$IFDEF max_DELPHI}, maxLogic.EventNexus.Threading.RawThread{$ENDIF}
  ;

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

{$IFDEF DEBUG}
function LogsDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
end;

var
  glLogCs: TCriticalSection;

procedure LogLine(const aTestName, aLine: string);
var
  lLine, fn: string;
  lBytes: TBytes;
begin
  glLogCs.Enter;
  try
    if not TDirectory.Exists(LogsDir) then
      TDirectory.CreateDirectory(LogsDir);
    fn := TPath.Combine(LogsDir, aTestName + '.log');
    lLine := FormatDateTime('hh:nn:ss.zzz', Now) + ' [T' + IntToStr(TThread.CurrentThread.ThreadID) + '] ' + aLine + sLineBreak+sLineBreak;
    // lBytes:= TEncoding.Utf8.GetBytes(lLine);
    TFile.AppendAllText(fn, lLine, TEncoding.Utf8);
  finally
    glLogCs.Leave;
  end;
end;
{$ENDIF}
{$ENDIF}

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
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('first');
    end);
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('second');
    end);
  {$ENDIF}
  try
    TmaxBus(maxAsBus(lBus)).Post<integer>(42);
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
  lBus := maxBus;
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
    TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        lAsyncId := TThread.CurrentThread.ThreadID;
        lEvAsync.SetEvent;
      end,
      Async);
    TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        lBgId := TThread.CurrentThread.ThreadID;
        lEvBg.SetEvent;
      end,
      Background);
    {$ENDIF}
    {$IFDEF max_DELPHI} LogLine('TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread', 'Subscribed Async and Background'); {$ENDIF}
    TmaxBus(maxAsBus(lBus)).Post<integer>(1);
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

procedure TTestCoalesce.DropsIntermediateDeliversLatest;
var
  lBus: ImaxBusAdvanced;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<TKeyed>;

  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;

  procedure Handler(const aEvt: TKeyed);
  begin
    lLock.Enter;
    try
      lValues.Add(aEvt);
    finally
      lLock.Leave;
    end;
  end;
  {$ELSE}
  lValues: TList<TKeyed>;
  {$ENDIF}
  lLock: TCriticalSection;

  function Make(const k: string; v: integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;

  function FindVal(const k: string): integer;
  var
    t: TKeyed;
  begin
    lLock.Enter;
    try
      for t in lValues do
        if t.Key = k then
          exit(t.Value);
      Result := -1;
    finally
      lLock.Leave;
    end;
  end;
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
    TmaxBus(maxAsBus(lBus)).EnableCoalesceOf<TKeyed>(
      function(const aEvt: TKeyed): TmaxString
      begin
        Result := aEvt.Key;
      end,
      10000);
    lValues := TList<TKeyed>.Create;
    lSub := TmaxBus(maxAsBus(lBus)).Subscribe<TKeyed>(
      procedure(const aEvt: TKeyed)
      begin
        lLock.Enter;
        try
          lValues.Add(aEvt);
        finally
          lLock.Leave;
        end;
      end);
    {$ENDIF}
    try
      {$IFDEF max_FPC}
      lBus.Post<TKeyed>(Make('A', 1));
      lBus.Post<TKeyed>(Make('A', 2));
      lBus.Post<TKeyed>(Make('B', 10));
      lBus.Post<TKeyed>(Make('B', 11));
      {$ELSE}
      TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('A', 1));
      TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('A', 2));
      TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('B', 10));
      TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('B', 11));
      {$ENDIF}
      Sleep(20);
      lLock.Enter;
      try
        CheckEquals(2, lValues.Count);
        CheckEquals(2, FindVal('A'));
        CheckEquals(11, FindVal('B'));
      finally
        lLock.Leave;
      end;
    finally
      lValues.Free;
    end;
  finally
    lLock.Free;
    {$IFDEF max_FPC}
    lBus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    TmaxBus(maxAsBus(lBus)).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
  end;
end;

procedure TTestCoalesce.ZeroWindowBatchesPosts;
var
  lBus: ImaxBusAdvanced;
  lSub: ImaxSubscription;
  {$IFDEF max_FPC}
  lValues: specialize TList<TKeyed>;

  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;

  procedure Handler(const aEvt: TKeyed);
  begin
    lLock.Enter;
    try
      lValues.Add(aEvt);
    finally
      lLock.Leave;
    end;
  end;
  {$ELSE}
  lValues: TList<TKeyed>;
  {$ENDIF}
  lLock: TCriticalSection;

  function Make(const k: string; v: integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;
begin
  lBus := maxBus as ImaxBusAdvanced;
  lBus.Clear;
  lLock := TCriticalSection.Create;
  {$IFDEF max_FPC}
  lBus.EnableCoalesceOf<TKeyed>(@KeyOf, 0);
  lValues := specialize TList<TKeyed>.Create;
  lSub := lBus.Subscribe<TKeyed>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    0);
  lValues := TList<TKeyed>.Create;
  lSub := TmaxBus(maxAsBus(lBus)).Subscribe<TKeyed>(
    procedure(const aEvt: TKeyed)
    begin
      lLock.Enter;
      try
        lValues.Add(aEvt);
      finally
        lLock.Leave;
      end;
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    lBus.Post<TKeyed>(Make('A', 1));
    lBus.Post<TKeyed>(Make('A', 2));
    {$ELSE}
    TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('A', 1));
    TmaxBus(maxAsBus(lBus)).Post<TKeyed>(Make('A', 2));
    {$ENDIF}
    Sleep(1);
    lLock.Enter;
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(2, lValues[0].Value);
    finally
      lLock.Leave;
    end;
  finally
    lValues.Free;
    {$IFDEF max_FPC}
    lBus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    TmaxBus(maxAsBus(lBus)).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
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
    TmaxBus(maxAsBus(fBus)).Post<integer>(i);
  {$ENDIF}
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
  lDelivered := 0;
  for i := Low(lSubs) to High(lSubs) do
  begin
    {$IFDEF max_FPC}
    lSubs[i] := lBus.Subscribe<integer>(@Handler, TmaxDelivery(random(Ord(High(TmaxDelivery)) + 1)));
    {$ELSE}
    lSubs[i] := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
  TmaxBus(maxAsBus(lBus)).SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      lGot := aEvt.GetValue;
    end);
  {$ENDIF}
  TmaxBus(maxAsBus(lBus)).PostGuidOf<IIntEvent>(TIntEvent.Create(5));
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
  TmaxBus(maxAsBus(lBus)).EnableSticky<IIntEvent>(True);
  TmaxBus(maxAsBus(lBus)).PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  {$ENDIF}
  lGot := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeGuidOf<IIntEvent>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).SubscribeGuidOf<IIntEvent>(
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
  TmaxBus(maxAsBus(lBus)).EnableSticky<IIntEvent>(False);
  {$ENDIF}
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
  lBusObj := TmaxBus(maxAsBus(lBus));
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
  lBusObj := TmaxBus(maxAsBus(lBus));
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

procedure TTestAutoSubscribe.InvalidSignatureRaises;
var
  lBad: TBadAutoSub;
  lRaised: boolean;
begin
  lBad := TBadAutoSub.Create;
  try
    maxBus.Clear;
    lRaised := False;
    try
      AutoSubscribe(lBad);
    except
      on E: EmaxInvalidSubscription do
        lRaised := True;
    end;
    Check(lRaised, 'Expected EmaxInvalidSubscription to be raised');
  finally
    AutoUnsubscribe(lBad);
    lBad.Free;
    maxBus.Clear;
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
  TmaxBus(maxAsBus(fBus)).TryPost<integer>(fValue);
  {$ENDIF}
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
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      lGot := aValue;
    end);
  {$ENDIF}
  TmaxBus(maxAsBus(lBus)).Post<integer>(1);
  lMetrics := lBus as ImaxBusMetrics;
  lStats := TmaxBus(maxAsBus(lMetrics)).GetStatsFor<integer>;
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
  t: TPostThread;
  ok: boolean;
  lMetrics: ImaxBusMetrics;
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
  TmaxBus(maxAsBus(lQueues)).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  lCount := 0;
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(lCount);
    end);
  {$ENDIF}
  t := TPostThread.Create(lBus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(2);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DropOldestRemoves', 'TryPost(2)=' + BoolToStr(ok, True)); {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(3);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DropOldestRemoves', 'TryPost(3)=' + BoolToStr(ok, True)); {$ENDIF}
  Check(not ok);
  t.WaitFor;
  t.Free;
  lMetrics := lBus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  lStats := lMetrics.GetStatsFor<integer>;
  {$ELSE}
  lStats := TmaxBus(maxAsBus(lMetrics)).GetStatsFor<integer>;
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
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('boom');
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    lBus.Post<integer>(1);
    {$ELSE}
    TmaxBus(maxAsBus(lBus)).Post<integer>(1);
    {$ENDIF}
  except
    on EmaxDispatchError do ;
  end;
  lMetrics := lBus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  lStats := lMetrics.GetStatsFor<integer>;
  {$ELSE}
  lStats := TmaxBus(maxAsBus(lMetrics)).GetStatsFor<integer>;
  {$ENDIF}
  CheckEquals(1, lStats.ExceptionsTotal);
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
  TmaxBus(maxAsBus(fBus)).TryPostNamedOf<integer>(fName, fValue);
  {$ENDIF}
end;

procedure TTestNamedTopics.StickyAndCoalesceNamed;
var
  lBus: ImaxBus;
  lName: TmaxString;
  lValues: array of integer;
  lCount: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    SetLength(lValues, lCount + 1);
    lValues[lCount] := aValue;
    Inc(lCount);
  end;

  function KeyOf(const aValue: integer): TmaxString;
  begin
    if aValue mod 2 = 0 then
      Result := 'even'
    else
      Result := 'odd';
  end;
  {$ELSE}
  // Delphi uses anonymous function for key selection
  {$ENDIF}
begin
  lBus := maxBus;
  lBus.Clear;
  lName := 'named';
  (lBus as ImaxBusAdvanced).EnableStickyNamed(lName, True);
  {$IFDEF max_FPC}
  lBus.EnableCoalesceNamedOf<integer>(lName, @KeyOf);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).EnableCoalesceNamedOf<integer>(lName,
    function(const aValue: integer): TmaxString
    begin
      if aValue mod 2 = 0 then
        Result := 'even'
      else
        Result := 'odd';
    end);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DropOldestRemoves', 'Policy MaxDepth=1, Overflow=DropOldest'); {$ENDIF}
  {$IFDEF max_FPC}
  lBus.PostNamedOf<integer>(lName, 10);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).PostNamedOf<integer>(lName, 10);
  {$ENDIF}
  lCount := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeNamedOf<integer>(lName, @Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).SubscribeNamedOf<integer>(lName,
    procedure(const aValue: integer)
    begin
      SetLength(lValues, lCount + 1);
      lValues[lCount] := aValue;
      Inc(lCount);
    end);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DeadlineDrops', 'Policy MaxDepth=1, Overflow=Deadline, DeadlineUs=50000'); {$ENDIF}
  {$IFDEF max_FPC}
  lBus.PostNamedOf<integer>(lName, 1);
  lBus.PostNamedOf<integer>(lName, 3);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).PostNamedOf<integer>(lName, 1);
  TmaxBus(maxAsBus(lBus)).PostNamedOf<integer>(lName, 3);
  {$ENDIF}
  Sleep(50);
  CheckEquals(2, lCount);
  CheckEquals(10, lValues[0]);
  CheckEquals(3, lValues[1]);
  (lBus as ImaxBusAdvanced).EnableStickyNamed(lName, False);
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
  lName := 'named';
  lQueues := lBus as ImaxBusQueues;
  lPolicy.MaxDepth := 1;
  lPolicy.Overflow := DropNewest;
  lPolicy.DeadlineUs := 0;
  lQueues.SetPolicyNamed(lName, lPolicy);
  lCount := 0;
  {$IFDEF max_FPC}
  lBus.SubscribeNamedOf<integer>(lName, @Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).SubscribeNamedOf<integer>(lName,
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(lCount);
    end);
  {$ENDIF}
  t := TNamedPostThread.Create(lBus, lName, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := lBus.TryPostNamedOf<integer>(lName, 2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPostNamedOf<integer>(lName, 2);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DeadlineDrops', 'TryPost(2)=' + BoolToStr(ok, True)); {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPostNamedOf<integer>(lName, 3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPostNamedOf<integer>(lName, 3);
  {$ENDIF}
  {$IFDEF max_DELPHI} LogLine('TTestQueuePolicy.DeadlineDrops', 'TryPost(3)=' + BoolToStr(ok, True)); {$ENDIF}
  Check(not ok);
  t.WaitFor;
  t.Free;
  CheckEquals(2, lCount);
  lMetrics := lBus as ImaxBusMetrics;
  lStats := lMetrics.GetStatsNamed(lName);
  CheckEquals(3, lStats.PostsTotal);
  CheckEquals(2, lStats.DeliveredTotal);
  CheckEquals(1, lStats.DroppedTotal);
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
  TmaxBus(maxAsBus(lQueues)).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(3);
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
  TmaxBus(maxAsBus(lQueues)).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(3);
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
  TmaxBus(maxAsBus(lQueues)).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(3);
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
  TmaxBus(maxAsBus(lQueues)).SetPolicyFor<integer>(lPolicy);
  {$ENDIF}
  {$IFDEF max_FPC}
  lBus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := lBus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(lBus)).TryPost<integer>(3);
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
  TmaxBus(maxAsBus(lBus)).EnableSticky<integer>(True);
  {$ELSE}
  lBus.EnableSticky<integer>(True);
  {$ENDIF}
  try
    {$IFDEF max_DELPHI}
    TmaxBus(maxAsBus(lBus)).Post<integer>(42);
    {$ELSE}
    lBus.Post<integer>(42);
    {$ENDIF}
    {$IFDEF max_FPC}
    lValues := specialize TList<integer>.Create;
    lSub := lBus.Subscribe<integer>(@Handler);
    {$ELSE}
    lValues := TList<integer>.Create;
    lSub := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end);
    {$ENDIF}
    try
      CheckEquals(1, lValues.Count);
      CheckEquals(42, lValues[0]);
      {$IFDEF max_DELPHI}
      TmaxBus(maxAsBus(lBus)).Post<integer>(43);
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
    TmaxBus(maxAsBus(lBus)).EnableSticky<integer>(False);
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
  lSub := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
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
      TmaxBus(maxAsBus(lBus)).Post<integer>(i);
    {$ENDIF}
    CheckEquals(5, lValues.Count);
    for i := 1 to 5 do
      CheckEquals(i, lValues[i - 1]);
    lSub.Unsubscribe;
    lValues.Clear;
    {$IFDEF max_FPC}
    lSub := lBus.Subscribe<integer>(@Handler);
    {$ELSE}
    lSub := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        lValues.Add(aValue);
      end);
    {$ENDIF}
    for i := 6 to 10 do
      {$IFDEF max_FPC}
      lBus.Post<integer>(i);
    {$ELSE}
      TmaxBus(maxAsBus(lBus)).Post<integer>(i);
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
    lSub1 := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(lTgt.Handle);
    lSub2 := TmaxBus(maxAsBus(lBus)).Subscribe<integer>(lTgt.Handle);
    {$ENDIF}
    lBus.UnsubscribeAllFor(lTgt);
    {$IFDEF max_FPC}
    lBus.Post<integer>(1);
    {$ELSE}
    TmaxBus(maxAsBus(lBus)).Post<integer>(1);
    {$ENDIF}
    CheckEquals(0, lTgt.Count);
    Check(not lSub1.IsActive);
    Check(not lSub2.IsActive);
  finally
    lTgt.Free;
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
  lDelayStart, lDelayDelta: UInt64;
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
    lDelayDelta := 0;
    aScheduler.RunDelayed(
      procedure
      begin
        lDelayDelta := GetTickCount64 - lDelayStart;
        lDelayEvent.SetEvent;
      end,
      100000);
    Check(WaitForSignal(lDelayEvent, 2000), aName + ': RunDelayed timed out');
    Check(lDelayDelta >= 50, aName + ': RunDelayed executed too early');
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

initialization
  {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
  glLogCs:= TCriticalSection.Create  ;
  {$IFEND}
finalization
  {$IF DEFINED(max_DELPHI) AND DEFINED(DEBUG)}
  FreeAndNil(glLogCs);
  {$IFEND}
end.

