program MaxEventNexusTests;

{$I ../fpc_delphimode.inc}

{$IFDEF FPC}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

uses
  mormot.core.test,
  SysUtils, Classes, {$IFDEF max_FPC} Generics.Collections, SyncObjs, {$ELSE} System.Generics.Collections, System.SyncObjs, {$ENDIF}
  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.RawThread,
  {$IFDEF max_DELPHI} maxLogic.EventNexus.Threading.MaxAsync, maxLogic.EventNexus.Threading.TTask, {$ENDIF}
  maxLogic.EventNexus in '..\maxLogic.EventNexus.pas';

type
  TKeyed = record
    Key: string;
    Value: Integer;
  end;

type
  TTestAggregateException = class(TSynTestCase)
  published
    procedure AggregatesMultiple;
  end;

procedure TTestAggregateException.AggregatesMultiple;
var
  bus: ImaxBus;
{$IFDEF max_FPC}
  procedure First(const aValue: Integer);
  begin
    raise Exception.Create('first');
  end;
  procedure Second(const aValue: Integer);
  begin
    raise Exception.Create('second');
  end;
{$ENDIF}
begin
  bus := maxBus;
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@First);
  bus.Subscribe<Integer>(@Second);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      raise Exception.Create('first');
    end);
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      raise Exception.Create('second');
    end);
{$ENDIF}
  try
    bus.Post<Integer>(42);
    Check(False, 'Expected aggregate exception');
  except
    on e: EmaxAggregateException do
    begin
      CheckEquals(2, e.Inner.Count);
      CheckEquals('first', e.Inner[0].Message);
      CheckEquals('second', e.Inner[1].Message);
    end;
  end;
end;

  TTestAsyncDelivery = class(TSynTestCase)
  published
    procedure AsyncAndBackgroundRunOffPostingThread;
  end;

procedure TTestAsyncDelivery.AsyncAndBackgroundRunOffPostingThread;
var
  bus: ImaxBus;
  mainId, asyncId, bgId: TThreadID;
  evAsync, evBg: TEvent;
{$IFDEF max_FPC}
  procedure AsyncHandler(const aVal: Integer);
  begin
    asyncId := TThread.CurrentThread.ThreadID;
    evAsync.SetEvent;
  end;
  procedure BgHandler(const aVal: Integer);
  begin
    bgId := TThread.CurrentThread.ThreadID;
    evBg.SetEvent;
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  mainId := TThread.CurrentThread.ThreadID;
  evAsync := TEvent.Create(nil, True, False, '');
  evBg := TEvent.Create(nil, True, False, '');
  try
{$IFDEF max_FPC}
    bus.Subscribe<Integer>(@AsyncHandler, Async);
    bus.Subscribe<Integer>(@BgHandler, Background);
{$ELSE}
    bus.Subscribe<Integer>(
      procedure(const aVal: Integer)
      begin
        asyncId := TThread.CurrentThread.ThreadID;
        evAsync.SetEvent;
      end,
      Async);
    bus.Subscribe<Integer>(
      procedure(const aVal: Integer)
      begin
        bgId := TThread.CurrentThread.ThreadID;
        evBg.SetEvent;
      end,
      Background);
{$ENDIF}
    bus.Post<Integer>(1);
    Check(evAsync.WaitFor(1000) = wrSignaled);
    Check(evBg.WaitFor(1000) = wrSignaled);
    Check(mainId <> asyncId);
    Check(mainId <> bgId);
  finally
    evAsync.Free;
    evBg.Free;
  end;
end;

  TTestCoalesce = class(TSynTestCase)
  published
    procedure DropsIntermediateDeliversLatest;
    procedure ZeroWindowBatchesPosts;
  end;

