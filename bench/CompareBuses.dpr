program CompareBuses;

{$APPTYPE CONSOLE}

{$IFDEF FPC}
  {$FATAL This benchmark requires Delphi (System.Threading, anonymous methods).}
{$ENDIF}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  System.StrUtils,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.RawThread,
  maxLogic.EventNexus.Threading.TTask,
  iPub.Rtl.Messaging,
  NX.Horizon;

type
  IBenchmarkEvent = interface
    ['{EC2D7788-2FD7-4E9B-8EDE-7F2A36F6406D}']
    function Value: Integer;
  end;

  TBenchmarkEvent = class(TInterfacedObject, IBenchmarkEvent)
  private
    fValue: Integer;
  public
    constructor Create(aValue: Integer);
    function Value: Integer;
  end;

  TEventCallback = reference to procedure(const aEvent: IBenchmarkEvent);

  IBenchmarkBus = interface
    ['{A56FF071-C20F-48A3-A487-32D68120570C}']
    procedure Subscribe(const aCallback: TEventCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TConsumerAdapter = class
  private
    fCallback: TEventCallback;
  public
    constructor Create(const aCallback: TEventCallback);
    procedure Handle(const aEvent: IBenchmarkEvent);
  end;

  TEventNexusBus = class(TInterfacedObject, IBenchmarkBus)
  private
    fBus: ImaxBus;
    fSubscriptions: TList<ImaxSubscription>;
    fAdapters: TObjectList<TConsumerAdapter>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TEventCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TiPubBus = class(TInterfacedObject, IBenchmarkBus)
  private
    fManager: TipMessaging;
    fAdapters: TObjectList<TConsumerAdapter>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TEventCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TNxBus = class(TInterfacedObject, IBenchmarkBus)
  private
    fHorizon: TNxHorizon;
    fSubscriptions: TList<INxEventSubscription>;
    fAdapters: TObjectList<TConsumerAdapter>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TEventCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TBusFactory = reference to function: IBenchmarkBus;

  TBusEntry = record
    Name: string;
    Factory: TBusFactory;
  end;

function BusEntry(const aName: string; const aFactory: TBusFactory): TBusEntry;
begin
  Result.Name := aName;
  Result.Factory := aFactory;
end;

  TProducerThread = class(TThread)
  private
    fBus: IBenchmarkBus;
    fEvents: Integer;
    fStartValue: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const aBus: IBenchmarkBus; aEvents, aStartValue: Integer);
  end;

constructor TBenchmarkEvent.Create(aValue: Integer);
begin
  inherited Create;
  fValue := aValue;
end;

function TBenchmarkEvent.Value: Integer;
begin
  Result := fValue;
end;

constructor TConsumerAdapter.Create(const aCallback: TEventCallback);
begin
  inherited Create;
  fCallback := aCallback;
end;

procedure TConsumerAdapter.Handle(const aEvent: IBenchmarkEvent);
begin
  if Assigned(fCallback) then
    fCallback(aEvent);
end;

constructor TEventNexusBus.Create;
begin
  inherited Create;
  fBus := TmaxBus.Create(CreateMaxAsyncScheduler);
  fSubscriptions := TList<ImaxSubscription>.Create;
  fAdapters := TObjectList<TConsumerAdapter>.Create(True);
end;

destructor TEventNexusBus.Destroy;
begin
  Clear;
  fSubscriptions.Free;
  fAdapters.Free;
  inherited;
end;

procedure TEventNexusBus.Subscribe(const aCallback: TEventCallback);
var
  adapter: TConsumerAdapter;
  sub: ImaxSubscription;
begin
  adapter := TConsumerAdapter.Create(aCallback);
  fAdapters.Add(adapter);
  sub := fBus.SubscribeGuidOf<IBenchmarkEvent>(
    procedure(const aEvent: IBenchmarkEvent)
    begin
      adapter.Handle(aEvent);
    end);
  fSubscriptions.Add(sub);
end;

