# EventNexus

## What's New (2026-02-26)

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

## Performance and Scope Snapshot (2026-02-28)

The cross-library benchmark uses a deliberately small common surface (`subscribe + post`) across EventNexus, iPub, and EventHorizon.
So raw speed numbers below do not include advanced features such as delayed posting, queue policies, tracing, or sticky/coalescing behavior.

Method:

- Tool: `bench/SchedulerCompare.exe` with `bench/run-framework-isolated.sh`
- Isolated-process medians (fresh process per sample)
- Async profile: `--events=2000 --consumers=2 --runs=1 --delivery=async --max-inflight=64`
- Successful samples per framework: `5` (retry budget `max-attempts=20`)
- Platform lanes: Win32 and Win64

Median async framework results (Win32):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 30967 | 129169 | 5 | 5 |
| EventNexus(TTask-strong) | 47795 | 83690 | 5 | 5 |
| iPub | 44833 | 89219 | 5 | 5 |
| EventHorizon | 46160 | 86655 | 5 | 6 |

Median async framework results (Win64):

| Framework | Median avg us | Median throughput evt/s | Successful samples | Attempts |
|---|---:|---:|---:|---:|
| EventNexus(TTask-weak) | 34380 | 116346 | 5 | 5 |
| EventNexus(TTask-strong) | 57959 | 69014 | 5 | 5 |
| iPub | 27783 | 143972 | 5 | 5 |
| EventHorizon | 44085 | 90733 | 5 | 6 |

Interpretation:

- Win32 async: EventNexus weak is ahead of iPub in this run set; EventNexus strong is slightly behind iPub.
- Win64 async: iPub is ahead of both EventNexus weak and EventNexus strong in this run set.
- EventHorizon needed retries in both lanes (`wait-drain` transient failures), which is why we report successful-sample counts and attempt counts.
- This update reports async-only medians; posting will be refreshed in a follow-up run with the same isolated-process method.

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

## Sticky and coalescing

- Sticky: `EnableSticky<T>(True)` / `EnableStickyNamed(...)` caches latest event.
- Coalescing: `EnableCoalesceOf<T>(...)`, `EnableCoalesceNamedOf<T>(...)`, `EnableCoalesceGuidOf<T>(...)` keeps latest value per key per window.

## Scheduling adapters

`IEventNexusScheduler` implementations shipped in this repo:

- `maxLogic.EventNexus.Threading.MaxAsync` (recommended default)
- `maxLogic.EventNexus.Threading.RawThread` (threading fallback)
- `maxLogic.EventNexus.Threading.TTask`

Recommendation:

- Default to `MaxAsync` for lowest async latency and highest throughput on current Delphi targets.
- Use `RawThread` when you want a minimal dependency chain and predictable behavior in constrained runtime environments.
- Use `TTask` when you explicitly want RTL-native scheduling semantics.

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

## Tests (DUnitX)

- Build tests: `./build-tests.sh`
- Build + run tests: `./build-and-run-tests.sh`
- Binary: `tests/MaxEventNexusTests.exe`
- Coverage depth (current suite): 32 legacy test classes with 88 published test methods executed via the DUnitX compatibility fixture.
- Diagnostics policy gate: build scripts enforce `build/diagnostics-policy.regex` and fail on untriaged warnings/hints.
- API coverage proxy: `./build/report-api-test-coverage.sh --enforce-target` (target in `build/api-test-coverage-target.txt`, report in `build/analysis/test-api-coverage.md`).

The test runner is DUnitX-based and executes the active fixture suite from `tests/src`. DUnitX reports one top-level fixture because it hosts the legacy published-method suite runner.

## Docs

- `spec.md`
- `DESIGN.md`
- `MIGRATION.md`
- `samples/readme.md`
- `tests/readme.md`
