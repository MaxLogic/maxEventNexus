# EventNexus

## What's New (2026-03-21)

- Refreshed the published isolated-process benchmark snapshot for Win32/Win64 async and posting profiles, and stabilized the framework benchmark smoke path around the final `SchedulerCompare` contract.
- `Clear` now stays a runtime reset: explicit queue policies and coalescing configuration survive, while queued/pending runtime state is still dropped.
- `PostResult<T>`, `PostResultNamedOf<T>`, and `PostResultGuidOf<T>` now report live `AutoSubscribe` handlers as real receivers instead of returning `NoTopic`.
- Deferred-only `AutoSubscribe` handlers now make `PostResult<T>`, `PostResultNamedOf<T>`, and `PostResultGuidOf<T>` return `Queued` instead of misreporting `DispatchedInline`, with `Main`/`Background` decided from the actual runtime context.
- Named-of topics now resolve queue presets as explicit `SetPolicyNamed(name, ...)` policy, then name preset, then type preset, then `Unspecified`; type-preset changes also reapply to existing implicit named-of topics.
- `bench/BenchHarness` now uses the supported `TmaxBus` / `maxBusObj(...)` bridge contract and has a maintained `bench/BenchHarness.dproj` build path.
- Runtime/public units are now fully Delphi-only; remaining FPC conditionals were removed from adapter/facade scheduler paths.
- Tests run through DUnitX (`tests/MaxEventNexusTests.dpr`) with compatibility support for published-method legacy suites.
- Delphi AutoSubscribe one-parameter attributed handlers now bind correctly for typed, named, and GUID topics.
- Test/CI scripts enforce diagnostics policy (`build/diagnostics-policy.regex`) so untriaged warnings/hints fail the build.
- Async benchmark profile is stabilized (bounded queue/in-flight guards + scheduler submission fallbacks), with CSV contract rows remaining `status=ok`.
- Sample and benchmark projects now carry explicit unit search paths for shared foundation/mORMot units in group builds.
- Queue policy preset defaults/overrides and lock-free posting behavior are documented for typed, named, and GUID topics.
- Added delayed posting APIs (`PostDelayed*`) with cancel/pending handle semantics.
- Reduced static-analysis top debt again (`C101=20`, `C103=14`) with test-fixture refactors and no public API changes.
- Hardened delayed-posting edge coverage: zero-delay dispatch/metrics/cancel semantics and deterministic long-delay pending/cancel behavior.
- Added optional strong object-method subscriptions (`SubscribeStrong<T>`, `SubscribeNamedOfStrong<T>`, `SubscribeGuidOfStrong<T>`) for callers that guarantee subscriber lifetime and want to skip weak-liveness tracking overhead.

EventNexus is a type-safe event bus for Delphi 12+ with typed, named, and GUID topic routing, delivery-mode control, sticky cache, coalescing, and queue policies.

## Performance and Scope Snapshot (2026-03-21)

The cross-library benchmark uses a deliberately small common surface (`subscribe + post`) across EventNexus, iPub, and EventHorizon.
So raw speed numbers below do not include advanced features such as delayed posting, queue policies, tracing, or sticky/coalescing behavior.

Method:

- Tool: `bench/SchedulerCompare.exe` with `bench/run-framework-isolated.sh`
- Isolated-process medians (fresh process per sample)
- Async profile: `--events=2000 --consumers=2 --runs=1 --delivery=async --max-inflight=0`
- Posting profile: `--events=2000 --consumers=2 --runs=1 --delivery=posting --max-inflight=0`
- Successful samples per framework: `5` (retry budget `max-attempts=10`)
- Platform lanes: Win32 and Win64

Median async framework results (Win32):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 31003 | 129019 | 5 | 9 |
| EventNexus(TTask-strong) | 18856 | 212134 | 5 | 5 |
| iPub | 16493 | 242527 | 5 | 5 |
| EventHorizon | 16267 | 245896 | 5 | 5 |

