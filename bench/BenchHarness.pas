program BenchHarness;

{$APPTYPE CONSOLE}

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.StrUtils, System.SyncObjs,
  System.SysUtils,
  maxLogic.EventNexus, maxLogic.EventNexus.Core, maxLogic.EventNexus.Mailbox,
  maxLogic.EventNexus.Threading.MaxAsync;

type
  TBenchmarkMode = (BenchmarkEventBus, BenchmarkMailboxDirect, BenchmarkMailboxBus);

  TBenchmarkConfig = record
    Producers: Integer;
    Consumers: Integer;
    Events: Integer;
    PayloadSize: Integer;
    Sticky: Boolean;
    Coalesce: Boolean;
    Mode: TBenchmarkMode;
    CsvPath: string;
    TimeoutMs: Cardinal;
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

  TMailboxResult = record
    Accepted: Int64;
    Dropped: Int64;
    ElapsedUs: Int64;
    ErrorText: string;
    Pumped: Int64;
    Producers: Integer;
    Scenario: string;
    Status: string;
    ThroughputOpsPerSec: Int64;
    TotalEvents: Int64;
  end;

  TMailboxBusConsumer = class
  private
    fOwner: Pointer;
  public
    constructor Create(aOwner: Pointer);
    procedure Handle(const aValue: Integer);
  end;

  TMailboxReceiverThread = class(TThread)
  private
    fBus: ImaxBus;
    fConsumer: TMailboxBusConsumer;
    fDone: TEvent;
    fErrorText: string;
    fExpectedTotal: Int64;
    fMailbox: ImaxMailbox;
    fMode: TBenchmarkMode;
    fPumped: Int64;
    fReady: TEvent;
    fSubscription: ImaxSubscription;
  protected
    procedure Execute; override;
  public
    constructor Create(const aBus: ImaxBus; aMode: TBenchmarkMode; aExpectedTotal: Int64;
      const aReady, aDone: TEvent);
    destructor Destroy; override;
    property ErrorText: string read fErrorText;
    property Mailbox: ImaxMailbox read fMailbox;
    property Pumped: Int64 read fPumped;
  end;

  TMailboxProducer = class(TThread)
  private
    fAccepted: Int64;
    fBusObj: TmaxBus;
    fDropped: Int64;
    fErrorText: string;
    fEvents: Integer;
    fMailbox: ImaxMailbox;
    fMode: TBenchmarkMode;
    fReceiver: TMailboxReceiverThread;
  protected
    procedure Execute; override;
  public
    constructor Create(const aBusObj: TmaxBus; const aMailbox: ImaxMailbox; const aReceiver: TMailboxReceiverThread;
      aMode: TBenchmarkMode; aEvents: Integer);
    property Accepted: Int64 read fAccepted;
    property Dropped: Int64 read fDropped;
    property ErrorText: string read fErrorText;
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

constructor TMailboxReceiverThread.Create(const aBus: ImaxBus; aMode: TBenchmarkMode; aExpectedTotal: Int64;
  const aReady, aDone: TEvent);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fBus := aBus;
  fDone := aDone;
  fExpectedTotal := aExpectedTotal;
  fMode := aMode;
  fPumped := 0;
  fReady := aReady;
  fSubscription := nil;
end;

destructor TMailboxReceiverThread.Destroy;
begin
  fSubscription := nil;
  fConsumer.Free;
  inherited;
end;

constructor TMailboxBusConsumer.Create(aOwner: Pointer);
begin
  inherited Create;
  fOwner := aOwner;
end;

procedure TMailboxBusConsumer.Handle(const aValue: Integer);
var
  lOwner: TMailboxReceiverThread;
begin
  lOwner := TMailboxReceiverThread(fOwner);
  if aValue <> 0 then
  begin
  end;
  if TInterlocked.Increment(lOwner.fPumped) = lOwner.fExpectedTotal then
    lOwner.fDone.SetEvent;
end;

procedure TMailboxReceiverThread.Execute;
var
  lBusObj: TmaxBus;
begin
  try
    fMailbox := TmaxMailbox.Create;
    if fMode = BenchmarkMailboxBus then
    begin
      lBusObj := maxBusObj(fBus);
      fConsumer := TMailboxBusConsumer.Create(Self);
      fSubscription := lBusObj.SubscribeIn<Integer>(fMailbox, fConsumer.Handle);
    end;
    fReady.SetEvent;

    while not Terminated do
    begin
      if not fMailbox.PumpOne(10) then
      begin
        if TInterlocked.CompareExchange(fPumped, 0, 0) >= fExpectedTotal then
          Break;
      end;
    end;
  except
    on e: Exception do
    begin
      fErrorText := e.ClassName + ': ' + e.Message;
      fDone.SetEvent;
      fReady.SetEvent;
    end;
  end;