procedure TTestCoalesce.DropsIntermediateDeliversLatest;
var
  bus: ImaxBusAdvanced;
  sub: ImaxSubscription;
{$IFDEF max_FPC}
  values: TList<TKeyed>;
  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;
  procedure Handler(const aEvt: TKeyed);
  begin
    values.Add(aEvt);
  end;
{$ELSE}
  values: TList<TKeyed>;
{$ENDIF}
  function Make(const k: string; v: Integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;
  function FindVal(const k: string): Integer;
  var
    t: TKeyed;
  begin
    for t in values do
      if t.Key = k then
        Exit(t.Value);
    Result := -1;
  end;
begin
  bus := maxBus as ImaxBusAdvanced;
  bus.Clear;
{$IFDEF max_FPC}
  bus.EnableCoalesceOf<TKeyed>(@KeyOf, 10000);
  values := TList<TKeyed>.Create;
  sub := bus.Subscribe<TKeyed>(@Handler);
{$ELSE}
  bus.EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    10000);
  values := TList<TKeyed>.Create;
  sub := bus.Subscribe<TKeyed>(
    procedure(const aEvt: TKeyed)
    begin
      values.Add(aEvt);
    end);
{$ENDIF}
  try
    bus.Post<TKeyed>(Make('A', 1));
    bus.Post<TKeyed>(Make('A', 2));
    bus.Post<TKeyed>(Make('B', 10));
    bus.Post<TKeyed>(Make('B', 11));
    Sleep(20);
    CheckEquals(2, values.Count);
    CheckEquals(2, FindVal('A'));
    CheckEquals(11, FindVal('B'));
  finally
    values.Free;
    bus.EnableCoalesceOf<TKeyed>(nil);
  end;
end;

procedure TTestCoalesce.ZeroWindowBatchesPosts;
var
  bus: ImaxBusAdvanced;
  sub: ImaxSubscription;
{$IFDEF max_FPC}
  values: TList<TKeyed>;
  function KeyOf(const aEvt: TKeyed): TmaxString;
  begin
    Result := aEvt.Key;
  end;
  procedure Handler(const aEvt: TKeyed);
  begin
    values.Add(aEvt);
  end;
{$ELSE}
  values: TList<TKeyed>;
{$ENDIF}
  function Make(const k: string; v: Integer): TKeyed;
  begin
    Result.Key := k;
    Result.Value := v;
  end;
begin
  bus := maxBus as ImaxBusAdvanced;
  bus.Clear;
{$IFDEF max_FPC}
  bus.EnableCoalesceOf<TKeyed>(@KeyOf, 0);
  values := TList<TKeyed>.Create;
  sub := bus.Subscribe<TKeyed>(@Handler);
{$ELSE}
  bus.EnableCoalesceOf<TKeyed>(
    function(const aEvt: TKeyed): TmaxString
    begin
      Result := aEvt.Key;
    end,
    0);
  values := TList<TKeyed>.Create;
  sub := bus.Subscribe<TKeyed>(
    procedure(const aEvt: TKeyed)
    begin
      values.Add(aEvt);
    end);
{$ENDIF}
  try
    bus.Post<TKeyed>(Make('A', 1));
    bus.Post<TKeyed>(Make('A', 2));
    Sleep(1);
    CheckEquals(1, values.Count);
    CheckEquals(2, values[0].Value);
  finally
    values.Free;
    bus.EnableCoalesceOf<TKeyed>(nil);
  end;
end;

  TTestFuzz = class(TSynTestCase)
  published
    procedure RandomDeliveryNoDeadlock;
  end;

  TPostBurstThread = class(TThread)
  public
    Bus: ImaxBus;
    Count: Integer;
    constructor Create(const aBus: ImaxBus; aCount: Integer);
  protected
    procedure Execute; override;
  end;