Median async framework results (Win64):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 35768 | 111831 | 5 | 5 |
| EventNexus(TTask-strong) | 23531 | 169988 | 5 | 6 |
| iPub | 9431 | 424133 | 5 | 5 |
| EventHorizon | 27335 | 146332 | 5 | 5 |

Median posting framework results (Win32):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 856 | 4672897 | 5 | 5 |
| EventNexus(TTask-strong) | 783 | 5108556 | 5 | 5 |
| iPub | 644 | 6211180 | 5 | 5 |
| EventHorizon | 1687 | 2371072 | 5 | 5 |

Median posting framework results (Win64):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 996 | 4016064 | 5 | 5 |
| EventNexus(TTask-strong) | 761 | 5256241 | 5 | 5 |
| iPub | 608 | 6578947 | 5 | 5 |
| EventHorizon | 1693 | 2362669 | 5 | 5 |

Interpretation:

- Win32 async: EventHorizon and iPub lead this run set; EventNexus strong is third, while EventNexus weak needed several retries before producing five successful samples.
- Win64 async: iPub leads, EventNexus strong is second, EventHorizon is third, and EventNexus weak is fourth; EventNexus strong needed one retry to complete the sample set.
- Posting lanes: iPub leads both lanes, EventNexus strong is second in both lanes, EventNexus weak is third, and EventHorizon is slowest.
- RawThread is intentionally absent from the cross-framework tables: those rows keep EventNexus on the same `subscribe + post` TTask-backed surface as the comparison libraries, while RawThread remains our dedicated-thread non-pool scheduler when we want isolation from the Delphi thread pool.

Feature scope beyond baseline pub/sub:

- The benchmark surface is minimal (`subscribe/post`), but EventNexus currently ships at least 16 major runtime capabilities around it:
  typed topics, named topics, GUID topics, 4 delivery modes, main-thread fallback policy, sticky cache, coalescing, queue overflow policies, queue presets, delayed posting with cancel/pending handle, `TryPost*` and `PostResult*`, metrics snapshots/callbacks, wildcard named subscriptions, bulk dispatch APIs, dispatch tracing hooks, and weak/strong object-method subscription modes.

## Core API shape on Delphi

Delphi does not allow generic methods on interfaces (`E2535`), so the public API is split:

- `ImaxBus` / `ImaxBusAdvanced` / `ImaxBusQueues` / `ImaxBusMetrics` expose non-generic named operations.
- `TmaxBus` exposes generic typed/named/GUID methods.
- Typed bridge `maxBusObj(...)` gives access to `TmaxBus` when we start from an interface.

### Interface-first example (named topic)

```pascal
uses
  maxLogic.EventNexus;

var
  lBus: ImaxBus;
  lSub: ImaxSubscription;
begin
  lBus := maxBus;
  lSub := lBus.SubscribeNamed('ping',
    procedure
    begin
      Writeln('pong');
    end,
    TmaxDelivery.Posting);

  lBus.PostNamed('ping');
  lSub := nil; // auto-unsubscribe
end;
```

### Generic example (typed topic)

```pascal
uses
  maxLogic.EventNexus, maxLogic.EventNexus.Core;

type
  TOrderPlaced = record
    Id: Integer;
  end;

var
  lBus: TmaxBus;
  lSub: ImaxSubscription;
begin
  lBus := maxBusObj;
  lSub := lBus.Subscribe<TOrderPlaced>(
    procedure(const aEvent: TOrderPlaced)
    begin
      Writeln(aEvent.Id);
    end,
    TmaxDelivery.Posting);

  lBus.Post<TOrderPlaced>(Default(TOrderPlaced));
  lSub := nil;
end;
```

## Delivery modes and main-thread policy

`TmaxDelivery` values:

- `Posting`: inline on the caller thread.
- `Main`: marshaled to main/UI thread when available.
- `Async`: queued via configured scheduler.
- `Background`: async when called on main thread, otherwise inline.

For console/service contexts where `Main` cannot marshal to a UI loop, configure fallback behavior:

```pascal
maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
// or DegradeToAsync / Strict
```

