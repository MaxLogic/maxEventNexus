# Bench Harness Overview

This folder contains standalone executables used to exercise and compare
different event-bus implementations.  All programs are console apps; build
them with Delphi (unless otherwise noted) and run them directly from the command
line.

## 1. EventNexus-Only Workloads

### `BenchHarness.pas`

*Purpose:* Stress EventNexus with configurable producers, consumers, payload
size, sticky cache, and coalescing.

```
fpc @../../../fpc.cfg BenchHarness.pas -Fu.. -FE.
./BenchHarness --producers=4 --consumers=4 --events=100000 --payload=256 --sticky --coalesce
```

Metrics printed:

| Field | Meaning |
|-------|---------|
| `Time ms` | Wall-clock duration from first post to final consumer completion |
| `Throughput evt/s` | Delivered events ÷ duration |
| `Posted/Delivered` | Counters from EventNexus metrics surface |

### `SchedulerCompare.dpr` (Delphi)

*Purpose:* Compare internal scheduler adapters (`TmaxRawThreadScheduler`,
`TmaxAsyncScheduler`, `TmaxTTaskScheduler`) under identical loads.

```
dcc32 SchedulerCompare.dpr
SchedulerCompare
```

Each run reports elapsed time for posting/consuming 20k events with four async
subscribers.

## 2. Cross-Framework Comparison

### `CompareBuses.dpr` (Delphi)

*Purpose:* Measure throughput and heap deltas across:

- EventNexus (configured with the MaxAsync adapter)
- iPub Messaging (`reference/iPub.Rtl.Messaging.pas`)
- NX Horizon (`reference/NX.Horizon.pas`)

```
dcc32 CompareBuses.dpr
CompareBuses --producers=4 --consumers=4 --events=50000
```

### Behaviour under Test

1. A `TBenchmarkEvent` holds an integer payload via the `IBenchmarkEvent`
   interface so all buses can exchange the same type.
2. For each bus, a wrapper implements:
   - `Subscribe` — registers the callback using that library’s idioms (async
     delivery mode where available).
   - `Post` — pushes `IBenchmarkEvent` instances.
   - `Clear` — tears down subscriptions to avoid leaks between runs.
3. Producers (`TProducerThread`) post events in parallel.  Consumers decrement
   an atomic “remaining events” counter and signal an event object when all work
   drains.  Main thread waits with `CheckSynchronize` to let queued main-thread
   work execute.

### Output

For each framework the benchmark prints:

| Field | Meaning |
|-------|---------|
| `Elapsed ms` | Total duration for all producers + drain time |
| `Throughput evt/s` | Total events × 1000 ÷ elapsed milliseconds |
| `Heap delta (bytes)` | `GetHeapStatus.TotalAllocated` delta before/after run |
| `TotalAllocated delta` | Aggregated allocation delta from `GetMemoryManagerState` |

These deltas help identify sustained memory growth across frameworks.

### Customising Runs

Command-line switches mirror `BenchHarness`:

```
--producers=N   Number of posting threads (default 4)
--consumers=N   Number of subscribers per bus (default 4)
--events=N      Events posted per producer (default 50,000)
```

Increase these values to explore heavy-load scenarios.  Keep an eye on timeout
exceptions which indicate a bus failed to drain within 60 seconds.

## 3. Adding New Buses or Schedulers

1. Implement `IBenchmarkBus` wrappers for the new framework in
   `CompareBuses.dpr`.
2. Register the new entry in the `entries` array inside `RunAllBenchmarks`.
3. (Optional) Add a scheduler factory to `SchedulerCompare.dpr` for finer
   adapter comparisons.

Please ensure any added dependency units remain checked-in under `reference/`
or `lib/` so the benchmarks build out of the box.
