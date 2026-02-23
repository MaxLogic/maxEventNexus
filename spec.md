# EventNexus Specification

**Status:** Draft v1.0
**Target:** Delphi 12+
**Priorities:** correctness, predictable concurrency, low-allocation posting path

This spec defines the EventNexus public contract as implemented in this repository.

## 1. Goals and non-goals

### 1.1 Goals

- Provide a type-safe pub/sub event bus with typed, named, and GUID topic models.
- Keep posting path free from global bus lock contention.
- Provide delivery-mode control (`Posting`, `Main`, `Async`, `Background`).
- Support sticky latest-value caching and coalescing for burst reduction.
- Provide queue back-pressure controls and topic metrics.
- Keep tests executable from CLI with DUnitX.

### 1.2 Non-goals

- No generic methods on interfaces (Delphi `E2535` limitation still applies).
- No hard dependency on UI frameworks in core runtime.
- No transport/IPC concerns in the core in-process bus.

## 2. Public API model

## 2.1 Interface layer

- `ImaxBus`:
  - `SubscribeNamed`, `PostNamed`, `TryPostNamed`, `UnsubscribeAllFor`, `Clear`
- `ImaxBusAdvanced`:
  - `EnableStickyNamed`
- `ImaxBusQueues`:
  - `SetPolicyNamed`, `GetPolicyNamed`
- `ImaxBusMetrics`:
  - `GetStatsNamed`, `GetTotals`

These interfaces are intentionally non-generic.

## 2.2 Generic layer

Generic APIs live on `TmaxBus` (class).

Examples:

- `Subscribe<T>`, `Post<T>`, `TryPost<T>`
- `SubscribeNamedOf<T>`, `PostNamedOf<T>`, `TryPostNamedOf<T>`
- `SubscribeGuidOf<T: IInterface>`, `PostGuidOf<T>`, `TryPostGuidOf<T>`
- `EnableSticky<T>`, `EnableCoalesceOf<T>`, `EnableCoalesceNamedOf<T>`, `EnableCoalesceGuidOf<T>`
- `SetPolicyFor<T>`, `SetPolicyGuidOf<T>`, `GetPolicyFor<T>`, `GetPolicyGuidOf<T>`
- `GetStatsFor<T>`, `GetStatsGuidOf<T>`

Bridge from interface to class:

```pascal
var
  lBus: TmaxBus;
begin
  lBus := maxBusObj;
end;
```

## 2.3 Subscription lifetime

`Subscribe*` returns `ImaxSubscription`.

- `Unsubscribe` is idempotent.
- Releasing the last interface reference auto-unsubscribes.
- `UnsubscribeAllFor` removes subscriptions owned by the specified target object.

## 3. Threading and scheduling

Scheduler abstraction:

```pascal
type
  IEventNexusScheduler = interface
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;
```

Shipped adapters:

- `maxLogic.EventNexus.Threading.RawThread`
- `maxLogic.EventNexus.Threading.MaxAsync`
- `maxLogic.EventNexus.Threading.TTask`

Runtime injection:

```pascal
maxSetAsyncScheduler(CreateMaxAsyncScheduler);
```

## 4. Delivery semantics

- `Posting`: inline execution.
- `Main`: execute on main thread if available.
- `Async`: execute on scheduler async path.
- `Background`: execute async only when caller is main thread; otherwise inline.

### 4.1 Main-thread policy in console/service contexts

When `Main` delivery cannot marshal to UI loop:

- `Strict`: raise `EmaxMainThreadRequired`.
- `DegradeToAsync`: route to `RunAsync`.
- `DegradeToPosting`: run inline.

Configuration:

```pascal
maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
```

## 5. Topic families and routing

- Typed topics use `PTypeInfo` key.
- Named topics use case-insensitive string key.
- GUID topics use `TGuid` key.

Topic registries are protected by per-family locks. Posting does not take one global bus lock.

## 6. Subscriber storage and weak-target behavior

- Per-topic subscribers are stored in copy-on-write arrays.
- Dispatch reads snapshots, while subscribe/unsubscribe replace arrays.
- Object-method subscriptions track weak target liveness using pointer+generation metadata.
- Stale/dead targets are skipped during dispatch and pruned lazily.

