# Benchmark Overview

This folder contains Delphi benchmark programs for EventNexus.

## Build

- `./build-delphi.sh bench/SchedulerCompare.dproj -config Release`
- `./build-delphi.sh bench/CompareBuses.dproj -config Release`

## EventNexus workload (`BenchHarness.pas`)

Purpose:

- stress post/dispatch throughput with configurable producers, subscribers, and payload size,
- exercise sticky and coalescing options.

Example runs:

```bash
./bench/BenchHarness --producers=4 --consumers=4 --events=100000 --payload=256 --sticky --coalesce
./bench/BenchHarness --producers=4 --consumers=1000 --events=20000 --payload=64
```

The second scenario is the high-subscriber stress profile used to validate copy-on-write snapshot scaling.

Reported fields:

- `Time ms`
- `Throughput evt/s`
- `Posted/Delivered`

## Scheduler and cross-library comparison (`SchedulerCompare.dpr`)

Compares internal scheduler adapters under equivalent workloads and emits percentile summaries:

- `TmaxRawThreadScheduler`
- `TmaxAsyncScheduler`
- `TmaxTTaskScheduler`

Also emits cross-library rows in the same CSV for:

- `EventNexus(maxAsync)`
- `iPub`
- `EventHorizon`

Key options:

- `--events=<n>`
- `--consumers=<n>`
- `--runs=<n>`
- `--delivery=posting|main|async|background`
- `--metrics-readers=<n>`
- `--metrics-reads=<n>`
- `--csv=<path>`

Example:

```batch
bench\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\scheduler-summary.csv
```

Output contract (clock source, percentile method, CSV schema):

- `docs/benchmarks/benchmark-output-contract.md`

Threshold gate (pass/fail, scheduler rows only):

- `./build/check-benchmark-thresholds.sh bench/scheduler-summary.csv`
- `build\\check-benchmark-thresholds.bat bench\\scheduler-summary.csv`
- Optional second argument overrides threshold config path (default: `bench/scheduler-thresholds.csv`).

## Legacy cross-framework runner (`CompareBuses.dpr`)

`CompareBuses.dpr` remains as a standalone legacy harness, but the primary comparable output is now emitted directly by `SchedulerCompare.dpr`.

## Notes

- CSV rows include `status` and `error` columns so scheduler-specific failures are visible while still producing one complete report file.
