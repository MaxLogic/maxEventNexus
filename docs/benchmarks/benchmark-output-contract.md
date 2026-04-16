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

## Mailbox Benchmark CSV Contract

- Tool: `bench/BenchHarness.exe`
- Modes: `--mode=mailbox-direct` and `--mode=mailbox-bus`
- Scope: portable mailbox end-to-end receiver handoff plus drain throughput; used to decide whether platform specialization is justified
- Receiver topology: one owner-thread mailbox and one receiver thread only (`--consumers=1`)

Header:

```text
scenario,target,producers,events,elapsed_us,throughput_ops_s,accepted,dropped,pumped,status,error
```

Field notes:

- `scenario`: fixed value `mailbox-benchmark`
- `target`: `mailbox-direct` or `mailbox-bus`
- `events`: total events across all producers (`producers * events-per-producer`)
- `accepted`: successful enqueue or bus post admissions
- `dropped`: rejected admissions; the maintained unbounded benchmark profiles expect `0`
- `pumped`: items executed on the receiver mailbox owner thread
- `elapsed_us` / `throughput_ops_s`: end-to-end timing from producer start until the receiver mailbox drains the expected work
- `status`: `ok` or `failed`
- `error`: non-empty only when `status=failed`

Recommended proof commands:

```batch
bench\BenchHarness.exe --mode=mailbox-direct --producers=4 --events=50000 --csv=build\analysis\mailbox-direct.csv
bench\BenchHarness.exe --mode=mailbox-bus --producers=4 --events=50000 --csv=build\analysis\mailbox-bus.csv
```

Success condition:

- each process exits `0`
- each CSV file exists with header + one `mailbox-benchmark` row
- each row reports `status=ok`, `dropped=0`, and `accepted=pumped`

## Mailbox Specialization Trigger

Keep the portable mailbox implementation as the default baseline.

Specialized mailbox work is justified only if:

- we gather at least 5 isolated samples per maintained mailbox profile
- median throughput improves by at least 25% on `mailbox-direct`
- median throughput improves by at least 15% on `mailbox-bus`
- no maintained mailbox profile regresses by more than 5%
- mailbox semantics stay identical across close, clear, overflow, and coalescing behavior

If those thresholds are not met, reject specialization and keep the portable mailbox path only.
Current benchmark evidence does not meet the trigger, so no specialized mailbox implementation ships today.
