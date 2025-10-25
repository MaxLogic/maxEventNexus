unit MaxEventNexus.Main.Tests;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
{$DEFINE max_FPC}
{$ELSE}
{$DEFINE max_DELPHI}
{$ENDIF}

interface

uses
  mormot.core.Test,
  SysUtils, Classes, SyncObjs,
  {$IFDEF max_DELPHI}
  System.generics.collections,
  {$ELSE}
  generics.collections,
  {$ENDIF}

  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.RawThread,
  {$IFDEF max_DELPHI}
  maxLogic.EventNexus.Threading.maxAsync,
  maxLogic.EventNexus.Threading.TTask,
  {$ENDIF }
  maxLogic.EventNexus;

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
    Bus: ImaxBus;
    Count: integer;
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
    Bus: ImaxBus;
    Value: integer;
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
    Bus: ImaxBus;
      Name: TmaxString;
    Value: integer;
    constructor Create(const aBus: ImaxBus; const AName: TmaxString; aValue: integer);
  protected
    procedure Execute; override;
  end;

  TTestSticky = class(TSynTestCase)
  published
    procedure LateSubscriberGetsLastEvent;
  end;

  TTarget = class
  public
    Count: integer;
    procedure Handle(const aValue: integer);
  end;

  TTestUnsubscribeAll = class(TSynTestCase)
  published
    procedure RemovesAllHandlers;
  end;

  TTestSchedulers = class(TSynTestCase)
  private
    function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): boolean;
    procedure ExerciseScheduler(const aScheduler: IEventNexusScheduler; const AName: string);
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

  IIntEvent = interface
    ['{E0A90F15-6C16-4BD7-9057-CC95B2E98F03}']
    function getValue: integer;
  end;

  TIntEvent = class(TInterfacedObject, IIntEvent)
  private
    fVal: integer;
  public
    constructor Create(aVal: integer);
    function getValue: integer;
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

implementation

uses
  maxLogic.Utils;

{ TTestAggregateException }

procedure TTestAggregateException.AggregatesMultiple;
var
  Bus: ImaxBus;

  {$IFDEF max_FPC}
  procedure first(const aValue: integer);
  begin
    raise Exception.Create('first');
  end;

  procedure Second(const aValue: integer);
  begin
    raise Exception.Create('second');
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@first);
  Bus.Subscribe<integer>(@Second);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('first');
    end);
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('second');
    end);
  {$ENDIF}
  try
    TmaxBus(maxAsBus(Bus)).Post<integer>(42);
    Check(False, 'Expected aggregate exception');
  except
    on e: EmaxAggregateException do
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
  Bus: ImaxBus;
  mainId, asyncId, bgId: TThreadID;
  evAsync, evBg: TEvent;

  {$IFDEF max_FPC}
  procedure AsyncHandler(const aVal: integer);
  begin
    asyncId := TThread.CurrentThread.ThreadID;
    evAsync.SetEvent;
  end;

  procedure BgHandler(const aVal: integer);
  begin
    bgId := TThread.CurrentThread.ThreadID;
    evBg.SetEvent;
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  mainId := TThread.CurrentThread.ThreadID;
  evAsync := TEvent.Create(nil, True, False, '');
  evBg := TEvent.Create(nil, True, False, '');
  try
    {$IFDEF max_FPC}
    Bus.Subscribe<integer>(@AsyncHandler, Async);
    Bus.Subscribe<integer>(@BgHandler, Background);
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        asyncId := TThread.CurrentThread.ThreadID;
        evAsync.SetEvent;
      end,
      Async);
    TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
      procedure(const aVal: integer)
      begin
        bgId := TThread.CurrentThread.ThreadID;
        evBg.SetEvent;
      end,
      Background);
    {$ENDIF}
    TmaxBus(maxAsBus(Bus)).Post<integer>(1);
    Check(evAsync.WaitFor(1000) = wrSignaled);
    Check(evBg.WaitFor(1000) = wrSignaled);
    Check(mainId <> asyncId);
    Check(mainId <> bgId);
  finally
    evAsync.Free;
    evBg.Free;
  end;
