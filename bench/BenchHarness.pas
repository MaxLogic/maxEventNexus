program BenchHarness;

{$APPTYPE CONSOLE}

uses
  System.Classes, System.Diagnostics, System.SysUtils,
  maxLogic.EventNexus.Core, maxLogic.EventNexus.Threading.MaxAsync;

type
  TBenchmarkConfig = record
    Producers: Integer;
    Consumers: Integer;
    Events: Integer;
    PayloadSize: Integer;
    Sticky: Boolean;
    Coalesce: Boolean;
  end;

  TPayload = record
    Data: TBytes;
  end;

  TProducer = class(TThread)
  private
    fBus: TmaxBus;
    fEvents: Integer;
    fPayload: TPayload;
  protected
    procedure Execute; override;
  public
    constructor Create(const aBus: TmaxBus; aEvents: Integer; const aPayload: TPayload);
  end;

constructor TProducer.Create(const aBus: TmaxBus; aEvents: Integer; const aPayload: TPayload);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  fBus := aBus;
  fEvents := aEvents;
  fPayload := aPayload;
end;

procedure TProducer.Execute;
var
  i: Integer;
begin
  for i := 1 to fEvents do
    fBus.Post<TPayload>(fPayload);
end;

procedure ParseArgs(var aCfg: TBenchmarkConfig);
const
  cPrefixConsumers = '--consumers=';
  cPrefixEvents = '--events=';
  cPrefixPayload = '--payload=';
  cPrefixProducers = '--producers=';
var
  i: Integer;
  lArg: string;
begin
  aCfg.Producers := 1;
  aCfg.Consumers := 1;
  aCfg.Events := 100000;
  aCfg.PayloadSize := 16;
  aCfg.Sticky := False;
  aCfg.Coalesce := False;

  for i := 1 to ParamCount do
  begin
    lArg := ParamStr(i);
    if Pos(cPrefixProducers, lArg) = 1 then
      aCfg.Producers := StrToIntDef(Copy(lArg, Length(cPrefixProducers) + 1), aCfg.Producers)
    else if Pos(cPrefixConsumers, lArg) = 1 then
      aCfg.Consumers := StrToIntDef(Copy(lArg, Length(cPrefixConsumers) + 1), aCfg.Consumers)
    else if Pos(cPrefixEvents, lArg) = 1 then
      aCfg.Events := StrToIntDef(Copy(lArg, Length(cPrefixEvents) + 1), aCfg.Events)
    else if Pos(cPrefixPayload, lArg) = 1 then
      aCfg.PayloadSize := StrToIntDef(Copy(lArg, Length(cPrefixPayload) + 1), aCfg.PayloadSize)
    else if lArg = '--sticky' then
      aCfg.Sticky := True
    else if lArg = '--coalesce' then
      aCfg.Coalesce := True;
  end;
end;

procedure RunBenchmark(const aCfg: TBenchmarkConfig);
var
  i: Integer;
  lBus: TmaxBus;
  lBusIntf: ImaxBus;
  lElapsedMs: Int64;
  lPayload: TPayload;
  lProducers: TArray<TProducer>;
  lStats: TmaxTopicStats;
  lStopwatch: TStopwatch;
  lSubs: TArray<ImaxSubscription>;
begin
  lBusIntf := TmaxBus.Create(CreateMaxAsyncScheduler);
  lBus := maxBusObj(lBusIntf);

  SetLength(lPayload.Data, aCfg.PayloadSize);
  for i := 0 to High(lPayload.Data) do
    lPayload.Data[i] := Byte(i);

  if aCfg.Sticky then
    lBus.EnableSticky<TPayload>(True);
  if aCfg.Coalesce then
    lBus.EnableCoalesceOf<TPayload>(
      function(const aValue: TPayload): TmaxString
      begin
        Result := 'k';
      end);

  SetLength(lSubs, aCfg.Consumers);
  for i := 0 to High(lSubs) do
    lSubs[i] := lBus.Subscribe<TPayload>(
      procedure(const aValue: TPayload)
      begin
      end);

  lStopwatch := TStopwatch.StartNew;
  SetLength(lProducers, aCfg.Producers);
  for i := 0 to High(lProducers) do
    lProducers[i] := TProducer.Create(lBus, aCfg.Events, lPayload);
  for i := 0 to High(lProducers) do
  begin
    lProducers[i].WaitFor;
    lProducers[i].Free;
  end;
  lElapsedMs := lStopwatch.ElapsedMilliseconds;

  lStats := lBus.GetStatsFor<TPayload>;

  Writeln('Producers: ', aCfg.Producers);
  Writeln('Consumers: ', aCfg.Consumers);
  Writeln('Events per producer: ', aCfg.Events);
  Writeln('Payload bytes: ', aCfg.PayloadSize);
  Writeln('Sticky: ', aCfg.Sticky);
  Writeln('Coalesce: ', aCfg.Coalesce);
  Writeln('Time ms: ', lElapsedMs);
  Writeln('Posted: ', lStats.PostsTotal, ' Delivered: ', lStats.DeliveredTotal);
  if lElapsedMs > 0 then
    Writeln('Throughput evt/s: ', (lStats.DeliveredTotal * 1000) div UInt64(lElapsedMs));
end;

var
  lCfg: TBenchmarkConfig;

begin
  ParseArgs(lCfg);
  RunBenchmark(lCfg);
end.
