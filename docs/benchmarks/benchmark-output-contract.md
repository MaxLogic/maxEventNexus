# Benchmark Output Contract

- Tool: `bench/SchedulerCompare.exe`
- Scope: scheduler comparison + contention-aware metrics read load
- Status: active contract for `T-1019`

## Clock Source

- `TStopwatch.GetTimeStamp` / `TStopwatch.ElapsedTicks`
- Conversion: `elapsed_us = (ElapsedTicks * 1_000_000) div TStopwatch.Frequency`

## Percentile Method

- Method: **nearest-rank**
- Input: run-level latency values (`elapsed_us`) per scheduler/profile
- Percentiles: `p50`, `p95`, `p99`

## CSV Schema

Output file is written with `--csv=<path>` and contains one summary row per benchmark target.

Header:

```text
scenario,scheduler,delivery,consumers,events,runs,p50_us,p95_us,p99_us,avg_us,best_us,worst_us,avg_throughput_evt_s,total_metric_reads,avg_metric_reads_s,clock,percentile_method,status,error
```

Field notes:

- `scenario`: `scheduler-compare` | `framework-compare`
- `scheduler`: scheduler rows use `raw-thread` | `maxAsync` | `TTask`; framework rows use `EventNexus(TTask-weak)` | `EventNexus(TTask-strong)` | `iPub` | `EventHorizon`
- `delivery`: `posting` | `main` | `async` | `background`
- `status`: `ok` or `failed`
- `error`: non-empty only when `status=failed`

For failed schedulers in a run, metric/latency numeric fields are emitted as `0` and failure is captured in `error`.

## Recommended CLI Proof Command

```batch
bench\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\scheduler-summary.csv
```

Success condition:

- process exits `0`
- CSV file exists and has header + at least 3 `scheduler-compare` rows
- enabled framework rows (`framework-compare`) are emitted with `status=ok`