Policy behavior:

- `Strict`: raises `EmaxMainThreadRequired`.
- `DegradeToAsync`: reroutes `Main` delivery to scheduler async path.
- `DegradeToPosting`: runs handler on posting thread.

## Delayed posting

Use delayed post APIs when event delivery should happen later:

```pascal
var
  lBus: TmaxBus;
  lDelayed: ImaxDelayedPost;
begin
  lBus := maxBusObj;
  lDelayed := lBus.PostDelayed<Integer>(42, 30000); // 30 seconds
  // lDelayed.Cancel;
end;
```

Timing note:

- `PostDelayed*` delay values are configured in milliseconds.
- Scheduler/coalescing internals use microsecond request units, but on current Delphi/Windows backends those requests are best-effort and may round up to the nearest supported timer resolution.
- `0` remains immediate-eligible; any positive delay remains delayed.
- Delayed-post failures stay on the async path: install `maxSetAsyncErrorHandler(...)` if we need to observe them.
- Without an async error hook, a delayed handler failure is swallowed after the delayed execution path and is not synchronously re-raised to the original `PostDelayed*` caller.

## Queue policies

Per-topic policy (`TmaxQueuePolicy`) controls bounded queue behavior:

- `MaxDepth = 0` means unbounded.
- `Overflow = DropNewest | DropOldest | Block | Deadline`.
- `DeadlineUs` is used by `Deadline` overflow mode.

Set explicit policy:

```pascal
var
  lQueues: ImaxBusQueues;
  lPolicy: TmaxQueuePolicy;
begin
  lQueues := maxBus as ImaxBusQueues;
  lPolicy.MaxDepth := 256;
  lPolicy.Overflow := TmaxOverflow.DropOldest;
  lPolicy.DeadlineUs := 0;
  lQueues.SetPolicyNamed('orders.state', lPolicy);
end;
```

Preset defaults (`TmaxQueuePreset`) apply only when no explicit policy exists:

| Preset | MaxDepth | Overflow | DeadlineUs |
|---|---:|---|---:|
| `State` | 256 | `DropOldest` | 0 |
| `Action` | 1024 | `Deadline` | 2000 |
| `ControlPlane` | 1 | `Block` | 0 |
| `Unspecified` | 0 | `DropNewest` | 0 |

Configure presets:

```pascal
maxSetQueuePresetNamed('orders.state', TmaxQueuePreset.State);
maxSetQueuePresetForType(TypeInfo(TOrderPlaced), TmaxQueuePreset.Action);
maxSetQueuePresetGuid(StringToGUID('{00000000-0000-0000-0000-000000000000}'), TmaxQueuePreset.ControlPlane);
```

For named-of topics (`SubscribeNamedOf<T>` / `PostNamedOf<T>`), implicit queue policy precedence is:

- explicit `SetPolicyNamed(aName, ...)`
- `maxSetQueuePresetNamed(aName, ...)`
- `maxSetQueuePresetForType(TypeInfo(T), ...)`
- `Unspecified`

That means a type preset now acts as the fallback default for named-of topics when no name-specific preset exists, and preset updates reapply to already-created named-of topics while they still use implicit policy.

## Sticky and coalescing

- Sticky: `EnableSticky<T>(True)` / `EnableStickyNamed(...)` caches latest event.
- Coalescing: `EnableCoalesceOf<T>(...)`, `EnableCoalesceNamedOf<T>(...)`, `EnableCoalesceGuidOf<T>(...)` keeps latest value per key per window.

`Clear` stays a runtime reset, not a durable-config wipe:

- `Clear` drops subscriptions, queued work, sticky cached values, pending coalesce batches, and delayed posts scheduled before the clear boundary.
- `Clear` preserves sticky enablement, explicit per-topic queue policies, queue presets, coalescing selectors/windows, scheduler identity, and bus main-thread identity.

## Scheduling adapters

`IEventNexusScheduler` implementations shipped in this repo:

