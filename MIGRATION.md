# EventNexus Migration Guide

This guide maps common iPub/NX Horizon usage into current EventNexus APIs and runtime behavior.

## Runtime shape to keep in mind

- Interface layer (`ImaxBus*`) is non-generic on Delphi.
- Generic APIs live on `TmaxBus`.
- Use `maxBusObj` (or `maxBusObj(aBusInterface)`) when we need generic `TmaxBus` calls.
- Test harness is DUnitX (`tests/MaxEventNexusTests.dpr`).

## Recommended subscription lifetime pattern

`Subscribe*` returns `ImaxSubscription`.

- Keep token in a field for lifecycle ownership.
- Set token to `nil` in teardown/destructor for auto-unsubscribe.
- Explicit `Unsubscribe` remains valid and idempotent.

## iPub to EventNexus mapping

| iPub concept | EventNexus equivalent |
|---|---|
| `Post(name, payload)` | `PostNamedOf<T>(name, payload)` on `TmaxBus` |
| `Post(interface)` | `PostGuidOf<T>(payload)` on `TmaxBus` |
| `Post(type)` | `Post<T>(payload)` on `TmaxBus` |
| `Subscribe(name, handler)` | `SubscribeNamed(name, handler)` on `ImaxBus` |
| `Subscribe(type, handler)` | `Subscribe<T>(handler)` on `TmaxBus` |
| Auto wiring attributes | `maxSubscribeAttribute` + `AutoSubscribe`/`AutoUnsubscribe` |

## NX Horizon to EventNexus mapping

| NX Horizon concept | EventNexus equivalent |
|---|---|
| `Publish<T>` / `Subscribe<T>` | `Post<T>` / `Subscribe<T>` |
| Immediate/Main/Background | `Posting`, `Main`, `Async`, `Background` |
| Sticky events | `EnableSticky<T>(True)` / `EnableStickyNamed(...)` |
| Coalescing | `EnableCoalesceOf<T>(...)` |
| Queue throttling | `SetPolicy*` and `maxSetQueuePreset*` |

## Main delivery policy migration

If old code assumes UI-thread marshaling always exists, set explicit policy for console/service workloads:

```pascal
maxSetMainThreadPolicy(TmaxMainThreadPolicy.Strict);
// or DegradeToAsync / DegradeToPosting
```

Behavior when posting `Main` from non-main thread in console context:

- `Strict`: raises `EmaxMainThreadRequired`.
- `DegradeToAsync`: schedules on async executor.
- `DegradeToPosting`: executes inline on posting thread.

## Queue preset migration

If old code relied on implicit queue behavior, configure preset defaults once:

```pascal
maxSetQueuePresetNamed('orders.state', TmaxQueuePreset.State);
maxSetQueuePresetForType(TypeInfo(TOrderPlaced), TmaxQueuePreset.Action);
maxSetQueuePresetGuid(StringToGUID('{00000000-0000-0000-0000-000000000000}'), TmaxQueuePreset.ControlPlane);
```

Explicit per-topic `SetPolicy*` overrides presets.

## Test migration to DUnitX

- Build: `./build-tests.sh`
- Build + run: `./build-and-run-tests.sh`
- Runner: `tests/MaxEventNexusTests.exe`

When porting older tests, we should use DUnitX fixtures/assertions and keep deterministic proof commands in `TASKS.md`.
