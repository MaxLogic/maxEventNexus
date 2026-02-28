program SchedulerCompare;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, SyncObjs,
  System.Diagnostics, System.Generics.Collections, System.Math, System.StrUtils, System.Threading,
  iPub.Rtl.Messaging,
  NX.Horizon,
  maxLogic.EventNexus,
  maxLogic.EventNexus.Core,
  maxLogic.EventNexus.Threading.Adapter,
  maxLogic.EventNexus.Threading.MaxAsync,
  maxLogic.EventNexus.Threading.RawThread,
  maxLogic.EventNexus.Threading.TTask;

type
  TSchedulerFactory = function: IEventNexusScheduler;

  TSchedulerEntry = record
    Name: string;
    Factory: TSchedulerFactory;
  end;

  IBenchmarkEvent = interface
    ['{54A9A7A4-8D5B-4BE6-8FDE-1F7A58A5CE2E}']
    function GetValue: Integer;
    property Value: Integer read GetValue;
  end;

  TBenchmarkEvent = class(TInterfacedObject, IBenchmarkEvent)
  private
    fValue: Integer;
  public
    constructor Create(aValue: Integer);
    function GetValue: Integer;
  end;

  TFrameworkCallback = reference to procedure(const aEvent: IBenchmarkEvent);

  IFrameworkBus = interface
    ['{DF69FB99-703B-4A3A-BDA0-D2B3E13CB0EA}']
    procedure Subscribe(const aCallback: TFrameworkCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TFrameworkFactory = function(aDelivery: TmaxDelivery): IFrameworkBus;

  TFrameworkEntry = record
    Name: string;
    Factory: TFrameworkFactory;
  end;

  TFrameworkConsumer = class
  private
    fCallback: TFrameworkCallback;
  public
    constructor Create(const aCallback: TFrameworkCallback);
    procedure Handle(const aEvent: IBenchmarkEvent);
  end;

  TEventNexusFrameworkBus = class(TInterfacedObject, IFrameworkBus)
  private
    fBus: TmaxBus;
    fConsumers: TObjectList<TFrameworkConsumer>;
    fDelivery: TmaxDelivery;
    fUseStrongSubscriptions: Boolean;
    fSubscriptions: TList<ImaxSubscription>;
  public
    constructor Create(aDelivery: TmaxDelivery; aUseStrongSubscriptions: Boolean);
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TFrameworkCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TiPubFrameworkBus = class(TInterfacedObject, IFrameworkBus)
  private
    fConsumers: TObjectList<TFrameworkConsumer>;
    fDelivery: TipMessagingThread;
    fManager: TipMessaging;
  public
    constructor Create(aDelivery: TmaxDelivery);
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TFrameworkCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TEventHorizonFrameworkBus = class(TInterfacedObject, IFrameworkBus)
  private
    fConsumers: TObjectList<TFrameworkConsumer>;
    fDelivery: TNxHorizonDelivery;
    fHorizon: TNxHorizon;
    fSubscriptions: TList<INxEventSubscription>;
  public
    constructor Create(aDelivery: TmaxDelivery);
    destructor Destroy; override;
    procedure Subscribe(const aCallback: TFrameworkCallback);
    procedure Post(const aEvent: IBenchmarkEvent);
    procedure Clear;
  end;

  TBenchmarkConfig = record
    Events: Integer;
    Consumers: Integer;
    Runs: Integer;
    Delivery: TmaxDelivery;
    CsvPath: string;
    MetricsReaders: Integer;
    MetricsReadsPerReader: Int64;
    QueueMaxDepth: Integer;
    MaxInFlight: Integer;
    SkipSchedulers: Boolean;
    FrameworkFilter: string;
  end;

  TRunSample = record
    ElapsedUs: Int64;
    ThroughputPerSec: Int64;
    MetricReads: Int64;
    MetricReadsPerSec: Int64;
  end;

const
  cClockName = 'TStopwatch.GetTimeStamp';
  cPercentileMethod = 'nearest-rank';

function CreateRawThreadScheduler: IEventNexusScheduler;
begin
  Result := TmaxRawThreadScheduler.Create;
end;

constructor TBenchmarkEvent.Create(aValue: Integer);
begin
  inherited Create;
  fValue := aValue;
end;

function TBenchmarkEvent.GetValue: Integer;
begin
  Result := fValue;
end;

constructor TFrameworkConsumer.Create(const aCallback: TFrameworkCallback);
begin
  inherited Create;
  fCallback := aCallback;
end;

procedure TFrameworkConsumer.Handle(const aEvent: IBenchmarkEvent);
begin
  if Assigned(fCallback) then
  begin
    fCallback(aEvent);
  end;
end;

function DeliveryToIpub(aDelivery: TmaxDelivery): TipMessagingThread;
begin
  case aDelivery of
    TmaxDelivery.Posting: Result := TipMessagingThread.Posting;
    TmaxDelivery.Main: Result := TipMessagingThread.Main;
    TmaxDelivery.Async: Result := TipMessagingThread.Async;
    TmaxDelivery.Background: Result := TipMessagingThread.Background;
  else
    Result := TipMessagingThread.Posting;
  end;
end;

function DeliveryToEventHorizon(aDelivery: TmaxDelivery): TNxHorizonDelivery;
begin
  case aDelivery of
    TmaxDelivery.Posting: Result := TNxHorizonDelivery.Sync;
    TmaxDelivery.Main: Result := TNxHorizonDelivery.MainAsync;
    TmaxDelivery.Async: Result := TNxHorizonDelivery.Async;
    TmaxDelivery.Background: Result := TNxHorizonDelivery.Async;
  else
    Result := TNxHorizonDelivery.Sync;
  end;
end;

constructor TEventNexusFrameworkBus.Create(aDelivery: TmaxDelivery; aUseStrongSubscriptions: Boolean);
begin
  inherited Create;
  fDelivery := aDelivery;
  fUseStrongSubscriptions := aUseStrongSubscriptions;
  fBus := TmaxBus.Create(CreateTTaskScheduler);
  fSubscriptions := TList<ImaxSubscription>.Create;
  fConsumers := TObjectList<TFrameworkConsumer>.Create(True);
end;

destructor TEventNexusFrameworkBus.Destroy;
begin
  Clear;
  fConsumers.Free;
  fSubscriptions.Free;
  inherited;
end;

procedure TEventNexusFrameworkBus.Subscribe(const aCallback: TFrameworkCallback);
var
  lConsumer: TFrameworkConsumer;
  lSubscription: ImaxSubscription;
begin
  lConsumer := TFrameworkConsumer.Create(aCallback);
  fConsumers.Add(lConsumer);
  if fUseStrongSubscriptions then
  begin
    lSubscription := fBus.SubscribeGuidOfStrong<IBenchmarkEvent>(lConsumer.Handle, fDelivery);
  end else begin
    lSubscription := fBus.SubscribeGuidOf<IBenchmarkEvent>(lConsumer.Handle, fDelivery);
  end;
  fSubscriptions.Add(lSubscription);
end;

procedure TEventNexusFrameworkBus.Post(const aEvent: IBenchmarkEvent);
begin
  fBus.PostGuidOf<IBenchmarkEvent>(aEvent);
end;

procedure TEventNexusFrameworkBus.Clear;
var
  lSubscription: ImaxSubscription;
begin
  for lSubscription in fSubscriptions do
  begin
    lSubscription.Unsubscribe;
  end;
  fSubscriptions.Clear;
  fConsumers.Clear;
end;

constructor TiPubFrameworkBus.Create(aDelivery: TmaxDelivery);
begin
  inherited Create;
  fDelivery := DeliveryToIpub(aDelivery);
  fManager := TipMessaging.NewManager;
  fConsumers := TObjectList<TFrameworkConsumer>.Create(True);
end;

destructor TiPubFrameworkBus.Destroy;
begin
  Clear;
  fConsumers.Free;
  fManager.Free;
  inherited;
end;

procedure TiPubFrameworkBus.Subscribe(const aCallback: TFrameworkCallback);
var
  lConsumer: TFrameworkConsumer;
begin
  lConsumer := TFrameworkConsumer.Create(aCallback);
  fConsumers.Add(lConsumer);
  fManager.SubscribeMethod<IBenchmarkEvent>('', lConsumer.Handle, fDelivery);
end;

procedure TiPubFrameworkBus.Post(const aEvent: IBenchmarkEvent);
begin
  fManager.Post<IBenchmarkEvent>(aEvent);
end;

procedure TiPubFrameworkBus.Clear;
var
  lConsumer: TFrameworkConsumer;
begin
  for lConsumer in fConsumers do
  begin
    fManager.TryUnsubscribeMethod<IBenchmarkEvent>('', lConsumer.Handle);
  end;
  fConsumers.Clear;
end;

constructor TEventHorizonFrameworkBus.Create(aDelivery: TmaxDelivery);
begin
  inherited Create;
  fDelivery := DeliveryToEventHorizon(aDelivery);
  fHorizon := TNxHorizon.Create;
  fSubscriptions := TList<INxEventSubscription>.Create;
  fConsumers := TObjectList<TFrameworkConsumer>.Create(True);
end;

destructor TEventHorizonFrameworkBus.Destroy;
begin
  Clear;
  fConsumers.Free;
  fSubscriptions.Free;
  fHorizon.Free;
  inherited;
end;

procedure TEventHorizonFrameworkBus.Subscribe(const aCallback: TFrameworkCallback);
var
  lConsumer: TFrameworkConsumer;
  lSubscription: INxEventSubscription;
begin
  lConsumer := TFrameworkConsumer.Create(aCallback);
  fConsumers.Add(lConsumer);
  lSubscription := fHorizon.Subscribe<IBenchmarkEvent>(fDelivery, lConsumer.Handle);
  fSubscriptions.Add(lSubscription);
end;

procedure TEventHorizonFrameworkBus.Post(const aEvent: IBenchmarkEvent);
begin
  fHorizon.Post<IBenchmarkEvent>(aEvent);
end;

procedure TEventHorizonFrameworkBus.Clear;
var
  lSubscription: INxEventSubscription;
begin
  for lSubscription in fSubscriptions do
  begin
    fHorizon.Unsubscribe(lSubscription);
    lSubscription.WaitFor;
  end;
  fSubscriptions.Clear;
  fConsumers.Clear;
end;

function CreateEventNexusFrameworkBusWeak(aDelivery: TmaxDelivery): IFrameworkBus;
begin
  Result := TEventNexusFrameworkBus.Create(aDelivery, False);
end;

function CreateEventNexusFrameworkBusStrong(aDelivery: TmaxDelivery): IFrameworkBus;
begin
  Result := TEventNexusFrameworkBus.Create(aDelivery, True);
end;

function CreateIpubFrameworkBus(aDelivery: TmaxDelivery): IFrameworkBus;
begin
  Result := TiPubFrameworkBus.Create(aDelivery);
end;

function CreateEventHorizonFrameworkBus(aDelivery: TmaxDelivery): IFrameworkBus;
begin
  Result := TEventHorizonFrameworkBus.Create(aDelivery);
end;

function DeliveryToText(aDelivery: TmaxDelivery): string;
begin
  case aDelivery of
    TmaxDelivery.Posting: Result := 'posting';
    TmaxDelivery.Main: Result := 'main';
    TmaxDelivery.Async: Result := 'async';
    TmaxDelivery.Background: Result := 'background';
  else
    Result := 'posting';
  end;
end;

function ParseDelivery(const aValue: string): TmaxDelivery;
begin
  if SameText(aValue, 'posting') then
    Exit(TmaxDelivery.Posting);
  if SameText(aValue, 'main') then
    Exit(TmaxDelivery.Main);
  if SameText(aValue, 'async') then
    Exit(TmaxDelivery.Async);
  if SameText(aValue, 'background') then
    Exit(TmaxDelivery.Background);
  raise Exception.CreateFmt('Invalid delivery mode "%s". Use posting|main|async|background.', [aValue]);
end;

function IsAllFrameworksFilter(const aValue: string): Boolean;
begin
  Result := (Trim(aValue) = '') or SameText(aValue, 'all');
end;

function IsFrameworkSelected(const aFilter: string; const aFrameworkName: string): Boolean;
begin
  if IsAllFrameworksFilter(aFilter) then
    Exit(True);
  if SameText(aFilter, aFrameworkName) then
    Exit(True);

  if SameText(aFrameworkName, 'EventNexus(TTask-weak)') then
    Exit(SameText(aFilter, 'weak') or SameText(aFilter, 'eventnexus-weak'));
  if SameText(aFrameworkName, 'EventNexus(TTask-strong)') then
    Exit(SameText(aFilter, 'strong') or SameText(aFilter, 'eventnexus-strong'));
  if SameText(aFrameworkName, 'iPub') then
    Exit(SameText(aFilter, 'ipub'));
  if SameText(aFrameworkName, 'EventHorizon') then
    Exit(SameText(aFilter, 'eventhorizon') or SameText(aFilter, 'horizon'));

  Result := False;
end;

function AnyFrameworkSelected(const aFilter: string; const aEntries: array of TFrameworkEntry): Boolean;
var
  lIdx: Integer;
begin
  for lIdx := Low(aEntries) to High(aEntries) do
  begin
    if IsFrameworkSelected(aFilter, aEntries[lIdx].Name) then
      Exit(True);
  end;
  Result := False;
end;

procedure PrintUsage;
begin
  Writeln('Usage: SchedulerCompare [options]');
  Writeln('  --events=<n>            events posted per run (default: 20000)');
  Writeln('  --consumers=<n>         subscriber count (default: 4)');
  Writeln('  --runs=<n>              benchmark runs per scheduler (default: 9)');
  Writeln('  --delivery=<mode>       posting|main|async|background (default: async)');
  Writeln('  --metrics-readers=<n>   concurrent stats-reader threads (default: 0)');
  Writeln('  --metrics-reads=<n>     max reads per reader, 0=unbounded until run ends (default: 0)');
  Writeln('  --queue-max-depth=<n>   typed-topic queue depth for benchmark topic, 0=unbounded (default: 64)');
  Writeln('  --max-inflight=<n>      max in-flight deliveries while posting, 0=unbounded (default: 256)');
  Writeln('  --skip-schedulers       skip scheduler rows and run framework rows only');
  Writeln('  --framework=<name>      all|weak|strong|ipub|eventhorizon or exact framework label');
  Writeln('  --csv=<path>            write summary CSV to file path');
end;

procedure ParseArgs(var aCfg: TBenchmarkConfig);
var
  i: Integer;
  lArg: string;
begin
  aCfg.Events := 20000;
  aCfg.Consumers := 4;
  aCfg.Runs := 9;
  aCfg.Delivery := TmaxDelivery.Async;
  aCfg.CsvPath := '';
  aCfg.MetricsReaders := 0;
  aCfg.MetricsReadsPerReader := 0;
  aCfg.QueueMaxDepth := 64;
  aCfg.MaxInFlight := 256;
  aCfg.SkipSchedulers := False;
  aCfg.FrameworkFilter := 'all';

  for i := 1 to ParamCount do
  begin
    lArg := ParamStr(i);
    if SameText(lArg, '--help') then
    begin
      PrintUsage;
      Halt(0);
    end
    else if StartsText('--events=', lArg) then
      aCfg.Events := StrToIntDef(Copy(lArg, Length('--events=') + 1, MaxInt), aCfg.Events)
    else if StartsText('--consumers=', lArg) then
      aCfg.Consumers := StrToIntDef(Copy(lArg, Length('--consumers=') + 1, MaxInt), aCfg.Consumers)
    else if StartsText('--runs=', lArg) then
      aCfg.Runs := StrToIntDef(Copy(lArg, Length('--runs=') + 1, MaxInt), aCfg.Runs)
    else if StartsText('--delivery=', lArg) then
      aCfg.Delivery := ParseDelivery(Copy(lArg, Length('--delivery=') + 1, MaxInt))
    else if StartsText('--metrics-readers=', lArg) then
      aCfg.MetricsReaders := StrToIntDef(Copy(lArg, Length('--metrics-readers=') + 1, MaxInt), aCfg.MetricsReaders)
    else if StartsText('--metrics-reads=', lArg) then
      aCfg.MetricsReadsPerReader := StrToInt64Def(Copy(lArg, Length('--metrics-reads=') + 1, MaxInt), aCfg.MetricsReadsPerReader)
    else if StartsText('--queue-max-depth=', lArg) then
      aCfg.QueueMaxDepth := StrToIntDef(Copy(lArg, Length('--queue-max-depth=') + 1, MaxInt), aCfg.QueueMaxDepth)
    else if StartsText('--max-inflight=', lArg) then
      aCfg.MaxInFlight := StrToIntDef(Copy(lArg, Length('--max-inflight=') + 1, MaxInt), aCfg.MaxInFlight)
    else if SameText(lArg, '--skip-schedulers') then
      aCfg.SkipSchedulers := True
    else if StartsText('--framework=', lArg) then
      aCfg.FrameworkFilter := Trim(Copy(lArg, Length('--framework=') + 1, MaxInt))
    else if StartsText('--csv=', lArg) then
      aCfg.CsvPath := Copy(lArg, Length('--csv=') + 1, MaxInt)
    else
      raise Exception.CreateFmt('Unknown argument "%s". Use --help for options.', [lArg]);
  end;

  if aCfg.Events <= 0 then
    raise Exception.Create('events must be > 0');
  if aCfg.Consumers <= 0 then
    raise Exception.Create('consumers must be > 0');
  if aCfg.Runs <= 0 then
    raise Exception.Create('runs must be > 0');
  if aCfg.MetricsReaders < 0 then
    raise Exception.Create('metrics-readers must be >= 0');
  if aCfg.MetricsReadsPerReader < 0 then
    raise Exception.Create('metrics-reads must be >= 0');
  if aCfg.QueueMaxDepth < 0 then
    raise Exception.Create('queue-max-depth must be >= 0');
  if aCfg.MaxInFlight < 0 then
    raise Exception.Create('max-inflight must be >= 0');
  if aCfg.FrameworkFilter = '' then
    raise Exception.Create('framework must not be empty (use all|weak|strong|ipub|eventhorizon)');
end;

function WaitForSignal(const aEvent: TEvent; aTimeoutMs: Cardinal): Boolean;
var
  lWatch: TStopwatch;
begin
  lWatch := TStopwatch.StartNew;
  repeat
    if aEvent.WaitFor(0) = wrSignaled then
      Exit(True);
    CheckSynchronize(0);
    Sleep(1);
  until lWatch.ElapsedMilliseconds >= aTimeoutMs;
  Result := aEvent.WaitFor(0) = wrSignaled;
end;

function ElapsedUs(const aWatch: TStopwatch): Int64;
begin
  Result := (aWatch.ElapsedTicks * 1000000) div TStopwatch.Frequency;
  if Result <= 0 then
    Result := 1;
end;

function PercentileNearestRank(const aValues: TArray<Int64>; aPercent: Double): Int64;
var
  lSorted: TArray<Int64>;
  lRank: Integer;
  lN: Integer;
begin
  lN := Length(aValues);
  if lN = 0 then
    Exit(0);
  lSorted := Copy(aValues);
  TArray.Sort<Int64>(lSorted);
  lRank := Ceil((aPercent / 100.0) * lN);
  if lRank < 1 then
    lRank := 1
  else if lRank > lN then
    lRank := lN;
  Result := lSorted[lRank - 1];
end;

function SumValues(const aValues: TArray<Int64>): Int64;
var
  lValue: Int64;
begin
  Result := 0;
  for lValue in aValues do
    Inc(Result, lValue);
end;

function MinValue(const aValues: TArray<Int64>): Int64;
var
  lValue: Int64;
begin
  if Length(aValues) = 0 then
    Exit(0);
  Result := aValues[0];
  for lValue in aValues do
    if lValue < Result then
      Result := lValue;
end;

function MaxValue(const aValues: TArray<Int64>): Int64;
var
  lValue: Int64;
begin
  if Length(aValues) = 0 then
    Exit(0);
  Result := aValues[0];
  for lValue in aValues do
    if lValue > Result then
      Result := lValue;
end;

function CsvSafe(const aText: string): string;
begin
  Result := StringReplace(aText, ',', ';', [rfReplaceAll]);
end;

procedure BenchmarkScheduler(const aEntry: TSchedulerEntry; const aCfg: TBenchmarkConfig; out aSamples: TArray<TRunSample>);
var
  lRun: Integer;
  lBusObj: TmaxBus;
  lHandler: TmaxProcOf<Integer>;
  lDone: TEvent;
  lStopReaders: TEvent;
  lReaderTasks: TArray<IFuture<Int64>>;
  lSubs: array of ImaxSubscription;
  lRemaining: Integer;
  lRemainingLock: TCriticalSection;
  lI: Integer;
  lScheduler: IEventNexusScheduler;
  lWatch: TStopwatch;
  lElapsedUs: Int64;
  lDelivered: Int64;
  lMetricReads: Int64;
  lPolicy: TmaxQueuePolicy;
  lPhase: string;
  lPostedDeliveries: Int64;
  lInFlight: Int64;
  lTotalExpected: Int64;
begin
  SetLength(aSamples, aCfg.Runs);
  for lRun := 0 to aCfg.Runs - 1 do
  begin
    lScheduler := aEntry.Factory;
    lBusObj := TmaxBus.Create(lScheduler);
    lDone := TEvent.Create(nil, True, False, '');
    lStopReaders := TEvent.Create(nil, True, False, '');
    lRemainingLock := TCriticalSection.Create;
    lMetricReads := 0;
    lPhase := 'setup';
    try
      try
        if aCfg.QueueMaxDepth > 0 then
        begin
          lPolicy.MaxDepth := aCfg.QueueMaxDepth;
          lPolicy.Overflow := TmaxOverflow.Block;
          lPolicy.DeadlineUs := 0;
          lBusObj.SetPolicyFor<Integer>(lPolicy);
        end;

        lRemaining := aCfg.Events * aCfg.Consumers;
        lTotalExpected := Int64(aCfg.Events) * aCfg.Consumers;
        lPostedDeliveries := 0;
        lHandler :=
          procedure(const aValue: Integer)
          begin
            lRemainingLock.Enter;
            try
              Dec(lRemaining);
              if lRemaining = 0 then
                lDone.SetEvent;
            finally
              lRemainingLock.Leave;
            end;
          end;

        SetLength(lSubs, aCfg.Consumers);
        lPhase := 'subscribe';
        for lI := 1 to aCfg.Consumers do
          lSubs[lI - 1] := lBusObj.Subscribe<Integer>(lHandler, aCfg.Delivery);

        if aCfg.MetricsReaders > 0 then
        begin
          lPhase := 'create-readers';
          SetLength(lReaderTasks, aCfg.MetricsReaders);
          for lI := 0 to High(lReaderTasks) do
          begin
            try
              lReaderTasks[lI] := TTask.Future<Int64>(
                function: Int64
                var
                  lReads: Int64;
                begin
                  lReads := 0;
                  while lStopReaders.WaitFor(0) <> wrSignaled do
                  begin
                    lBusObj.GetStatsFor<Integer>;
                    Inc(lReads);
                    if (aCfg.MetricsReadsPerReader > 0) and (lReads >= aCfg.MetricsReadsPerReader) then
                      Break;
                  end;
                  Result := lReads;
                end);
            except
              // Reader-load submission is best-effort for benchmarking; do not fail the full run.
              lReaderTasks[lI] := nil;
            end;
          end;
        end;

        lPhase := 'post';
        lWatch := TStopwatch.StartNew;
        for lI := 1 to aCfg.Events do
        begin
          if (aCfg.MaxInFlight > 0) and (aCfg.Delivery <> TmaxDelivery.Posting) then
          begin
            while True do
            begin
              lRemainingLock.Enter;
              try
                lInFlight := lPostedDeliveries - (lTotalExpected - lRemaining);
              finally
                lRemainingLock.Leave;
              end;
              if lInFlight < aCfg.MaxInFlight then
                Break;
              CheckSynchronize(0);
              Sleep(1);
            end;
          end;
          lBusObj.Post<Integer>(lI);
          Inc(lPostedDeliveries, aCfg.Consumers);
        end;

        lPhase := 'wait-drain';
        if (lRemaining > 0) and (not WaitForSignal(lDone, 60000)) then
          raise Exception.CreateFmt('%s failed to drain queue on run %d', [aEntry.Name, lRun + 1]);

        lWatch.Stop;
        lElapsedUs := ElapsedUs(lWatch);
        lDelivered := lTotalExpected;

        lStopReaders.SetEvent;
        for lI := 0 to High(lReaderTasks) do
        begin
          if lReaderTasks[lI] <> nil then
            Inc(lMetricReads, lReaderTasks[lI].Value);
        end;

        aSamples[lRun].ElapsedUs := lElapsedUs;
        aSamples[lRun].ThroughputPerSec := (lDelivered * 1000000) div lElapsedUs;
        aSamples[lRun].MetricReads := lMetricReads;
        if lElapsedUs > 0 then
          aSamples[lRun].MetricReadsPerSec := (lMetricReads * 1000000) div lElapsedUs
        else
          aSamples[lRun].MetricReadsPerSec := 0;
      except
        on E: Exception do
          raise Exception.CreateFmt('%s run %d phase=%s: %s: %s',
            [aEntry.Name, lRun + 1, lPhase, E.ClassName, E.Message]);
      end;
    finally
      lStopReaders.Free;
      lRemainingLock.Free;
      lDone.Free;
      lScheduler := nil;
      SetLength(lSubs, 0);
      SetLength(lReaderTasks, 0);
    end;
  end;
end;

procedure BenchmarkFramework(const aEntry: TFrameworkEntry; const aCfg: TBenchmarkConfig; out aSamples: TArray<TRunSample>);
var
  lBus: IFrameworkBus;
  lDone: TEvent;
  lElapsedUs: Int64;
  lInFlight: Int64;
  lI: Integer;
  lPhase: string;
  lPostedDeliveries: Int64;
  lRemaining: Integer;
  lRemainingLock: TCriticalSection;
  lRun: Integer;
  lTotalExpected: Int64;
  lWatch: TStopwatch;
begin
  SetLength(aSamples, aCfg.Runs);
  for lRun := 0 to aCfg.Runs - 1 do
  begin
    lBus := aEntry.Factory(aCfg.Delivery);
    lDone := TEvent.Create(nil, True, False, '');
    lRemainingLock := TCriticalSection.Create;
    lPhase := 'setup';
    try
      try
        lRemaining := aCfg.Events * aCfg.Consumers;
        lTotalExpected := Int64(aCfg.Events) * aCfg.Consumers;
        lPostedDeliveries := 0;

        lPhase := 'subscribe';
        for lI := 1 to aCfg.Consumers do
        begin
          lBus.Subscribe(
            procedure(const aEvent: IBenchmarkEvent)
            begin
              if aEvent <> nil then
              begin
                aEvent.GetValue;
              end;

              lRemainingLock.Enter;
              try
                Dec(lRemaining);
                if lRemaining = 0 then
                begin
                  lDone.SetEvent;
                end;
              finally
                lRemainingLock.Leave;
              end;
            end);
        end;

        lPhase := 'post';
        lWatch := TStopwatch.StartNew;
        for lI := 1 to aCfg.Events do
        begin
          if (aCfg.MaxInFlight > 0) and (aCfg.Delivery <> TmaxDelivery.Posting) then
          begin
            while True do
            begin
              lRemainingLock.Enter;
              try
                lInFlight := lPostedDeliveries - (lTotalExpected - lRemaining);
              finally
                lRemainingLock.Leave;
              end;
              if lInFlight < aCfg.MaxInFlight then
              begin
                Break;
              end;
              CheckSynchronize(0);
              Sleep(1);
            end;
          end;
          lBus.Post(TBenchmarkEvent.Create(lI));
          Inc(lPostedDeliveries, aCfg.Consumers);
        end;

        lPhase := 'wait-drain';
        if (lRemaining > 0) and (not WaitForSignal(lDone, 180000)) then
        begin
          raise Exception.CreateFmt('%s failed to drain queue on run %d', [aEntry.Name, lRun + 1]);
        end;

        lWatch.Stop;
        lElapsedUs := ElapsedUs(lWatch);

        aSamples[lRun].ElapsedUs := lElapsedUs;
        aSamples[lRun].ThroughputPerSec := (lTotalExpected * 1000000) div lElapsedUs;
        aSamples[lRun].MetricReads := 0;
        aSamples[lRun].MetricReadsPerSec := 0;
      except
        on E: Exception do
        begin
          raise Exception.CreateFmt('%s run %d phase=%s: %s: %s',
            [aEntry.Name, lRun + 1, lPhase, E.ClassName, E.Message]);
        end;
      end;
    finally
      if lBus <> nil then
      begin
        lBus.Clear;
      end;
      lBus := nil;
      lRemainingLock.Free;
      lDone.Free;
    end;
  end;
end;

procedure SummarizeSamples(const aSamples: TArray<TRunSample>; out aP50Us, aP95Us, aP99Us,
  aAvgUs, aBestUs, aWorstUs, aAvgThroughput, aTotalMetricReads, aAvgMetricReadsPerSec: Int64);
var
  lElapsed: TArray<Int64>;
  lThroughput: TArray<Int64>;
  lMetricReadsPerSec: TArray<Int64>;
  lI: Integer;
begin
  SetLength(lElapsed, Length(aSamples));
  SetLength(lThroughput, Length(aSamples));
  SetLength(lMetricReadsPerSec, Length(aSamples));

  aTotalMetricReads := 0;
  for lI := 0 to High(aSamples) do
  begin
    lElapsed[lI] := aSamples[lI].ElapsedUs;
    lThroughput[lI] := aSamples[lI].ThroughputPerSec;
    lMetricReadsPerSec[lI] := aSamples[lI].MetricReadsPerSec;
    Inc(aTotalMetricReads, aSamples[lI].MetricReads);
  end;

  aP50Us := PercentileNearestRank(lElapsed, 50.0);
  aP95Us := PercentileNearestRank(lElapsed, 95.0);
  aP99Us := PercentileNearestRank(lElapsed, 99.0);
  aAvgUs := SumValues(lElapsed) div Length(lElapsed);
  aBestUs := MinValue(lElapsed);
  aWorstUs := MaxValue(lElapsed);
  aAvgThroughput := SumValues(lThroughput) div Length(lThroughput);
  aAvgMetricReadsPerSec := SumValues(lMetricReadsPerSec) div Length(lMetricReadsPerSec);
end;

procedure AppendCsvSummaryRow(aLines: TStrings; const aScenario: string; const aName: string;
  const aCfg: TBenchmarkConfig; aP50Us, aP95Us, aP99Us, aAvgUs, aBestUs, aWorstUs, aAvgThroughput,
  aTotalMetricReads, aAvgMetricReadsPerSec: Int64);
begin
  aLines.Add(aScenario + ',' +
    aName + ',' +
    DeliveryToText(aCfg.Delivery) + ',' +
    IntToStr(aCfg.Consumers) + ',' +
    IntToStr(aCfg.Events) + ',' +
    IntToStr(aCfg.Runs) + ',' +
    IntToStr(aP50Us) + ',' +
    IntToStr(aP95Us) + ',' +
    IntToStr(aP99Us) + ',' +
    IntToStr(aAvgUs) + ',' +
    IntToStr(aBestUs) + ',' +
    IntToStr(aWorstUs) + ',' +
    IntToStr(aAvgThroughput) + ',' +
    IntToStr(aTotalMetricReads) + ',' +
    IntToStr(aAvgMetricReadsPerSec) + ',' +
    cClockName + ',' +
    cPercentileMethod + ',ok,');
end;

procedure AppendCsvFailureRow(aLines: TStrings; const aScenario: string; const aName: string;
  const aCfg: TBenchmarkConfig; const aError: string);
begin
  aLines.Add(aScenario + ',' +
    aName + ',' +
    DeliveryToText(aCfg.Delivery) + ',' +
    IntToStr(aCfg.Consumers) + ',' +
    IntToStr(aCfg.Events) + ',' +
    IntToStr(aCfg.Runs) + ',' +
    '0,0,0,0,0,0,0,0,0,' +
    cClockName + ',' +
    cPercentileMethod + ',failed,' +
    CsvSafe(aError));
end;

procedure Run;
var
  lCfg: TBenchmarkConfig;
  lFrameworkCfg: TBenchmarkConfig;
  lFrameworkEntries: array of TFrameworkEntry;
  lRunCfg: TBenchmarkConfig;
  lEntries: array of TSchedulerEntry;
  lFrameworkIdx: Integer;
  lIdx: Integer;
  lSamples: TArray<TRunSample>;
  lP50Us, lP95Us, lP99Us: Int64;
  lAvgUs, lBestUs, lWorstUs: Int64;
  lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec: Int64;
  lCsv: TStringList;
  lFrameworkRan: Boolean;
begin
  ParseArgs(lCfg);

  SetLength(lEntries, 3);
  lEntries[0].Name := 'raw-thread';
  lEntries[0].Factory := CreateRawThreadScheduler;
  lEntries[1].Name := 'maxAsync';
  lEntries[1].Factory := CreateMaxAsyncScheduler;
  lEntries[2].Name := 'TTask';
  lEntries[2].Factory := CreateTTaskScheduler;

  SetLength(lFrameworkEntries, 4);
  lFrameworkEntries[0].Name := 'EventNexus(TTask-weak)';
  lFrameworkEntries[0].Factory := CreateEventNexusFrameworkBusWeak;
  lFrameworkEntries[1].Name := 'EventNexus(TTask-strong)';
  lFrameworkEntries[1].Factory := CreateEventNexusFrameworkBusStrong;
  lFrameworkEntries[2].Name := 'iPub';
  lFrameworkEntries[2].Factory := CreateIpubFrameworkBus;
  lFrameworkEntries[3].Name := 'EventHorizon';
  lFrameworkEntries[3].Factory := CreateEventHorizonFrameworkBus;
  if not AnyFrameworkSelected(lCfg.FrameworkFilter, lFrameworkEntries) then
  begin
    raise Exception.CreateFmt('Unknown framework "%s". Use all|weak|strong|ipub|eventhorizon or exact framework name.',
      [lCfg.FrameworkFilter]);
  end;

  lCsv := nil;
  if lCfg.CsvPath <> '' then
  begin
    lCsv := TStringList.Create;
    lCsv.Add('scenario,scheduler,delivery,consumers,events,runs,p50_us,p95_us,p99_us,avg_us,best_us,worst_us,avg_throughput_evt_s,total_metric_reads,avg_metric_reads_s,clock,percentile_method,status,error');
  end;

  try
    Writeln('Clock: ', cClockName);
    Writeln('Percentiles: ', cPercentileMethod);
    Writeln('Delivery: ', DeliveryToText(lCfg.Delivery));
    Writeln('Consumers: ', lCfg.Consumers, '  Events: ', lCfg.Events, '  Runs: ', lCfg.Runs);
    Writeln('Metrics readers: ', lCfg.MetricsReaders, '  Max reads/reader: ', lCfg.MetricsReadsPerReader);
    Writeln('Queue max depth: ', lCfg.QueueMaxDepth);
    Writeln('Max in-flight deliveries: ', lCfg.MaxInFlight);
    Writeln;

    if lCfg.SkipSchedulers then
    begin
      Writeln('Scheduler comparison skipped (--skip-schedulers).');
      Writeln;
    end else begin
      for lIdx := Low(lEntries) to High(lEntries) do
      begin
        lRunCfg := lCfg;
        if SameText(lEntries[lIdx].Name, 'maxAsync') and (lRunCfg.Delivery <> TmaxDelivery.Posting) and
          (lRunCfg.Runs > 1) then
        begin
          Writeln('Note: maxAsync async profile is capped to 1 run in-process to avoid cumulative memory pressure.');
          lRunCfg.Runs := 1;
        end;
        try
          BenchmarkScheduler(lEntries[lIdx], lRunCfg, lSamples);
          SummarizeSamples(lSamples, lP50Us, lP95Us, lP99Us, lAvgUs, lBestUs, lWorstUs,
            lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec);

          Writeln('--- ', lEntries[lIdx].Name, ' ---');
          Writeln('p50 us: ', lP50Us);
          Writeln('p95 us: ', lP95Us);
          Writeln('p99 us: ', lP99Us);
          Writeln('avg us: ', lAvgUs, '  best us: ', lBestUs, '  worst us: ', lWorstUs);
          Writeln('avg throughput evt/s: ', lAvgThroughput);
          Writeln('total metric reads: ', lTotalMetricReads, '  avg metric reads/s: ', lAvgMetricReadsPerSec);
          Writeln;

          if lCsv <> nil then
            AppendCsvSummaryRow(lCsv, 'scheduler-compare', lEntries[lIdx].Name, lRunCfg, lP50Us, lP95Us,
              lP99Us, lAvgUs, lBestUs,
              lWorstUs, lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec);
        except
          on E: Exception do
          begin
            Writeln('--- ', lEntries[lIdx].Name, ' ---');
            Writeln('FAILED: ', E.ClassName, ': ', E.Message);
            Writeln;
            if lCsv <> nil then
              AppendCsvFailureRow(lCsv, 'scheduler-compare', lEntries[lIdx].Name, lRunCfg,
                E.ClassName + ': ' + E.Message);
          end;
        end;
      end;
    end;

    if IsAllFrameworksFilter(lCfg.FrameworkFilter) then
      Writeln('Cross-library comparison: EventNexus(TTask-weak), EventNexus(TTask-strong), iPub, EventHorizon')
    else
      Writeln('Cross-library comparison: ', lCfg.FrameworkFilter);
    Writeln;
    lFrameworkCfg := lCfg;
    lFrameworkCfg.MetricsReaders := 0;
    lFrameworkCfg.MetricsReadsPerReader := 0;
    if (lFrameworkCfg.MaxInFlight > 64) then
    begin
      lFrameworkCfg.MaxInFlight := 64;
    end;
    if (lFrameworkCfg.Delivery <> TmaxDelivery.Posting) and (lFrameworkCfg.Runs > 1) then
    begin
      Writeln('Note: cross-library async profile is capped to 1 run in-process to avoid cumulative memory pressure.');
      lFrameworkCfg.Runs := 1;
    end;
    lFrameworkRan := False;
    for lFrameworkIdx := Low(lFrameworkEntries) to High(lFrameworkEntries) do
    begin
      if not IsFrameworkSelected(lCfg.FrameworkFilter, lFrameworkEntries[lFrameworkIdx].Name) then
        Continue;
      lFrameworkRan := True;
      try
        BenchmarkFramework(lFrameworkEntries[lFrameworkIdx], lFrameworkCfg, lSamples);
        SummarizeSamples(lSamples, lP50Us, lP95Us, lP99Us, lAvgUs, lBestUs, lWorstUs,
          lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec);

        Writeln('--- ', lFrameworkEntries[lFrameworkIdx].Name, ' ---');
        Writeln('p50 us: ', lP50Us);
        Writeln('p95 us: ', lP95Us);
        Writeln('p99 us: ', lP99Us);
        Writeln('avg us: ', lAvgUs, '  best us: ', lBestUs, '  worst us: ', lWorstUs);
        Writeln('avg throughput evt/s: ', lAvgThroughput);
        Writeln;

        if lCsv <> nil then
          AppendCsvSummaryRow(lCsv, 'framework-compare', lFrameworkEntries[lFrameworkIdx].Name,
            lFrameworkCfg, lP50Us, lP95Us, lP99Us, lAvgUs, lBestUs, lWorstUs, lAvgThroughput,
            lTotalMetricReads, lAvgMetricReadsPerSec);
      except
        on E: Exception do
        begin
          Writeln('--- ', lFrameworkEntries[lFrameworkIdx].Name, ' ---');
          Writeln('FAILED: ', E.ClassName, ': ', E.Message);
          Writeln;
          if lCsv <> nil then
            AppendCsvFailureRow(lCsv, 'framework-compare', lFrameworkEntries[lFrameworkIdx].Name,
              lFrameworkCfg, E.ClassName + ': ' + E.Message);
        end;
      end;
    end;
    if not lFrameworkRan then
    begin
      Writeln('No framework rows matched filter.');
      Writeln;
    end;

    if lCsv <> nil then
    begin
      lCsv.SaveToFile(lCfg.CsvPath);
      Writeln('Wrote CSV summary: ', lCfg.CsvPath);
    end;
  finally
    lCsv.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
