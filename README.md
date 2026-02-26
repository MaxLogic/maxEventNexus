# EventNexus

## What's New (2026-02-23)

- Runtime/public units are now fully Delphi-only; remaining FPC conditionals were removed from adapter/facade scheduler paths.
- Tests run through DUnitX (`tests/MaxEventNexusTests.dpr`) with compatibility support for published-method legacy suites.
- Delphi AutoSubscribe one-parameter attributed handlers now bind correctly for typed, named, and GUID topics.
- Test/CI scripts enforce diagnostics policy (`build/diagnostics-policy.regex`) so untriaged warnings/hints fail the build.
- Async benchmark profile is stabilized (bounded queue/in-flight guards + scheduler submission fallbacks), with CSV contract rows remaining `status=ok`.
- Sample and benchmark projects now carry explicit unit search paths for shared foundation/mORMot units in group builds.
- Queue policy preset defaults/overrides and lock-free posting behavior are documented for typed, named, and GUID topics.
- Added delayed posting APIs (`PostDelayed*`) with cancel/pending handle semantics.

EventNexus is a type-safe event bus for Delphi 12+ with typed, named, and GUID topic routing, delivery-mode control, sticky cache, coalescing, and queue policies.

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

- `maxLogic.EventNexus.Threading.RawThread` (default fallback)
- `maxLogic.EventNexus.Threading.MaxAsync`
- `maxLogic.EventNexus.Threading.TTask`

Inject at runtime:

```pascal
uses
  maxLogic.EventNexus, maxLogic.EventNexus.Threading.MaxAsync;

begin
  maxSetAsyncScheduler(CreateMaxAsyncScheduler);
end;
```

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
- Diagnostics policy gate: build scripts enforce `build/diagnostics-policy.regex` and fail on untriaged warnings/hints.

The test runner is DUnitX-based and executes the active fixture suite from `tests/src`.

## Docs

- `spec.md`
- `DESIGN.md`
- `MIGRATION.md`
- `samples/readme.md`
- `tests/readme.md`
