program BenchHarness;

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes,
  maxLogic.EventNexus;

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
    fEvents: Integer;
    fPayload: TPayload;
  protected
    procedure Execute; override;
  public
    constructor Create(aEvents: Integer; const aPayload: TPayload);
  end;

{ TProducer }

constructor TProducer.Create(aEvents: Integer; const aPayload: TPayload);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  fEvents := aEvents;
  fPayload := aPayload;
end;

procedure TProducer.Execute;
var
  i: Integer;
begin
  for i := 1 to fEvents do
    MLBus.Post<TPayload>(fPayload);
end;

procedure ParseArgs(var aCfg: TBenchmarkConfig);
var
  i: Integer;
  s: string;
const
  PREFIX_PROD = '--producers=';
  PREFIX_CONS = '--consumers=';
  PREFIX_EVT  = '--events=';
  PREFIX_PAY  = '--payload=';
begin
  aCfg.Producers := 1;
  aCfg.Consumers := 1;
  aCfg.Events := 100000;
  aCfg.PayloadSize := 16;
  aCfg.Sticky := False;
  aCfg.Coalesce := False;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if Pos(PREFIX_PROD, s) = 1 then
      aCfg.Producers := StrToIntDef(Copy(s, Length(PREFIX_PROD) + 1), aCfg.Producers)
    else if Pos(PREFIX_CONS, s) = 1 then
      aCfg.Consumers := StrToIntDef(Copy(s, Length(PREFIX_CONS) + 1), aCfg.Consumers)
    else if Pos(PREFIX_EVT, s) = 1 then
      aCfg.Events := StrToIntDef(Copy(s, Length(PREFIX_EVT) + 1), aCfg.Events)
    else if Pos(PREFIX_PAY, s) = 1 then
      aCfg.PayloadSize := StrToIntDef(Copy(s, Length(PREFIX_PAY) + 1), aCfg.PayloadSize)
    else if s = '--sticky' then
      aCfg.Sticky := True
    else if s = '--coalesce' then
      aCfg.Coalesce := True;
  end;
end;

procedure RunBenchmark(const aCfg: TBenchmarkConfig);
var
  payload: TPayload;
  producers: array of TProducer;
  subs: array of IMLSubscription;
  i: Integer;
  startTick, stopTick: QWord;
  metrics: IMLBusMetrics;
  stats: TMLTopicStats;
{$IFDEF FPC}
  procedure Consume(const aValue: TPayload);
  begin
    // no-op
  end;
{$ENDIF}
begin
  SetLength(payload.Data, aCfg.PayloadSize);
  for i := 0 to High(payload.Data) do
    payload.Data[i] := Byte(i);

  if aCfg.Sticky then
    MLBus.EnableSticky<TPayload>(True);
  if aCfg.Coalesce then
    (MLBus as IMLBusAdvanced).EnableCoalesceOf<TPayload>(
      function(const aValue: TPayload): TMLString
      begin
        Result := 'k';
      end);

  SetLength(subs, aCfg.Consumers);
{$IFDEF FPC}
  for i := 0 to High(subs) do
    subs[i] := MLBus.Subscribe<TPayload>(@Consume);
{$ELSE}
  var lHandler: TMLProcOf<TPayload>;
  lHandler :=
    procedure(const aValue: TPayload)
    begin
      // no-op
    end;
  for i := 0 to High(subs) do
    subs[i] := MLBus.Subscribe<TPayload>(lHandler);
{$ENDIF}

  startTick := GetTickCount64;
  SetLength(producers, aCfg.Producers);
  for i := 0 to High(producers) do
    producers[i] := TProducer.Create(aCfg.Events, payload);
  for i := 0 to High(producers) do
  begin
    producers[i].WaitFor;
    producers[i].Free;
  end;
  stopTick := GetTickCount64;

  metrics := MLBus as IMLBusMetrics;
  stats := metrics.GetStatsFor<TPayload>;

  Writeln('Producers: ', aCfg.Producers);
  Writeln('Consumers: ', aCfg.Consumers);
  Writeln('Events per producer: ', aCfg.Events);
  Writeln('Payload bytes: ', aCfg.PayloadSize);
  Writeln('Sticky: ', aCfg.Sticky);
  Writeln('Coalesce: ', aCfg.Coalesce);
  Writeln('Time ms: ', stopTick - startTick);
  Writeln('Posted: ', stats.PostsTotal, ' Delivered: ', stats.DeliveredTotal);
  if stopTick > startTick then
    Writeln('Throughput evt/s: ', (stats.DeliveredTotal * 1000) div (stopTick - startTick));
end;

var
  cfg: TBenchmarkConfig;
begin
  ParseArgs(cfg);
  RunBenchmark(cfg);
end.