end;

{ TTestCoalesce }

procedure TTestCoalesce.DropsIntermediateDeliversLatest;
var
  Bus: ImaxBusAdvanced;
  sub: ImaxSubscription;
  {$IFDEF max_FPC}
  Values: TList<TKeyed>;

  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;

  procedure Handler(const aEvt: TKeyed);
  begin
    Values.Add(aEvt);
  end;
  {$ELSE}
  Values: System.generics.collections.TList<TKeyed>;
  {$ENDIF}

  function Make(const k: string; v: integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;

  function FindVal(const k: string): integer;
  var
    t: TKeyed;
  begin
    for t in Values do
      if t.Key = k then
        exit(t.Value);
    Result := -1;
  end;
begin
  Bus := maxBus as ImaxBusAdvanced;
  Bus.Clear;
  {$IFDEF max_FPC}
  Bus.EnableCoalesceOf<TKeyed>(@KeyOf, 10000);
  Values := TList<TKeyed>.Create;
  sub := Bus.Subscribe<TKeyed>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    10000);
  Values := TList<TKeyed>.Create;
  sub := TmaxBus(maxAsBus(Bus)).Subscribe<TKeyed>(
    procedure(const aEvt: TKeyed)
    begin
      Values.Add(aEvt);
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    Bus.Post<TKeyed>(Make('A', 1));
    Bus.Post<TKeyed>(Make('A', 2));
    Bus.Post<TKeyed>(Make('B', 10));
    Bus.Post<TKeyed>(Make('B', 11));
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('A', 1));
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('A', 2));
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('B', 10));
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('B', 11));
    {$ENDIF}
    Sleep(20);
    CheckEquals(2, Values.Count);
    CheckEquals(2, FindVal('A'));
    CheckEquals(11, FindVal('B'));
  finally
    Values.Free;
    {$IFDEF max_FPC}
    Bus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
  end;
end;

procedure TTestCoalesce.ZeroWindowBatchesPosts;
var
  Bus: ImaxBusAdvanced;
  sub: ImaxSubscription;
  {$IFDEF max_FPC}
  Values: TList<TKeyed>;

  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;

  procedure Handler(const aEvt: TKeyed);
  begin
    Values.Add(aEvt);
  end;
  {$ELSE}
  Values: System.generics.collections.TList<TKeyed>;
  {$ENDIF}

  function Make(const k: string; v: integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;
begin
  Bus := maxBus as ImaxBusAdvanced;
  Bus.Clear;
  {$IFDEF max_FPC}
  Bus.EnableCoalesceOf<TKeyed>(@KeyOf, 0);
  Values := TList<TKeyed>.Create;
  sub := Bus.Subscribe<TKeyed>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    0);
  Values := TList<TKeyed>.Create;
  sub := TmaxBus(maxAsBus(Bus)).Subscribe<TKeyed>(
    procedure(const aEvt: TKeyed)
    begin
      Values.Add(aEvt);
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    Bus.Post<TKeyed>(Make('A', 1));
    Bus.Post<TKeyed>(Make('A', 2));
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('A', 1));
    TmaxBus(maxAsBus(Bus)).Post<TKeyed>(Make('A', 2));
    {$ENDIF}
    Sleep(1);
    CheckEquals(1, Values.Count);
    CheckEquals(2, Values[0].Value);
  finally
    Values.Free;
    {$IFDEF max_FPC}
    Bus.EnableCoalesceOf<TKeyed>(nil);
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).EnableCoalesceOf<TKeyed>(nil);
    {$ENDIF}
  end;
end;

{ TPostBurstThread }