constructor TPostBurstThread.Create(const aBus: ImaxBus; aCount: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Count := aCount;
end;

procedure TPostBurstThread.Execute;
var
  i: Integer;
begin
  for i := 1 to Count do
    Bus.Post<Integer>(i);
end;

procedure TTestFuzz.RandomDeliveryNoDeadlock;
const
  THREADS = 4;
  POSTS_PER_THREAD = 50;
var
  bus: ImaxBus;
  subs: array[0..3] of ImaxSubscription;
  threads: array of TPostBurstThread;
  delivered: Integer;
  i: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    TInterlocked.Increment(delivered);
  end;
{$ENDIF}
begin
  Randomize;
  bus := maxBus;
  bus.Clear;
  delivered := 0;
  for i := Low(subs) to High(subs) do
  begin
{$IFDEF max_FPC}
    subs[i] := bus.Subscribe<Integer>(@Handler, TmaxDelivery(Random(Ord(High(TmaxDelivery)) + 1)));
{$ELSE}
    subs[i] := bus.Subscribe<Integer>(
      procedure(const aValue: Integer)
      begin
        TInterlocked.Increment(delivered);
      end,
      TmaxDelivery(Random(Ord(High(TmaxDelivery)) + 1)));
{$ENDIF}
  end;
  SetLength(threads, THREADS);
  for i := 0 to THREADS - 1 do
  begin
    threads[i] := TPostBurstThread.Create(bus, POSTS_PER_THREAD);
    threads[i].Start;
  end;
  for i := 0 to THREADS - 1 do
  begin
    threads[i].WaitFor;
    threads[i].Free;
  end;
  Sleep(200);
  CheckEquals(THREADS * POSTS_PER_THREAD * Length(subs), delivered);
end;

  TTestGuidTopics = class(TSynTestCase)
  published
    procedure GuidPublishDelivers;
    procedure StickyGuidDeliversLast;
  end;

  IIntEvent = interface
    ['{E0A90F15-6C16-4BD7-9057-CC95B2E98F03}']
    function GetValue: Integer;
  end;

  TIntEvent = class(TInterfacedObject, IIntEvent)
  private
    fVal: Integer;
  public
    constructor Create(aVal: Integer);
    function GetValue: Integer;
  end;

constructor TIntEvent.Create(aVal: Integer);
begin
  inherited Create;
  fVal := aVal;
end;

function TIntEvent.GetValue: Integer;
begin
  Result := fVal;
end;

procedure TTestGuidTopics.GuidPublishDelivers;
var
  bus: ImaxBus;
  got: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    got := aEvt.GetValue;
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  got := 0;
{$IFDEF max_FPC}
  bus.SubscribeGuidOf<IIntEvent>(@Handler);
{$ELSE}
  bus.SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      got := aEvt.GetValue;
    end);
{$ENDIF}
  bus.PostGuidOf<IIntEvent>(TIntEvent.Create(5));
  Sleep(10);
  CheckEquals(5, got);
end;

procedure TTestGuidTopics.StickyGuidDeliversLast;
var
  bus: ImaxBus;
  got: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aEvt: IIntEvent);
  begin
    got := aEvt.GetValue;
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  bus.EnableSticky<IIntEvent>(True);
  bus.PostGuidOf<IIntEvent>(TIntEvent.Create(7));
  got := 0;
{$IFDEF max_FPC}
  bus.SubscribeGuidOf<IIntEvent>(@Handler);
{$ELSE}
  bus.SubscribeGuidOf<IIntEvent>(
    procedure(const aEvt: IIntEvent)
    begin
      got := aEvt.GetValue;
    end);
{$ENDIF}
  Sleep(10);
  CheckEquals(7, got);
  bus.EnableSticky<IIntEvent>(False);
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
    Value: Integer;
    constructor Create(const aBus: ImaxBus; aValue: Integer);
  protected
    procedure Execute; override;
  end;

constructor TPostThread.Create(const aBus: ImaxBus; aValue: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Value := aValue;
end;

procedure TPostThread.Execute;
begin
  Bus.TryPost<Integer>(Value);
end;

procedure TTestMetrics.CountsPostsAndDelivered;
var
  bus: ImaxBus;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;
  got: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    got := aValue;
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  got := 0;
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      got := aValue;
    end);
{$ENDIF}
  bus.Post<Integer>(1);
  metrics := bus as ImaxBusMetrics;
  stats := metrics.GetStatsFor<Integer>;
  CheckEquals(1, stats.PostsTotal);
  CheckEquals(1, stats.DeliveredTotal);
  CheckEquals(0, stats.DroppedTotal);
  CheckEquals(1, got);