procedure TEventNexusBus.Post(const aEvent: IBenchmarkEvent);
begin
  fBus.PostGuidOf<IBenchmarkEvent>(aEvent);
end;

procedure TEventNexusBus.Clear;
var
  sub: ImaxSubscription;
begin
  for sub in fSubscriptions do
    sub.Unsubscribe;
  fSubscriptions.Clear;
  fAdapters.Clear;
end;

constructor TiPubBus.Create;
begin
  inherited Create;
  fManager := TipMessaging.NewManager;
  fAdapters := TObjectList<TConsumerAdapter>.Create(True);
end;

destructor TiPubBus.Destroy;
begin
  Clear;
  fManager.Free;
  fAdapters.Free;
  inherited;
end;

procedure TiPubBus.Subscribe(const aCallback: TEventCallback);
var
  adapter: TConsumerAdapter;
begin
  adapter := TConsumerAdapter.Create(aCallback);
  fAdapters.Add(adapter);
  fManager.SubscribeMethod<IBenchmarkEvent>('', adapter.Handle, TipMessagingThread.Async);
end;

procedure TiPubBus.Post(const aEvent: IBenchmarkEvent);
begin
  fManager.Post<IBenchmarkEvent>(aEvent);
end;

procedure TiPubBus.Clear;
var
  adapter: TConsumerAdapter;
begin
  for adapter in fAdapters do
    fManager.TryUnsubscribeMethod<IBenchmarkEvent>('', adapter.Handle);
  fAdapters.Clear;
end;

constructor TNxBus.Create;
begin
  inherited Create;
  fHorizon := TNxHorizon.Create;
  fSubscriptions := TList<INxEventSubscription>.Create;
  fAdapters := TObjectList<TConsumerAdapter>.Create(True);
end;

destructor TNxBus.Destroy;
begin
  Clear;
  fSubscriptions.Free;
  fAdapters.Free;
  fHorizon.Free;
  inherited;
end;

procedure TNxBus.Subscribe(const aCallback: TEventCallback);
var
  adapter: TConsumerAdapter;
  subscription: INxEventSubscription;
begin
  adapter := TConsumerAdapter.Create(aCallback);
  fAdapters.Add(adapter);
  subscription := fHorizon.Subscribe<IBenchmarkEvent>(TNxHorizonDelivery.Async, adapter.Handle);
  fSubscriptions.Add(subscription);
end;

procedure TNxBus.Post(const aEvent: IBenchmarkEvent);
begin
  fHorizon.Post<IBenchmarkEvent>(aEvent);
end;

procedure TNxBus.Clear;
var
  subscription: INxEventSubscription;
begin
  for subscription in fSubscriptions do
  begin
    fHorizon.Unsubscribe(subscription);
    subscription.WaitFor;
  end;
  fSubscriptions.Clear;
  fAdapters.Clear;
end;

constructor TProducerThread.Create(const aBus: IBenchmarkBus; aEvents, aStartValue: Integer);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  fBus := aBus;
  fEvents := aEvents;
  fStartValue := aStartValue;
end;

procedure TProducerThread.Execute;
var
  i: Integer;
begin
  for i := 0 to Pred(fEvents) do
    fBus.Post(TBenchmarkEvent.Create(fStartValue + i));
end;

function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): Boolean;
var
  start: UInt64;
begin
  start := GetTickCount64;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      Exit(True);
    TThread.CheckSynchronize(0);
    Sleep(1);
  until GetTickCount64 - start >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

type
  TBenchmarkConfig = record
    Producers: Integer;
    Consumers: Integer;
    EventsPerProducer: Integer;
  end;

procedure ParseArgs(var aCfg: TBenchmarkConfig);
var
  i: Integer;
  arg: string;
begin
  aCfg.Producers := 4;
  aCfg.Consumers := 4;
  aCfg.EventsPerProducer := 50000;
  for i := 1 to ParamCount do
  begin
    arg := ParamStr(i);
    if StartsText('--producers=', arg) then
      aCfg.Producers := StrToIntDef(Copy(arg, 13, MaxInt), aCfg.Producers)
    else if StartsText('--consumers=', arg) then
      aCfg.Consumers := StrToIntDef(Copy(arg, 13, MaxInt), aCfg.Consumers)
    else if StartsText('--events=', arg) then
      aCfg.EventsPerProducer := StrToIntDef(Copy(arg, 10, MaxInt), aCfg.EventsPerProducer);
  end;