constructor TPostBurstThread.Create(const aBus: ImaxBus; aCount: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Count := aCount;
end;

procedure TPostBurstThread.Execute;
var
  i: integer;
begin
  for i := 1 to Count do
    {$IFDEF max_FPC}
    Bus.Post<integer>(i);
  {$ELSE}
    TmaxBus(maxAsBus(Bus)).Post<integer>(i);
  {$ENDIF}
end;

procedure TTestFuzz.RandomDeliveryNoDeadlock;
const
  cTHREADS = 4;
  POSTS_PER_THREAD = 50;
var
  Bus: ImaxBus;
  subs: array[0..3] of ImaxSubscription;
  threads: array of TPostBurstThread;
  delivered: integer;
  i: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    TInterlocked.Increment(delivered);
  end;
  {$ENDIF}
begin
  Randomize;
  Bus := maxBus;
  Bus.Clear;
  delivered := 0;
  for i := Low(subs) to High(subs) do
  begin
    {$IFDEF max_FPC}
    subs[i] := Bus.Subscribe<integer>(@Handler, TmaxDelivery(random(Ord(High(TmaxDelivery)) + 1)));
    {$ELSE}
    subs[i] := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        TInterlocked.Increment(delivered);
      end,
      TmaxDelivery(random(Ord(High(TmaxDelivery)) + 1)));
    {$ENDIF}
  end;
  SetLength(threads, cTHREADS);
  for i := 0 to cTHREADS - 1 do
  begin
    threads[i] := TPostBurstThread.Create(Bus, POSTS_PER_THREAD);
    threads[i].start;
  end;
  for i := 0 to cTHREADS - 1 do
  begin
    threads[i].WaitFor;
    threads[i].Free;
  end;
  Sleep(200);
  CheckEquals(cTHREADS * POSTS_PER_THREAD * length(subs), delivered);
end;

{ TIntEvent }

constructor TIntEvent.Create(aVal: integer);
begin
  inherited Create;
  fVal := aVal;
end;

function TIntEvent.getValue: integer;
begin
  Result := fVal;
end;

procedure TTestGuidTopics.GuidPublishDelivers;
var
  Bus: ImaxBus;
  got: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    got := aEvt.getValue;
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  got := 0;
  {$IFDEF max_FPC}
  Bus.SubscribeGuidOf<IIntEvent>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      got := aEvt.getValue;
    end);
  {$ENDIF}
  TmaxBus(maxAsBus(Bus)).PostGuidOf<IIntEvent>(TIntEvent.Create(5));
  Sleep(10);
  CheckEquals(5, got);
end;

procedure TTestGuidTopics.StickyGuidDeliversLast;
var
  Bus: ImaxBus;
  got: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    got := aEvt.getValue;
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  {$IFDEF max_FPC}
  Bus.EnableSticky<IIntEvent>(True);
  Bus.PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).EnableSticky<IIntEvent>(True);
  TmaxBus(maxAsBus(Bus)).PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  {$ENDIF}
  got := 0;
  {$IFDEF max_FPC}
  Bus.SubscribeGuidOf<IIntEvent>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      got := aEvt.getValue;
    end);
  {$ENDIF}
  Sleep(10);
  CheckEquals(7, got);
  {$IFDEF max_FPC}
  Bus.EnableSticky<IIntEvent>(False);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).EnableSticky<IIntEvent>(False);
  {$ENDIF}
end;

{ TPostThread }

constructor TPostThread.Create(const aBus: ImaxBus; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Value := aValue;
end;

procedure TPostThread.Execute;
begin
  {$IFDEF max_FPC}
  Bus.TryPost<integer>(Value);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).TryPost<integer>(Value);
  {$ENDIF}
end;

procedure TTestMetrics.CountsPostsAndDelivered;
var
  Bus: ImaxBus;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;
  got: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    got := aValue;
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  got := 0;
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      got := aValue;
    end);
  {$ENDIF}
  TmaxBus(maxAsBus(Bus)).Post<integer>(1);
  metrics := Bus as ImaxBusMetrics;
  stats := TmaxBus(maxAsBus(metrics)).GetStatsFor<integer>;
  CheckEquals(1, stats.PostsTotal);
  CheckEquals(1, stats.DeliveredTotal);
  CheckEquals(0, stats.DroppedTotal);
  CheckEquals(1, got);
end;