end;

procedure TTestMetrics.CountsDropped;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: Boolean;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(100);
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  queues.SetPolicyFor<Integer>(policy);
  count := 0;
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Sleep(100);
      Inc(count);
    end);
{$ENDIF}
  t := TPostThread.Create(bus, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPost<Integer>(2);
  Check(ok);
  ok := bus.TryPost<Integer>(3);
  Check(not ok);
  t.WaitFor;
  t.Free;
  metrics := bus as ImaxBusMetrics;
  stats := metrics.GetStatsFor<Integer>;
  CheckEquals(3, stats.PostsTotal);
  CheckEquals(2, stats.DeliveredTotal);
  CheckEquals(1, stats.DroppedTotal);
end;

procedure TTestMetrics.CountsExceptions;
var
  bus: ImaxBus;
  metrics: ImaxBusMetrics;
  stats: TmaxTopicStats;
{$IFDEF max_FPC}
  procedure Failer(const aValue: Integer);
  begin
    raise Exception.Create('boom');
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Failer);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      raise Exception.Create('boom');
    end);
{$ENDIF}
  try
    bus.Post<Integer>(1);
  except
    on EmaxAggregateException do;
  end;
  metrics := bus as ImaxBusMetrics;
  stats := metrics.GetStatsFor<Integer>;
  CheckEquals(1, stats.ExceptionsTotal);
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
    Value: Integer;
    constructor Create(const aBus: ImaxBus; const aName: TmaxString; aValue: Integer);
  protected
    procedure Execute; override;
  end;

