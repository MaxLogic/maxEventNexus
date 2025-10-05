# EventNexus Benchmarks

Performance benchmarks for EventNexus. Disabled by default.

## BenchHarness

```
# compile
fpc @../../../fpc.cfg BenchHarness.pas -Fu.. -FE.
# run with defaults
./BenchHarness
# custom run
./BenchHarness --producers=4 --consumers=4 --events=100000 --payload=256 --sticky --coalesce
```

Options:
- `--producers=N` number of posting threads (default 1)
- `--consumers=N` number of subscribers (default 1)
- `--events=N` posts per producer (default 100000)
- `--payload=BYTES` payload size in bytes (default 16)
- `--sticky` enable sticky cache
- `--coalesce` enable coalescing (single-key)

## KPI Targets

- throughput: ≥ 1M posts/s on 4 producers/4 consumers
- median latency: ≤ 50µs per event
- no drops at default policy under benchmark settings