end;

procedure RunBenchmark(const aEntry: TBusEntry; const aCfg: TBenchmarkConfig);
var
  bus: IBenchmarkBus;
  remaining: Int64;
  done: TEvent;
  threads: array of TProducerThread;
  i: Integer;
  sw: TStopwatch;
  mmBefore, mmAfter: TMemoryManagerState;
  heapBefore, heapAfter: THeapStatus;
  allocDelta: Int64;
begin
  Writeln('=== ', aEntry.Name, ' ===');
  bus := aEntry.Factory();
  remaining := Int64(aCfg.Producers) * aCfg.EventsPerProducer * aCfg.Consumers;
  done := TEvent.Create(nil, True, False, '');
  try
    for i := 1 to aCfg.Consumers do
      bus.Subscribe(
        procedure(const aEvent: IBenchmarkEvent)
        begin
          if TInterlocked.Decrement(remaining) = 0 then
            done.SetEvent;
        end);

    GetMemoryManagerState(mmBefore);
    heapBefore := GetHeapStatus;
    sw := TStopwatch.StartNew;

    SetLength(threads, aCfg.Producers);
    for i := 0 to High(threads) do
      threads[i] := TProducerThread.Create(bus, aCfg.EventsPerProducer, i * aCfg.EventsPerProducer);

    for i := 0 to High(threads) do
    begin
      threads[i].WaitFor;
      threads[i].Free;
    end;

    if not WaitForSignal(done, 60000) then
      raise Exception.CreateFmt('%s benchmark timed out waiting for consumers.', [aEntry.Name]);

    sw.Stop;
    GetMemoryManagerState(mmAfter);
    heapAfter := GetHeapStatus;
    allocDelta := mmAfter.TotalAllocated - mmBefore.TotalAllocated;

    Writeln('Producers            : ', aCfg.Producers);
    Writeln('Consumers            : ', aCfg.Consumers);
    Writeln('Events per producer  : ', aCfg.EventsPerProducer);
    Writeln('Elapsed ms           : ', sw.ElapsedMilliseconds);
    if sw.ElapsedMilliseconds > 0 then
      Writeln('Throughput evt/s     : ', (Int64(aCfg.Producers) * aCfg.EventsPerProducer * 1000) div sw.ElapsedMilliseconds);
    Writeln('Heap delta (bytes)   : ', heapAfter.TotalAllocated - heapBefore.TotalAllocated);
    Writeln('TotalAllocated delta : ', allocDelta);
  finally
    done.Free;
    bus.Clear;
  end;
end;

procedure RunAllBenchmarks(const aCfg: TBenchmarkConfig);
var
  entries: TArray<TBusEntry>;
begin
  entries := TArray<TBusEntry>.Create(
    BusEntry('EventNexus (maxAsync)',
      function: IBenchmarkBus
      begin
        Result := TEventNexusBus.Create;
      end),
    BusEntry('iPub Messaging',
      function: IBenchmarkBus
      begin
        Result := TiPubBus.Create;
      end),
    BusEntry('NX Horizon',
      function: IBenchmarkBus
      begin
        Result := TNxBus.Create;
      end)
  );

  for var entry in entries do
  begin
    try
      RunBenchmark(entry, aCfg);
    except
      on E: Exception do
        Writeln('Error running ', entry.Name, ': ', E.Message);
    end;
    Writeln;
  end;
end;

begin
  try
    ReportMemoryLeaksOnShutdown := True;
    var cfg: TBenchmarkConfig;
    ParseArgs(cfg);
    Writeln('Compare Event Buses');
    Writeln('Command line overrides: --producers=N --consumers=N --events=N');
    RunAllBenchmarks(cfg);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