end;

constructor TMailboxProducer.Create(const aBusObj: TmaxBus; const aMailbox: ImaxMailbox;
  const aReceiver: TMailboxReceiverThread; aMode: TBenchmarkMode; aEvents: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fAccepted := 0;
  fBusObj := aBusObj;
  fDropped := 0;
  fErrorText := '';
  fEvents := aEvents;
  fMailbox := aMailbox;
  fMode := aMode;
  fReceiver := aReceiver;
end;

procedure TMailboxProducer.Execute;
var
  i: Integer;
  lAccepted: Boolean;
begin
  try
    for i := 1 to fEvents do
    begin
      case fMode of
        BenchmarkMailboxDirect:
          lAccepted := fMailbox.TryPost(
            procedure
            begin
              if TInterlocked.Increment(fReceiver.fPumped) = fReceiver.fExpectedTotal then
                fReceiver.fDone.SetEvent;
            end);
        BenchmarkMailboxBus:
          begin
            fBusObj.Post<Integer>(i);
            lAccepted := True;
          end;
      else
        lAccepted := False;
      end;

      if lAccepted then
        Inc(fAccepted)
      else
        Inc(fDropped);
    end;
  except
    on e: Exception do
      fErrorText := e.ClassName + ': ' + e.Message;
  end;
end;

function BenchmarkModeName(aMode: TBenchmarkMode): string;
begin
  case aMode of
    BenchmarkEventBus:
      Result := 'event-bus';
    BenchmarkMailboxDirect:
      Result := 'mailbox-direct';
    BenchmarkMailboxBus:
      Result := 'mailbox-bus';
  else
    Result := 'event-bus';
  end;
end;

function BenchmarkTimeoutMs(aCfg: TBenchmarkConfig): Cardinal;
begin
  Result := aCfg.TimeoutMs;
  if Result = 0 then
    Result := 30000;
end;

function CsvSafe(const aValue: string): string;
begin
  Result := StringReplace(aValue, '"', '""', [rfReplaceAll]);
end;

function ParseBenchmarkMode(const aValue: string): TBenchmarkMode;
begin
  if SameText(aValue, 'mailbox-direct') then
    Exit(BenchmarkMailboxDirect);
  if SameText(aValue, 'mailbox-bus') then
    Exit(BenchmarkMailboxBus);
  Result := BenchmarkEventBus;
end;

procedure ParseArgs(var aCfg: TBenchmarkConfig);
const
  cPrefixConsumers = '--consumers=';
  cPrefixCsv = '--csv=';
  cPrefixEvents = '--events=';
  cPrefixMode = '--mode=';
  cPrefixPayload = '--payload=';
  cPrefixProducers = '--producers=';
  cPrefixTimeoutMs = '--timeout-ms=';
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
  aCfg.Mode := BenchmarkEventBus;
  aCfg.CsvPath := '';
  aCfg.TimeoutMs := 30000;

  for i := 1 to ParamCount do
  begin
    lArg := ParamStr(i);
    if StartsText(cPrefixProducers, lArg) then
      aCfg.Producers := StrToIntDef(Copy(lArg, Length(cPrefixProducers) + 1), aCfg.Producers)
    else if StartsText(cPrefixConsumers, lArg) then
      aCfg.Consumers := StrToIntDef(Copy(lArg, Length(cPrefixConsumers) + 1), aCfg.Consumers)
    else if StartsText(cPrefixEvents, lArg) then
      aCfg.Events := StrToIntDef(Copy(lArg, Length(cPrefixEvents) + 1), aCfg.Events)
    else if StartsText(cPrefixPayload, lArg) then
      aCfg.PayloadSize := StrToIntDef(Copy(lArg, Length(cPrefixPayload) + 1), aCfg.PayloadSize)
    else if StartsText(cPrefixMode, lArg) then
      aCfg.Mode := ParseBenchmarkMode(Copy(lArg, Length(cPrefixMode) + 1))
    else if StartsText(cPrefixCsv, lArg) then
      aCfg.CsvPath := Copy(lArg, Length(cPrefixCsv) + 1)
    else if StartsText(cPrefixTimeoutMs, lArg) then
      aCfg.TimeoutMs := StrToIntDef(Copy(lArg, Length(cPrefixTimeoutMs) + 1), Integer(aCfg.TimeoutMs))
    else if lArg = '--sticky' then
      aCfg.Sticky := True
    else if lArg = '--coalesce' then
      aCfg.Coalesce := True;
  end;
end;

function ResultElapsedUs(const aStopwatch: TStopwatch): Int64;
begin
  Result := (aStopwatch.ElapsedTicks * 1000000) div TStopwatch.Frequency;
end;

procedure RunEventBusBenchmark(const aCfg: TBenchmarkConfig);
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
        if Length(aValue.Data) >= 0 then
          Result := 'k'
        else
          Result := 'k';
      end);

  SetLength(lSubs, aCfg.Consumers);
  for i := 0 to High(lSubs) do
    lSubs[i] := lBus.Subscribe<TPayload>(
      procedure(const aValue: TPayload)
      begin
        if Length(aValue.Data) < 0 then
          raise Exception.Create('Unreachable payload size');
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

  Writeln('Mode: ', BenchmarkModeName(aCfg.Mode));
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

procedure WriteMailboxCsv(const aCfg: TBenchmarkConfig; const aResult: TMailboxResult);
var
  lCsvLine: string;
  lDirectory: string;
  lFileExists: Boolean;
  lWriter: TextFile;
begin
  if aCfg.CsvPath = '' then
    Exit;

  lDirectory := ExtractFileDir(aCfg.CsvPath);
  if lDirectory <> '' then
    ForceDirectories(lDirectory);

  lFileExists := FileExists(aCfg.CsvPath);
  AssignFile(lWriter, aCfg.CsvPath);
  if lFileExists then
    Append(lWriter)
  else
    Rewrite(lWriter);
  try
    if not lFileExists then
      Writeln(lWriter, 'scenario,target,producers,events,elapsed_us,throughput_ops_s,accepted,dropped,pumped,status,error');

    lCsvLine := Format('mailbox-benchmark,%s,%d,%d,%d,%d,%d,%d,%d,%s,"%s"',
      [aResult.Scenario, aResult.Producers, aResult.TotalEvents, aResult.ElapsedUs, aResult.ThroughputOpsPerSec,
       aResult.Accepted, aResult.Dropped, aResult.Pumped, aResult.Status, CsvSafe(aResult.ErrorText)]);
    Writeln(lWriter, lCsvLine);
  finally
    CloseFile(lWriter);
  end;
end;

procedure WriteMailboxSummary(const aResult: TMailboxResult);
begin
  Writeln('Mode: ', aResult.Scenario);
  Writeln('Producers: ', aResult.Producers);
  Writeln('Total events: ', aResult.TotalEvents);
  Writeln('Accepted: ', aResult.Accepted);
  Writeln('Dropped: ', aResult.Dropped);
  Writeln('Pumped: ', aResult.Pumped);
  Writeln('Elapsed us: ', aResult.ElapsedUs);
  Writeln('Throughput ops/s: ', aResult.ThroughputOpsPerSec);
  Writeln('Status: ', aResult.Status);
  if aResult.ErrorText <> '' then
    Writeln('Error: ', aResult.ErrorText);
end;

procedure RunMailboxProducers(const aCfg: TBenchmarkConfig; const aBusObj: TmaxBus;
  const aMailbox: ImaxMailbox; const aReceiver: TMailboxReceiverThread; out aAccepted, aDropped: Int64);
var
  i: Integer;
  lProducer: TMailboxProducer;
  lProducers: TArray<TMailboxProducer>;
begin
  aAccepted := 0;
  aDropped := 0;
  SetLength(lProducers, aCfg.Producers);
  try
    for i := 0 to High(lProducers) do
      lProducers[i] := TMailboxProducer.Create(aBusObj, aMailbox, aReceiver, aCfg.Mode, aCfg.Events);
    for i := 0 to High(lProducers) do
      lProducers[i].Start;
    for i := 0 to High(lProducers) do
    begin
      lProducer := lProducers[i];
      lProducer.WaitFor;
      if lProducer.ErrorText <> '' then
        raise Exception.Create(lProducer.ErrorText);
      Inc(aAccepted, lProducer.Accepted);
      Inc(aDropped, lProducer.Dropped);
    end;
  finally
    for i := 0 to High(lProducers) do
      lProducers[i].Free;
  end;
end;

procedure RunMailboxBenchmark(const aCfg: TBenchmarkConfig);
var
  lBusObj: TmaxBus;
  lAccepted: Int64;
  lBusIntf: ImaxBus;
  lDone: TEvent;
  lDropped: Int64;
  lExpectedTotal: Int64;
  lMailbox: ImaxMailbox;
  lReady: TEvent;
  lReceiver: TMailboxReceiverThread;
  lResult: TMailboxResult;
  lStopwatch: TStopwatch;
begin
  if aCfg.Consumers <> 1 then
    raise Exception.CreateFmt('Mailbox benchmark modes require --consumers=1 but got %d', [aCfg.Consumers]);
  if aCfg.Producers <= 0 then
    raise Exception.CreateFmt('Mailbox benchmark modes require --producers>0 but got %d', [aCfg.Producers]);
  if aCfg.Events <= 0 then
    raise Exception.CreateFmt('Mailbox benchmark modes require --events>0 but got %d', [aCfg.Events]);

  lAccepted := 0;
  lDropped := 0;
  lExpectedTotal := Int64(aCfg.Producers) * aCfg.Events;
  lResult.Accepted := 0;
  lResult.Dropped := 0;
  lResult.ElapsedUs := 0;
  lResult.ErrorText := '';
  lResult.Pumped := 0;
  lResult.Producers := aCfg.Producers;
  lResult.Scenario := BenchmarkModeName(aCfg.Mode);
  lResult.Status := 'failed';
  lResult.ThroughputOpsPerSec := 0;
  lResult.TotalEvents := lExpectedTotal;

  lBusIntf := nil;
  lBusObj := nil;
  if aCfg.Mode = BenchmarkMailboxBus then
  begin
    lBusIntf := TmaxBus.Create(CreateMaxAsyncScheduler);
    lBusObj := maxBusObj(lBusIntf);
  end;

  lDone := TEvent.Create(nil, True, False, '');
  lReady := TEvent.Create(nil, True, False, '');
  lReceiver := TMailboxReceiverThread.Create(lBusIntf, aCfg.Mode, lExpectedTotal, lReady, lDone);
  try
    lReceiver.Start;
    if lReady.WaitFor(BenchmarkTimeoutMs(aCfg)) <> wrSignaled then
      raise Exception.Create('Mailbox receiver did not become ready');
    if lReceiver.ErrorText <> '' then
      raise Exception.Create(lReceiver.ErrorText);

    lMailbox := lReceiver.Mailbox;
    lStopwatch := TStopwatch.StartNew;
    RunMailboxProducers(aCfg, lBusObj, lMailbox, lReceiver, lAccepted, lDropped);

    if lDone.WaitFor(BenchmarkTimeoutMs(aCfg)) <> wrSignaled then
      raise Exception.Create('Mailbox benchmark timed out waiting for the receiver to drain');

    lResult.Accepted := lAccepted;
    lResult.Dropped := lDropped;
    lResult.ElapsedUs := ResultElapsedUs(lStopwatch);
    lResult.Pumped := lReceiver.Pumped;
    if lResult.ElapsedUs > 0 then
      lResult.ThroughputOpsPerSec := (lResult.Pumped * 1000000) div lResult.ElapsedUs;

    if lReceiver.ErrorText <> '' then
      raise Exception.Create(lReceiver.ErrorText);
    if lResult.Accepted <> lExpectedTotal then
      raise Exception.CreateFmt('Expected %d accepted posts but got %d', [lExpectedTotal, lResult.Accepted]);
    if lResult.Dropped <> 0 then
      raise Exception.CreateFmt('Expected 0 dropped posts but got %d', [lResult.Dropped]);
    if lResult.Pumped <> lExpectedTotal then
      raise Exception.CreateFmt('Expected %d pumped items but got %d', [lExpectedTotal, lResult.Pumped]);

    lResult.Status := 'ok';
  except
    on e: Exception do
      lResult.ErrorText := e.ClassName + ': ' + e.Message;
  end;

  lReceiver.Terminate;
  lReceiver.WaitFor;
  lReceiver.Free;
  lReady.Free;
  lDone.Free;
  if lBusIntf <> nil then
    lBusIntf.Clear;

  WriteMailboxSummary(lResult);
  WriteMailboxCsv(aCfg, lResult);

  if not SameText(lResult.Status, 'ok') then
  begin
    if lResult.ErrorText <> '' then
      raise Exception.Create(lResult.ErrorText);
    raise Exception.Create('Mailbox benchmark failed');
  end;
end;

var
  lCfg: TBenchmarkConfig;

begin
  ParseArgs(lCfg);
  case lCfg.Mode of
    BenchmarkEventBus:
      RunEventBusBenchmark(lCfg);
    BenchmarkMailboxDirect,
    BenchmarkMailboxBus:
      RunMailboxBenchmark(lCfg);
  end;
end.