## 7. Sticky and coalescing

Sticky:

- If enabled, topic caches latest payload/state.
- Late subscribers receive cached value according to their delivery mode.

Coalescing:

- Optional key selector picks coalesce key per event.
- Pending dictionary keeps latest value per key.
- Flushing uses scheduler `RunDelayed` (`aWindowUs`), not blocking sleeps.

## 8. Queue policy and back-pressure

Queue policy:

```pascal
type
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);

  TmaxQueuePolicy = record
    MaxDepth: Integer;
    Overflow: TmaxOverflow;
    DeadlineUs: Int64;
  end;
```

- `MaxDepth = 0` means unbounded.
- `DeadlineUs` is used by `Deadline` mode.

### 8.1 Queue preset categories (default strategy)

Preset values are provided by `TmaxBus.PolicyForPreset`:

| Preset | MaxDepth | Overflow | DeadlineUs | Intended use |
|---|---:|---|---:|---|
| `State` | 256 | `DropOldest` | 0 | state snapshots where latest wins |
| `Action` | 1024 | `Deadline` | 2000 | bursty action streams |
| `ControlPlane` | 1 | `Block` | 0 | strict control messages |
| `Unspecified` | 0 | `DropNewest` | 0 | default fallback |

Configuration hooks:

- `maxSetQueuePresetForType(TypeInfo(...), Preset)`
- `maxSetQueuePresetNamed('...', Preset)`
- `maxSetQueuePresetGuid(Guid, Preset)`

Override rules:

- Explicit per-topic `SetPolicy*` always wins.
- Preset applies only when topic policy is not explicit.
- Preset updates re-apply to already-created topics only if those topics still use implicit policy.

### 8.2 High-water warning integration

Queue depth warning state is tracked in topic metrics:

- warning enters at depth `> 10000`
- warning resets at depth `<= 5000`

State transitions trigger metric sampling path, so monitoring can detect both rise and recovery.

## 9. Metrics and diagnostics

Per-topic stats (`TmaxTopicStats`):

- `PostsTotal`
- `DeliveredTotal`
- `DroppedTotal`
- `ExceptionsTotal`
- `MaxQueueDepth`
- `CurrentQueueDepth`

API:

- `GetStatsNamed`
- `GetStatsFor<T>` / `GetStatsGuidOf<T>` (class path)
- `GetTotals`

Callback hooks:

- `maxSetMetricCallback`
- `maxSetMetricSampleInterval`

## 10. Error behavior

- Synchronous posting paths aggregate handler exceptions and raise `EmaxDispatchError`.
- Async/main/background delivery paths forward errors to global async hook when set:

```pascal
maxSetAsyncErrorHandler(
  procedure(const aTopic: string; const aE: Exception)
  begin
    // integration hook
  end);
```

## 11. Performance constraints

- No global bus lock around `Post`.
- Keep steady-state posting path allocation-light.
- Keep per-topic ordering guarantees while allowing concurrency across unrelated topics.

## 12. Testing contract (DUnitX)

Active harness is DUnitX.

Baseline commands:

- `./build-tests.sh`
- `./build-and-run-tests.sh`
- optional direct execution: `tests/MaxEventNexusTests.exe`

Test sources live in `tests/src`.

Benchmark contract is maintained by `bench/SchedulerCompare.dpr` with CSV/percentile schema documented in `docs/benchmarks/benchmark-output-contract.md`.

## 13. Documentation contract

`README.md`, `DESIGN.md`, `MIGRATION.md`, sample docs, and test docs must reflect the current Delphi-only runtime and DUnitX harness.

When runtime behavior changes, update docs and changelog in the same change.

## 14. Proposed extensions (not committed)

The following remain optional and require separate acceptance before implementation:

1. Priority subscriptions.
2. Bulk dispatch API.
3. Named-topic wildcard subscriptions.
4. Tracing hooks.
5. Serializer plug-in for IPC bridge.
6. Disruptor-style specialized sequences.