constructor TNamedPostThread.Create(const aBus: ImaxBus; const aName: TmaxString; aValue: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Bus := aBus;
  Name := aName;
  Value := aValue;
end;

procedure TNamedPostThread.Execute;
begin
  Bus.TryPostNamedOf<Integer>(Name, Value);
end;

procedure TTestNamedTopics.StickyAndCoalesceNamed;
var
  bus: ImaxBus;
  name: TmaxString;
  values: array of Integer;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    SetLength(values, count + 1);
    values[count] := aValue;
    Inc(count);
  end;
  function KeyOf(const aValue: Integer): TmaxString;
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
  bus := maxBus;
  bus.Clear;
  name := 'named';
  bus.EnableStickyNamed(name, True);
{$IFDEF max_FPC}
  bus.EnableCoalesceNamedOf<Integer>(name, @KeyOf);
{$ELSE}
  bus.EnableCoalesceNamedOf<Integer>(name,
    function(const aValue: Integer): TmaxString
    begin
      if aValue mod 2 = 0 then
        Result := 'even'
      else
        Result := 'odd';
    end);
{$ENDIF}
  bus.PostNamedOf<Integer>(name, 10);
  count := 0;
{$IFDEF max_FPC}
  bus.SubscribeNamedOf<Integer>(name, @Handler);
{$ELSE}
  bus.SubscribeNamedOf<Integer>(name,
    procedure(const aValue: Integer)
    begin
      SetLength(values, count + 1);
      values[count] := aValue;
      Inc(count);
    end);
{$ENDIF}
  bus.PostNamedOf<Integer>(name, 1);
  bus.PostNamedOf<Integer>(name, 3);
  Sleep(50);
  CheckEquals(2, count);
  CheckEquals(10, values[0]);
  CheckEquals(3, values[1]);
  bus.EnableStickyNamed(name, False);
end;

procedure TTestNamedTopics.QueuePolicyAndMetricsNamed;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  metrics: ImaxBusMetrics;
  policy: TmaxQueuePolicy;
  stats: TmaxTopicStats;
  name: TmaxString;
  t: TNamedPostThread;
  ok: Boolean;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(100);
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  name := 'named';
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  queues.SetPolicyNamed(name, policy);
  count := 0;
{$IFDEF max_FPC}
  bus.SubscribeNamedOf<Integer>(name, @Handler);
{$ELSE}
  bus.SubscribeNamedOf<Integer>(name,
    procedure(const aValue: Integer)
    begin
      Sleep(100);
      Inc(count);
    end);
{$ENDIF}
  t := TNamedPostThread.Create(bus, name, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPostNamedOf<Integer>(name, 2);
  Check(ok);
  ok := bus.TryPostNamedOf<Integer>(name, 3);
  Check(not ok);
  t.WaitFor;
  t.Free;
  CheckEquals(2, count);
  metrics := bus as ImaxBusMetrics;
  stats := metrics.GetStatsNamed(name);
  CheckEquals(3, stats.PostsTotal);
  CheckEquals(2, stats.DeliveredTotal);
  CheckEquals(1, stats.DroppedTotal);
end;

  TTestQueuePolicy = class(TSynTestCase)
  published
    procedure DropNewestDrops;
    procedure DropOldestRemoves;
    procedure BlockWaits;
    procedure DeadlineDrops;
  end;

procedure TTestQueuePolicy.DropNewestDrops;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: Boolean;
  delivered: array of Integer;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(100);
    SetLength(delivered, count + 1);
    delivered[count] := aValue;
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropNewest;
  policy.DeadlineUs := 0;
  queues.SetPolicyFor<Integer>(policy);
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Sleep(100);
      SetLength(delivered, count + 1);
      delivered[count] := aValue;
      Inc(count);
    end);
{$ENDIF}
  t := TPostThread.Create(bus, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPost<Integer>(2);
  Check(ok);
  ok := bus.TryPost<Integer>(3);
  Check(not ok);
  t.WaitFor;
  CheckEquals(2, count);
  CheckEquals(1, delivered[0]);
  CheckEquals(2, delivered[1]);
  t.Free;
end;

procedure TTestQueuePolicy.DropOldestRemoves;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: Boolean;
  delivered: array of Integer;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(100);
    SetLength(delivered, count + 1);
    delivered[count] := aValue;
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := DropOldest;
  policy.DeadlineUs := 0;
  queues.SetPolicyFor<Integer>(policy);
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Sleep(100);
      SetLength(delivered, count + 1);
      delivered[count] := aValue;
      Inc(count);
    end);
{$ENDIF}
  t := TPostThread.Create(bus, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPost<Integer>(2);
  Check(ok);
  ok := bus.TryPost<Integer>(3);
  Check(not ok);
  t.WaitFor;
  CheckEquals(2, count);
  CheckEquals(2, delivered[0]);
  CheckEquals(3, delivered[1]);
  t.Free;
end;

procedure TTestQueuePolicy.BlockWaits;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: Boolean;
  delivered: array of Integer;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(100);
    SetLength(delivered, count + 1);
    delivered[count] := aValue;
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := Block;
  policy.DeadlineUs := 0;
  queues.SetPolicyFor<Integer>(policy);
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Sleep(100);
      SetLength(delivered, count + 1);
      delivered[count] := aValue;
      Inc(count);
    end);
{$ENDIF}
  t := TPostThread.Create(bus, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPost<Integer>(2);
  Check(ok);
  ok := bus.TryPost<Integer>(3);
  Check(ok);
  t.WaitFor;
  Sleep(150);
  CheckEquals(3, count);
  CheckEquals(1, delivered[0]);
  CheckEquals(2, delivered[1]);
  CheckEquals(3, delivered[2]);
  t.Free;
end;

procedure TTestQueuePolicy.DeadlineDrops;
var
  bus: ImaxBus;
  queues: ImaxBusQueues;
  policy: TmaxQueuePolicy;
  t: TPostThread;
  ok: Boolean;
  delivered: array of Integer;
  count: Integer;
{$IFDEF max_FPC}
  procedure Handler(const aValue: Integer);
  begin
    Sleep(200);
    SetLength(delivered, count + 1);
    delivered[count] := aValue;
    Inc(count);
  end;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  queues := bus as ImaxBusQueues;
  policy.MaxDepth := 1;
  policy.Overflow := Deadline;
  policy.DeadlineUs := 50000;
  queues.SetPolicyFor<Integer>(policy);
{$IFDEF max_FPC}
  bus.Subscribe<Integer>(@Handler);
{$ELSE}
  bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      Sleep(200);
      SetLength(delivered, count + 1);
      delivered[count] := aValue;
      Inc(count);
    end);
{$ENDIF}
  t := TPostThread.Create(bus, 1);
  t.Start;
  Sleep(10);
  ok := bus.TryPost<Integer>(2);
  Check(ok);
  ok := bus.TryPost<Integer>(3);
  Check(not ok);
  t.WaitFor;
  Sleep(250);
  CheckEquals(1, count);
  CheckEquals(1, delivered[0]);
  t.Free;
end;

  TTestSticky = class(TSynTestCase)
  published
    procedure LateSubscriberGetsLastEvent;
  end;

procedure TTestSticky.LateSubscriberGetsLastEvent;
var
  bus: ImaxBus;
  sub: ImaxSubscription;
{$IFDEF max_FPC}
  values: TList<Integer>;
  procedure Handler(const aValue: Integer);
  begin
    values.Add(aValue);
  end;
{$ELSE}
  values: TList<Integer>;
{$ENDIF}
begin
  bus := maxBus;
  bus.Clear;
  bus.EnableSticky<Integer>(True);
  try
    bus.Post<Integer>(42);
{$IFDEF max_FPC}
    values := TList<Integer>.Create;
    sub := bus.Subscribe<Integer>(@Handler);
{$ELSE}
    values := TList<Integer>.Create;
    sub := bus.Subscribe<Integer>(
      procedure(const aValue: Integer)
      begin
        values.Add(aValue);
      end);
{$ENDIF}
    try
      CheckEquals(1, values.Count);
      CheckEquals(42, values[0]);
      bus.Post<Integer>(43);
      CheckEquals(2, values.Count);
      CheckEquals(43, values[1]);
    finally
      values.Free;
    end;
  finally
    bus.EnableSticky<Integer>(False);
  end;
end;

  TTestSubscribeOrdering = class(TSynTestCase)
  published
    procedure PreservesOrderAndHandlesChurn;
  end;

procedure TTestSubscribeOrdering.PreservesOrderAndHandlesChurn;
var
  bus: ImaxBus;
  sub: ImaxSubscription;
{$IFDEF max_FPC}
  values: TList<Integer>;
  procedure Handler(const aValue: Integer);
  begin
    values.Add(aValue);
  end;
{$ELSE}
  values: TList<Integer>;
{$ENDIF}
  i: Integer;
begin
  bus := maxBus;
  bus.Clear;
{$IFDEF max_FPC}
  values := TList<Integer>.Create;
  sub := bus.Subscribe<Integer>(@Handler);
{$ELSE}
  values := TList<Integer>.Create;
  sub := bus.Subscribe<Integer>(
    procedure(const aValue: Integer)
    begin
      values.Add(aValue);
    end);
{$ENDIF}
  try
    for i := 1 to 5 do
      bus.Post<Integer>(i);
    CheckEquals(5, values.Count);
    for i := 1 to 5 do
      CheckEquals(i, values[i-1]);
    sub.Unsubscribe;
    values.Clear;
{$IFDEF max_FPC}
    sub := bus.Subscribe<Integer>(@Handler);
{$ELSE}
    sub := bus.Subscribe<Integer>(
      procedure(const aValue: Integer)
      begin
        values.Add(aValue);
      end);
{$ENDIF}
    for i := 6 to 10 do
      bus.Post<Integer>(i);
    CheckEquals(5, values.Count);
    for i := 0 to 4 do
      CheckEquals(6 + i, values[i]);
  finally
    values.Free;
  end;
end;

  TTarget = class
  public
    Count: Integer;
    procedure Handle(const aValue: Integer);
  end;

  TTestUnsubscribeAll = class(TSynTestCase)
  published
    procedure RemovesAllHandlers;
  end;

procedure TTarget.Handle(const aValue: Integer);
begin
  Inc(Count);
end;

procedure TTestUnsubscribeAll.RemovesAllHandlers;
var
  bus: ImaxBus;
  tgt: TTarget;
  sub1, sub2: ImaxSubscription;
begin
  bus := maxBus;
  tgt := TTarget.Create;
  try
{$IFDEF max_FPC}
    sub1 := bus.Subscribe<Integer>(@tgt.Handle);
    sub2 := bus.Subscribe<Integer>(@tgt.Handle);
{$ELSE}
    sub1 := bus.Subscribe<Integer>(tgt.Handle);
    sub2 := bus.Subscribe<Integer>(tgt.Handle);
{$ENDIF}
    bus.UnsubscribeAllFor(tgt);
    bus.Post<Integer>(1);
    CheckEquals(0, tgt.Count);
    Check(not sub1.IsActive);
    Check(not sub2.IsActive);
  finally
    tgt.Free;
  end;
  end;

  TTestSchedulers = class(TSynTestCase)
  private
    function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): Boolean;
    procedure ExerciseScheduler(const aScheduler: IEventNexusScheduler; const aName: string);
  published
    procedure RawThreadScheduler;
  {$IFDEF max_DELPHI}
    procedure MaxAsyncScheduler;
    procedure TTaskScheduler;
  {$ENDIF}
  end;