procedure TTestMetrics.CountsDropped;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  queues.SetPolicyFor<integer>(policy);
  {$ELSE}
  TmaxBus(maxAsBus(queues)).SetPolicyFor<integer>(policy);
  {$ENDIF}
  Count := 0;
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(Count);
    end);
  {$ENDIF}
  t := TPostThread.Create(Bus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  t.Free;
  metrics := Bus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  stats := metrics.GetStatsFor<integer>;
  {$ELSE}
  stats := TmaxBus(maxAsBus(metrics)).GetStatsFor<integer>;
  {$ENDIF}
  CheckEquals(3, stats.PostsTotal);
  CheckEquals(2, stats.DeliveredTotal);
  CheckEquals(1, stats.DroppedTotal);
end;

procedure TTestMetrics.CountsExceptions;
var
  Bus: ImaxBus;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;

  {$IFDEF max_FPC}
  procedure Failer(const aValue: integer);
  begin
    raise Exception.Create('boom');
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Failer);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      raise Exception.Create('boom');
    end);
  {$ENDIF}
  try
    {$IFDEF max_FPC}
    Bus.Post<integer>(1);
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).Post<integer>(1);
    {$ENDIF}
  except
    on EmaxAggregateException do ;
  end;
  metrics := Bus as ImaxBusMetrics;
  {$IFDEF max_FPC}
  stats := metrics.GetStatsFor<integer>;
  {$ELSE}
  stats := TmaxBus(maxAsBus(metrics)).GetStatsFor<integer>;
  {$ENDIF}
  CheckEquals(1, stats.ExceptionsTotal);
end;

{ TNamedPostThread }

constructor TNamedPostThread.Create(const aBus: ImaxBus; const AName: TmaxString; aValue: integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Name := AName;
  Value := aValue;
end;

procedure TNamedPostThread.Execute;
begin
  {$IFDEF max_FPC}
  Bus.TryPostNamedOf<integer>(Name, Value);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).TryPostNamedOf<integer>(Name, Value);
  {$ENDIF}
end;

procedure TTestNamedTopics.StickyAndCoalesceNamed;
var
  Bus: ImaxBus;
  Name: TmaxString;
  Values: array of integer;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    SetLength(Values, Count + 1);
    Values[Count] := aValue;
    Inc(Count);
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
  Bus := maxBus;
  Bus.Clear;
  Name := 'named';
  (Bus as ImaxBusAdvanced).EnableStickyNamed(Name, True);
  {$IFDEF max_FPC}
  Bus.EnableCoalesceNamedOf<integer>(Name, @KeyOf);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).EnableCoalesceNamedOf<integer>(Name,
    function(const aValue: integer): TmaxString
    begin
      if aValue mod 2 = 0 then
        Result := 'even'
      else
        Result := 'odd';
    end);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.PostNamedOf<integer>(Name, 10);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).PostNamedOf<integer>(Name, 10);
  {$ENDIF}
  Count := 0;
  {$IFDEF max_FPC}
  Bus.SubscribeNamedOf<integer>(Name, @Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).SubscribeNamedOf<integer>(Name,
    procedure(const aValue: integer)
    begin
      SetLength(Values, Count + 1);
      Values[Count] := aValue;
      Inc(Count);
    end);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.PostNamedOf<integer>(Name, 1);
  Bus.PostNamedOf<integer>(Name, 3);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).PostNamedOf<integer>(Name, 1);
  TmaxBus(maxAsBus(Bus)).PostNamedOf<integer>(Name, 3);
  {$ENDIF}
  Sleep(50);
  CheckEquals(2, Count);
  CheckEquals(10, Values[0]);
  CheckEquals(3, Values[1]);
  (Bus as ImaxBusAdvanced).EnableStickyNamed(Name, False);
end;

