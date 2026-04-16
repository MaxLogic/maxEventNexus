# Benchmark Overview

This folder contains Delphi benchmark programs for EventNexus.

## Build

- `./build-delphi.sh bench/SchedulerCompare.dproj -config Release`
- `./build-delphi.sh bench/BenchHarness.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex`

## EventNexus workload (`BenchHarness.pas`)

Purpose:

- stress post/dispatch throughput with configurable producers, subscribers, and payload size,
- exercise sticky and coalescing options.
- provide a maintained mailbox benchmark path for raw `ImaxMailbox.TryPost` handoff and mailbox-bound `SubscribeIn<T>` delivery.

Example runs:

```bash
./build-delphi.sh bench/BenchHarness.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex
./bench/BenchHarness --producers=4 --consumers=4 --events=100000 --payload=256 --sticky --coalesce
./bench/BenchHarness --producers=4 --consumers=1000 --events=20000 --payload=64
./bench/BenchHarness --mode=mailbox-direct --producers=4 --events=50000 --csv=build/analysis/mailbox-direct.csv
./bench/BenchHarness --mode=mailbox-bus --producers=4 --events=50000 --csv=build/analysis/mailbox-bus.csv
```

Implementation note:

- `BenchHarness` now uses the supported Delphi generic bridge contract (`TmaxBus` via `maxBusObj(...)`) rather than unsupported generic-interface calls.

The second scenario is the high-subscriber stress profile used to validate copy-on-write snapshot scaling.

Reported fields:

- `Time ms`
- `Throughput evt/s`
- `Posted/Delivered`

Mailbox benchmark modes:

- `--mode=mailbox-direct`: measures end-to-end raw `ImaxMailbox.TryPost` handoff into one owner-thread mailbox that pumps continuously until all work is drained.
- `--mode=mailbox-bus`: measures end-to-end `SubscribeIn<Integer>(mailbox, ...)` receiver handoff through EventNexus into one owner-thread mailbox that pumps continuously until all work is drained.
- Mailbox benchmark rows can emit CSV through `--csv=<path>` with the contract documented in `docs/benchmarks/benchmark-output-contract.md`.
- Mailbox modes use one receiver mailbox and one receiver thread only, so `--consumers=1` is required.
- Mailbox modes treat `--events` as events per producer, so total work is `producers * events`.

Convenience runner:

```batch
build\run-mailbox-benchmark.bat
```

This writes:

- `build\analysis\mailbox-direct.csv`
- `build\analysis\mailbox-bus.csv`

Specialization trigger criteria:

- treat the portable mailbox as the default baseline for all supported targets
- only consider a specialized mailbox implementation after at least 5 isolated samples per maintained profile
- require at least 25% median throughput improvement on `mailbox-direct`
- require at least 15% median throughput improvement on `mailbox-bus`
- reject any specialization that regresses the other maintained mailbox profile by more than 5% or changes semantics
- current evidence does not justify a specialized mailbox implementation, so the portable mailbox remains the only shipped path

## Scheduler and cross-library comparison (`SchedulerCompare.dpr`)

Compares internal scheduler adapters under equivalent workloads and emits percentile summaries:

- `TmaxRawThreadScheduler`
- `TmaxAsyncScheduler`
- `TmaxTTaskScheduler`

Also emits cross-library rows in the same CSV for:

- `EventNexus(TTask-weak)`
- `EventNexus(TTask-strong)`
- `iPub`
- `EventHorizon`

Key options:

- `--events=<n>`
- `--consumers=<n>`
- `--runs=<n>`
- `--delivery=posting|main|async|background`
- `--metrics-readers=<n>`
- `--metrics-reads=<n>`
- `--skip-schedulers`
- `--framework=all|weak|strong|ipub|eventhorizon`
- `--csv=<path>`

Example:

```batch
bench\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\scheduler-summary.csv
```

Default verification smoke:

```batch
bench\SchedulerCompare.exe --events=200 --consumers=1 --runs=1 --delivery=async --metrics-readers=0 --metrics-reads=0 --framework=weak --csv=build\analysis\benchmark-smoke.csv
build\check-benchmark-smoke.bat build\analysis\benchmark-smoke.csv
```

Framework-only async smoke:

```batch
build\run-framework-benchmark-smoke.bat
```

Output contract (clock source, percentile method, CSV schema):

- `docs/benchmarks/benchmark-output-contract.md`

Threshold gate (pass/fail, scheduler rows only):

- `./build/check-benchmark-thresholds.sh bench/scheduler-summary.csv`
- `build\\check-benchmark-thresholds.bat bench\\scheduler-summary.csv`
- Optional second argument overrides threshold config path (default: `bench/scheduler-thresholds.csv`).

Isolated-process framework medians (fresh process per sample):

```bash
./bench/run-framework-isolated.sh --delivery=async --events=2000 --consumers=2 --samples=9 --platform=Win32 --max-inflight=0
```

This runner executes one framework row per process (`--skip-schedulers --framework=<token> --runs=1`) and writes a summary CSV with median `avg_us` and median throughput.

## Legacy cross-framework runner (`CompareBuses.dpr`)

`CompareBuses.dpr` remains as legacy source only. There is no maintained `CompareBuses.dproj`, and the supported comparable output path is `SchedulerCompare.dpr`.

## Notes

- CSV rows include `status` and `error` columns so scheduler-specific failures are visible while still producing one complete report file.