function TTestSchedulers.WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): Boolean;
var
  start: UInt64;
begin
  start := GetTickCount64;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      Exit(True);
  {$IFDEF max_DELPHI}
    TThread.CheckSynchronize(0);
  {$ELSE}
    CheckSynchronize;
  {$ENDIF}
    Sleep(1);
  until GetTickCount64 - start >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

procedure TTestSchedulers.ExerciseScheduler(const aScheduler: IEventNexusScheduler; const aName: string);
var
  mainId, asyncId, mainHandlerId: TThreadID;
  asyncEvent, mainEvent, delayEvent: TEvent;
  delayStart, delayDelta: UInt64;
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
    Check(WaitForSignal(asyncEvent, 1000), aName + ': RunAsync timed out');
    Check(asyncId <> mainId, aName + ': RunAsync executed on main thread');

    aScheduler.RunOnMain(
      procedure
      begin
        mainHandlerId := TThread.CurrentThread.ThreadID;
        mainEvent.SetEvent;
      end);
    Check(WaitForSignal(mainEvent, 1000), aName + ': RunOnMain timed out');
    CheckEquals(mainId, mainHandlerId, aName + ': RunOnMain did not execute on main thread');

    delayStart := GetTickCount64;
    delayDelta := 0;
    aScheduler.RunDelayed(
      procedure
      begin
        delayDelta := GetTickCount64 - delayStart;
        delayEvent.SetEvent;
      end,
      100000);
    Check(WaitForSignal(delayEvent, 2000), aName + ': RunDelayed timed out');
    Check(delayDelta >= 50, aName + ': RunDelayed executed too early');
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

var
  Tests: TSynTests;
begin
  Tests := TSynTests.Create('MaxEventNexus');
  try
    Tests.AddCase(TTestAggregateException);
    Tests.AddCase(TTestAsyncDelivery);
    Tests.AddCase(TTestCoalesce);
    Tests.AddCase(TTestFuzz);
    Tests.AddCase(TTestGuidTopics);
    Tests.AddCase(TTestMetrics);
    Tests.AddCase(TTestNamedTopics);
    Tests.AddCase(TTestQueuePolicy);
    Tests.AddCase(TTestSchedulers);
    Tests.AddCase(TTestSticky);
    Tests.AddCase(TTestSubscribeOrdering);
    Tests.AddCase(TTestUnsubscribeAll);
    Tests.Run;
  finally
    Tests.Free;
  end;
end.