procedure TTestNamedTopics.QueuePolicyAndMetricsNamed;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  metrics: ImaxBusMetrics;
  policy: TmaxQueuePolicy;
  stats: TmaxTopicStats;
  Name: TmaxString;
  t: TNamedPostThread;
  ok: boolean;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  Name := 'named';
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  queues.SetPolicyNamed(Name, policy);
  Count := 0;
  {$IFDEF max_FPC}
  Bus.SubscribeNamedOf<integer>(Name, @Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).SubscribeNamedOf<integer>(Name,
    procedure(const aValue: integer)
    begin
      Sleep(100);
      Inc(Count);
    end);
  {$ENDIF}
  t := TNamedPostThread.Create(Bus, Name, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPostNamedOf<integer>(Name, 2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPostNamedOf<integer>(Name, 2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPostNamedOf<integer>(Name, 3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPostNamedOf<integer>(Name, 3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  t.Free;
  CheckEquals(2, Count);
  metrics := Bus as ImaxBusMetrics;
  stats := metrics.GetStatsNamed(Name);
  CheckEquals(3, stats.PostsTotal);
  CheckEquals(2, stats.DeliveredTotal);
  CheckEquals(1, stats.DroppedTotal);
end;

{ TTestQueuePolicy }

procedure TTestQueuePolicy.DropNewestDrops;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  delivered: array of integer;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(delivered, Count + 1);
    delivered[Count] := aValue;
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  queues.SetPolicyFor<integer>(policy);
  {$ELSE}
  TmaxBus(maxAsBus(queues)).SetPolicyFor<integer>(policy);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(delivered, Count + 1);
      delivered[Count] := aValue;
      Inc(Count);
    end);
  {$ENDIF}
  t := TPostThread.Create(Bus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  CheckEquals(2, Count);
  CheckEquals(1, delivered[0]);
  CheckEquals(2, delivered[1]);
  t.Free;
end;

procedure TTestQueuePolicy.DropOldestRemoves;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  delivered: array of integer;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(delivered, Count + 1);
    delivered[Count] := aValue;
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropOldest;
  policy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  queues.SetPolicyFor<integer>(policy);
  {$ELSE}
  TmaxBus(maxAsBus(queues)).SetPolicyFor<integer>(policy);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(delivered, Count + 1);
      delivered[Count] := aValue;
      Inc(Count);
    end);
  {$ENDIF}
  t := TPostThread.Create(Bus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  CheckEquals(2, Count);
  CheckEquals(2, delivered[0]);
  CheckEquals(3, delivered[1]);
  t.Free;
end;

procedure TTestQueuePolicy.BlockWaits;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  delivered: array of integer;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(100);
    SetLength(delivered, Count + 1);
    delivered[Count] := aValue;
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := Block;
  policy.DeadlineUs := 0;
  {$IFDEF max_FPC}
  queues.SetPolicyFor<integer>(policy);
  {$ELSE}
  TmaxBus(maxAsBus(queues)).SetPolicyFor<integer>(policy);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(100);
      SetLength(delivered, Count + 1);
      delivered[Count] := aValue;
      Inc(Count);
    end);
  {$ENDIF}
  t := TPostThread.Create(Bus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(3);
  {$ENDIF}
  Check(ok);
  t.WaitFor;
  Sleep(150);
  CheckEquals(3, Count);
  CheckEquals(1, delivered[0]);
  CheckEquals(2, delivered[1]);
  CheckEquals(3, delivered[2]);
  t.Free;
end;

procedure TTestQueuePolicy.DeadlineDrops;
var
  Bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: boolean;
  delivered: array of integer;
  Count: integer;

  {$IFDEF max_FPC}
  procedure Handler(const aValue: integer);
  begin
    Sleep(200);
    SetLength(delivered, Count + 1);
    delivered[Count] := aValue;
    Inc(Count);
  end;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  queues := Bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := deadline;
  policy.DeadlineUs := 50000;
  {$IFDEF max_FPC}
  queues.SetPolicyFor<integer>(policy);
  {$ELSE}
  TmaxBus(maxAsBus(queues)).SetPolicyFor<integer>(policy);
  {$ENDIF}
  {$IFDEF max_FPC}
  Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Sleep(200);
      SetLength(delivered, Count + 1);
      delivered[Count] := aValue;
      Inc(Count);
    end);
  {$ENDIF}
  t := TPostThread.Create(Bus, 1);
  t.start;
  Sleep(10);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(2);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(2);
  {$ENDIF}
  Check(ok);
  {$IFDEF max_FPC}
  ok := Bus.TryPost<integer>(3);
  {$ELSE}
  ok := TmaxBus(maxAsBus(Bus)).TryPost<integer>(3);
  {$ENDIF}
  Check(not ok);
  t.WaitFor;
  Sleep(250);
  CheckEquals(1, Count);
  CheckEquals(1, delivered[0]);
  t.Free;
end;

{ TTestSticky }

procedure TTestSticky.LateSubscriberGetsLastEvent;
var
  Bus: ImaxBus;
  sub: ImaxSubscription;
  {$IFDEF max_FPC}
  Values: TList<integer>;

  procedure Handler(const aValue: integer);
  begin
    Values.Add(aValue);
  end;
  {$ELSE}
  Values: System.generics.collections.TList<integer>;
  {$ENDIF}
begin
  Bus := maxBus;
  Bus.Clear;
  {$IFDEF max_DELPHI}
  TmaxBus(maxAsBus(Bus)).EnableSticky<integer>(True);
  {$ELSE}
  Bus.EnableSticky<integer>(True);
  {$ENDIF}
  try
    {$IFDEF max_DELPHI}
    TmaxBus(maxAsBus(Bus)).Post<integer>(42);
    {$ELSE}
    Bus.Post<integer>(42);
    {$ENDIF}
    {$IFDEF max_FPC}
    Values := TList<integer>.Create;
    sub := Bus.Subscribe<integer>(@Handler);
    {$ELSE}
    Values := TList<integer>.Create;
    sub := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Values.Add(aValue);
      end);
    {$ENDIF}
    try
      CheckEquals(1, Values.Count);
      CheckEquals(42, Values[0]);
      {$IFDEF max_DELPHI}
      TmaxBus(maxAsBus(Bus)).Post<integer>(43);
      {$ELSE}
      Bus.Post<integer>(43);
      {$ENDIF}
      CheckEquals(2, Values.Count);
      CheckEquals(43, Values[1]);
    finally
      Values.Free;
    end;
  finally
    {$IFDEF max_DELPHI}
    TmaxBus(maxAsBus(Bus)).EnableSticky<integer>(False);
    {$ELSE}
    Bus.EnableSticky<integer>(False);
    {$ENDIF}
  end;
end;

{ TTestSubscribeOrdering }

procedure TTestSubscribeOrdering.PreservesOrderAndHandlesChurn;
var
  Bus: ImaxBus;
  sub: ImaxSubscription;
  {$IFDEF max_FPC}
  Values: TList<integer>;

  procedure Handler(const aValue: integer);
  begin
    Values.Add(aValue);
  end;
  {$ELSE}
  Values: System.generics.collections.TList<integer>;
  {$ENDIF}
  i: integer;
begin
  Bus := maxBus;
  Bus.Clear;
  {$IFDEF max_FPC}
  Values := TList<integer>.Create;
  sub := Bus.Subscribe<integer>(@Handler);
  {$ELSE}
  Values := TList<integer>.Create;
  sub := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
    procedure(const aValue: integer)
    begin
      Values.Add(aValue);
    end);
  {$ENDIF}
  try
    for i := 1 to 5 do
      {$IFDEF max_FPC}
      Bus.Post<integer>(i);
    {$ELSE}
      TmaxBus(maxAsBus(Bus)).Post<integer>(i);
    {$ENDIF}
    CheckEquals(5, Values.Count);
    for i := 1 to 5 do
      CheckEquals(i, Values[i - 1]);
    sub.Unsubscribe;
    Values.Clear;
    {$IFDEF max_FPC}
    sub := Bus.Subscribe<integer>(@Handler);
    {$ELSE}
    sub := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(
      procedure(const aValue: integer)
      begin
        Values.Add(aValue);
      end);
    {$ENDIF}
    for i := 6 to 10 do
      {$IFDEF max_FPC}
      Bus.Post<integer>(i);
    {$ELSE}
      TmaxBus(maxAsBus(Bus)).Post<integer>(i);
    {$ENDIF}
    CheckEquals(5, Values.Count);
    for i := 0 to 4 do
      CheckEquals(6 + i, Values[i]);
  finally
    Values.Free;
  end;
end;

{ TTarget }

procedure TTarget.Handle(const aValue: integer);
begin
  Inc(Count);
end;

procedure TTestUnsubscribeAll.RemovesAllHandlers;
var
  Bus: ImaxBus;
  tgt: TTarget;
  sub1, sub2: ImaxSubscription;
begin
  Bus := maxBus;
  tgt := TTarget.Create;
  try
    {$IFDEF max_FPC}
    sub1 := Bus.Subscribe<integer>(@tgt.Handle);
    sub2 := Bus.Subscribe<integer>(@tgt.Handle);
    {$ELSE}
    sub1 := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(tgt.Handle);
    sub2 := TmaxBus(maxAsBus(Bus)).Subscribe<integer>(tgt.Handle);
    {$ENDIF}
    Bus.UnsubscribeAllFor(tgt);
    {$IFDEF max_FPC}
    Bus.Post<integer>(1);
    {$ELSE}
    TmaxBus(maxAsBus(Bus)).Post<integer>(1);
    {$ENDIF}
    CheckEquals(0, tgt.Count);
    Check(not sub1.IsActive);
    Check(not sub2.IsActive);
  finally
    tgt.Free;
  end;
end;

{ TTestSchedulers }

function TTestSchedulers.WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): boolean;
var
  start: uInt64;
begin
  // NOTE: Do not use a single blocking WaitFor(aTimeoutMs) here.
  // In a console test runner there is no UI message loop. Any code scheduled to the
  // main thread (TThread.Synchronize/Queue or RunOnMain) will only execute when the
  // main thread calls CheckSynchronize. If we block inside WaitFor, those callbacks
  // never run, the event may never be signaled, and tests would hang or time out.
  // We therefore poll the event (WaitFor(0)), pump the synchronize queue, then yield.
  start := GetTickCount64;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      exit(True);

    CheckSynchronize(0);
    Sleep(1);
  until GetTickCount64 - start >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

procedure TTestSchedulers.ExerciseScheduler(const aScheduler: IEventNexusScheduler; const AName: string);
var
  mainId, asyncId, mainHandlerId: TThreadID;
  asyncEvent, mainEvent, delayEvent: TEvent;
  delayStart, delayDelta: uInt64;
begin
  asyncEvent := TEvent.Create(nil, True, False, '');
  mainEvent := TEvent.Create(nil, True, False, '');
  delayEvent := TEvent.Create(nil, True, False, '');
  try
    mainId := TThread.CurrentThread.ThreadID;
    asyncId := mainId;
    mainHandlerId := 0;

    aScheduler.RunAsync(
      procedure
      begin
        asyncId := TThread.CurrentThread.ThreadID;
        asyncEvent.SetEvent;
      end);
    Check(WaitForSignal(asyncEvent, 1000), AName + ': RunAsync timed out');
    Check(asyncId <> mainId, AName + ': RunAsync executed on main thread');

    aScheduler.RunOnMain(
      procedure
      begin
        mainHandlerId := TThread.CurrentThread.ThreadID;
        mainEvent.SetEvent;
      end);
    Check(WaitForSignal(mainEvent, 1000), AName + ': RunOnMain timed out');
    CheckEquals(mainId, mainHandlerId, AName + ': RunOnMain did not execute on main thread');

    delayStart := GetTickCount64;
    delayDelta := 0;
    aScheduler.RunDelayed(
      procedure
      begin
        delayDelta := GetTickCount64 - delayStart;
        delayEvent.SetEvent;
      end,
      100000);
    Check(WaitForSignal(delayEvent, 2000), AName + ': RunDelayed timed out');
    Check(delayDelta >= 50, AName + ': RunDelayed executed too early');
  finally
    asyncEvent.Free;
    mainEvent.Free;
    delayEvent.Free;
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

end.