- `maxLogic.EventNexus.Threading.MaxAsync` (recommended default)
- `maxLogic.EventNexus.Threading.RawThread` (threading fallback)
- `maxLogic.EventNexus.Threading.TTask`

Recommendation:

- Default to `MaxAsync` for lowest async latency and highest throughput on current Delphi targets.
- Use `RawThread` when you want the scheduler to bypass the Delphi thread pool and run async/delayed work on dedicated `TThread` instances.
- Use `TTask` when you explicitly want RTL-native scheduling semantics.
- `MaxAsync` preserves async/delayed semantics on backend submission failure by falling back to dedicated-thread execution before any final inline safety net.

Delay-resolution note:

- `RunDelayed(aDelayUs)` is a best-effort request, not a promise of exact microsecond wake-up precision.
- Shipped adapters preserve the semantic distinction between `0` and positive delay values; positive delays may round up to backend timer granularity.

## Object-method lifetime modes

- `Subscribe<T>(objproc)`, `SubscribeNamedOf<T>(objproc)`, and `SubscribeGuidOf<T>(objproc)` use weak-target liveness tracking by default.
- `SubscribeStrong<T>`, `SubscribeNamedOfStrong<T>`, and `SubscribeGuidOfStrong<T>` intentionally skip weak-target checks for callers that can guarantee subscriber lifetime through unsubscribe/release.
- Use the strong variants only when we fully control the subscriber lifetime and want to skip weak-liveness overhead.

Inject at runtime:

```pascal
uses
  maxLogic.EventNexus, maxLogic.EventNexus.Threading.MaxAsync;

begin
  maxSetAsyncScheduler(CreateMaxAsyncScheduler);
end;
```

## Performance recommendation (memory manager)

For high-throughput workloads, we recommend using FastMM5 as the process memory manager.
EventNexus dispatch paths make heavy use of closures/managed values under async delivery, and FastMM5 usually reduces allocator contention and latency jitter versus the default RTL manager.

- FastMM5 project: https://github.com/pleriche/FastMM5
- Integration: add `FastMM5` as the first unit in the `.dpr` `uses` list.
- Licensing: FastMM5 supports both GPL and commercial licensing.

## Metrics

Install callback + throttle interval:

```pascal
maxSetMetricSampleInterval(250);
maxSetMetricCallback(
  procedure(const aName: string; const aStats: TmaxTopicStats)
  begin
    // lightweight snapshot
  end);
```

## Dispatch tracing

- `maxSetDispatchTrace` emits `TraceEnqueue`, `TraceInvokeStart`, `TraceInvokeEnd`, and `TraceInvokeError`.
- `TraceEnqueue` is a topic-queue signal, not a per-subscriber delivery report. Its `Delivery` value reflects topic-level queue semantics and is currently emitted as `Posting`.
- `TraceInvoke*` events are per-invocation and carry the subscriber delivery mode actually used for that handler.

## Tests (DUnitX)

- Build tests: `./build-tests.sh`
- Build + run tests: `./build-and-run-tests.sh`
- Stress runner: `./run-stress.sh`
- Binary: `tests/MaxEventNexusTests.exe`
- Coverage depth (current suite): the DUnitX compatibility fixture executes the active published-method regression suite from `tests/src`, including dedicated scheduler-contract coverage.
- Default verification also runs a lightweight `bench/SchedulerCompare` smoke profile plus a framework-only async smoke, and validates the documented benchmark CSV contract.
- Diagnostics policy gate: build scripts enforce `build/diagnostics-policy.regex` and fail on untriaged warnings/hints.
- API coverage proxy: `./build/report-api-test-coverage.sh --enforce-target` (target in `build/api-test-coverage-target.txt`, report in `build/analysis/test-api-coverage.md`).

The test runner is DUnitX-based and executes the active fixture suite from `tests/src`. DUnitX reports one top-level fixture because it hosts the legacy published-method suite runner.

## Docs

- `spec.md`
- `DESIGN.md`
- `MIGRATION.md`
- `samples/readme.md`
- `tests/readme.md`
