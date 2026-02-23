program SchedulerCompare;

{$APPTYPE CONSOLE}

uses
  Classes, SysUtils, SyncObjs,
  System.Diagnostics, System.Generics.Collections, System.Math, System.StrUtils,
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

  TBenchmarkConfig = record
    Events: Integer;
    Consumers: Integer;
    Runs: Integer;
    Delivery: TmaxDelivery;
    CsvPath: string;
    MetricsReaders: Integer;
    MetricsReadsPerReader: Int64;
  end;

  TRunSample = record
    ElapsedUs: Int64;
    ThroughputPerSec: Int64;
    MetricReads: Int64;
    MetricReadsPerSec: Int64;
  end;

  TMetricsReaderThread = class(TThread)
  private
    fBusObj: TmaxBus;
    fStopEvent: TEvent;
    fMaxReads: Int64;
    fReads: Int64;
  protected
    procedure Execute; override;
  public
    constructor Create(aBusObj: TmaxBus; aStopEvent: TEvent; aMaxReads: Int64);
    property Reads: Int64 read fReads;
  end;

const
  cClockName = 'TStopwatch.GetTimeStamp';
  cPercentileMethod = 'nearest-rank';

function CreateRawThreadScheduler: IEventNexusScheduler;
begin
  Result := TmaxRawThreadScheduler.Create;
end;

constructor TMetricsReaderThread.Create(aBusObj: TmaxBus; aStopEvent: TEvent; aMaxReads: Int64);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  fBusObj := aBusObj;
  fStopEvent := aStopEvent;
  fMaxReads := aMaxReads;
  fReads := 0;
end;

procedure TMetricsReaderThread.Execute;
var
  lReads: Int64;
begin
  lReads := 0;
  while fStopEvent.WaitFor(0) <> wrSignaled do
  begin
    fBusObj.GetStatsFor<Integer>;
    Inc(lReads);
    if (fMaxReads > 0) and (lReads >= fMaxReads) then
      Break;
  end;
  fReads := lReads;
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

procedure PrintUsage;
begin
  Writeln('Usage: SchedulerCompare [options]');
  Writeln('  --events=<n>            events posted per run (default: 20000)');
  Writeln('  --consumers=<n>         subscriber count (default: 4)');
  Writeln('  --runs=<n>              benchmark runs per scheduler (default: 9)');
  Writeln('  --delivery=<mode>       posting|main|async|background (default: async)');
  Writeln('  --metrics-readers=<n>   concurrent stats-reader threads (default: 0)');
  Writeln('  --metrics-reads=<n>     max reads per reader, 0=unbounded until run ends (default: 0)');
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
  lReaders: array of TMetricsReaderThread;
  lSubs: array of ImaxSubscription;
  lRemaining: Integer;
  lRemainingLock: TCriticalSection;
  lI: Integer;
  lScheduler: IEventNexusScheduler;
  lWatch: TStopwatch;
  lElapsedUs: Int64;
  lDelivered: Int64;
  lMetricReads: Int64;
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
    try
      lRemaining := aCfg.Events * aCfg.Consumers;
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
      for lI := 1 to aCfg.Consumers do
        lSubs[lI - 1] := lBusObj.Subscribe<Integer>(lHandler, aCfg.Delivery);

      if aCfg.MetricsReaders > 0 then
      begin
        SetLength(lReaders, aCfg.MetricsReaders);
        for lI := 0 to High(lReaders) do
          lReaders[lI] := TMetricsReaderThread.Create(lBusObj, lStopReaders, aCfg.MetricsReadsPerReader);
      end;

      lWatch := TStopwatch.StartNew;
      for lI := 1 to aCfg.Events do
        lBusObj.Post<Integer>(lI);

      if (lRemaining > 0) and (not WaitForSignal(lDone, 60000)) then
        raise Exception.CreateFmt('%s failed to drain queue on run %d', [aEntry.Name, lRun + 1]);

      lWatch.Stop;
      lElapsedUs := ElapsedUs(lWatch);
      lDelivered := Int64(aCfg.Events) * aCfg.Consumers;

      lStopReaders.SetEvent;
      for lI := 0 to High(lReaders) do
      begin
        lReaders[lI].WaitFor;
        Inc(lMetricReads, lReaders[lI].Reads);
        lReaders[lI].Free;
      end;

      aSamples[lRun].ElapsedUs := lElapsedUs;
      aSamples[lRun].ThroughputPerSec := (lDelivered * 1000000) div lElapsedUs;
      aSamples[lRun].MetricReads := lMetricReads;
      if lElapsedUs > 0 then
        aSamples[lRun].MetricReadsPerSec := (lMetricReads * 1000000) div lElapsedUs
      else
        aSamples[lRun].MetricReadsPerSec := 0;
    finally
      lStopReaders.Free;
      lRemainingLock.Free;
      lDone.Free;
      lScheduler := nil;
      SetLength(lSubs, 0);
      SetLength(lReaders, 0);
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

procedure AppendCsvSummary(aLines: TStrings; const aEntry: TSchedulerEntry; const aCfg: TBenchmarkConfig;
  aP50Us, aP95Us, aP99Us, aAvgUs, aBestUs, aWorstUs, aAvgThroughput, aTotalMetricReads,
  aAvgMetricReadsPerSec: Int64);
begin
  aLines.Add('scheduler-compare,' +
    aEntry.Name + ',' +
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

procedure AppendCsvFailure(aLines: TStrings; const aEntry: TSchedulerEntry; const aCfg: TBenchmarkConfig;
  const aError: string);
begin
  aLines.Add('scheduler-compare,' +
    aEntry.Name + ',' +
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
  lEntries: array of TSchedulerEntry;
  lIdx: Integer;
  lSamples: TArray<TRunSample>;
  lP50Us, lP95Us, lP99Us: Int64;
  lAvgUs, lBestUs, lWorstUs: Int64;
  lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec: Int64;
  lCsv: TStringList;
begin
  ParseArgs(lCfg);

  SetLength(lEntries, 3);
  lEntries[0].Name := 'raw-thread';
  lEntries[0].Factory := CreateRawThreadScheduler;
  lEntries[1].Name := 'maxAsync';
  lEntries[1].Factory := CreateMaxAsyncScheduler;
  lEntries[2].Name := 'TTask';
  lEntries[2].Factory := CreateTTaskScheduler;

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
    Writeln;

    for lIdx := Low(lEntries) to High(lEntries) do
    begin
      try
        BenchmarkScheduler(lEntries[lIdx], lCfg, lSamples);
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
          AppendCsvSummary(lCsv, lEntries[lIdx], lCfg, lP50Us, lP95Us, lP99Us, lAvgUs, lBestUs,
            lWorstUs, lAvgThroughput, lTotalMetricReads, lAvgMetricReadsPerSec);
      except
        on E: Exception do
        begin
          Writeln('--- ', lEntries[lIdx].Name, ' ---');
          Writeln('FAILED: ', E.ClassName, ': ', E.Message);
          Writeln;
          if lCsv <> nil then
            AppendCsvFailure(lCsv, lEntries[lIdx], lCfg, E.ClassName + ': ' + E.Message);
        end;
      end;
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
