# EventNexus Migration Guide

This guide maps common iPub/NX Horizon usage into current EventNexus APIs and runtime behavior.

## Runtime shape to keep in mind

- Interface layer (`ImaxBus*`) is non-generic on Delphi.
- Generic APIs live on `TmaxBus`.
- Use `maxBusObj` (or `maxBusObj(aBusInterface)`) when we need generic `TmaxBus` calls.
- Object-method subscriptions are weak-liveness tracked by default; `SubscribeStrong*` variants intentionally opt out when we fully own subscriber lifetime.
- Test harness is DUnitX (`tests/MaxEventNexusTests.dpr`).

## Recommended subscription lifetime pattern

`Subscribe*` returns `ImaxSubscription`.

- Keep token in a field for lifecycle ownership.
- Set token to `nil` in teardown/destructor for auto-unsubscribe.
- Explicit `Unsubscribe` remains valid and idempotent.
- Prefer default weak subscriptions unless we intentionally choose `SubscribeStrong*` and can guarantee subscriber lifetime until teardown.

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

## Mailbox delivery migration

Use mailbox delivery when a receiver must execute on its own thread or cooperative loop instead of on the posting thread, main thread, or shared async scheduler.

- Choose `Main` when we specifically need the UI/main thread.
- Choose `Async` when any worker thread is acceptable and the scheduler owns execution.
- Choose `Background` when we want main-thread callers to hop to async but non-main callers to stay inline.
- Choose mailbox delivery when the receiver owns its own thread affinity and is prepared to pump that mailbox itself.

Mailbox API mapping:

| Need | EventNexus mailbox API |
|---|---|
| Typed receiver-owned delivery | `SubscribeIn<T>(aMailbox, ...)` |
| Exact named receiver-owned delivery | `SubscribeNamedIn(aName, aMailbox, ...)` |
| Named typed receiver-owned delivery | `SubscribeNamedOfIn<T>(aName, aMailbox, ...)` |
| GUID typed receiver-owned delivery | `SubscribeGuidOfIn<T>(aMailbox, ...)` |

Mailbox migration rules:

- Create `TmaxMailbox` on the receiver thread and keep pumping it from that same thread.
- Mailbox overflow is receiver-local final handoff policy on `TmaxMailboxPolicy`; it is not inherited from topic `SetPolicy*` or `maxSetQueuePreset*`.
- Mailbox coalescing is a receiver-side option on payload-carrying mailbox subscriptions and is separate from topic-level coalescing.
- `Clear` purges bus-owned queued mailbox work, while mailbox policy and mailbox ownership remain intact.
- `Close(True)` rejects future enqueue and discards pending mailbox items; `Close(False)` preserves pending items but still rejects future enqueue.
- The current implementation is portable-only; no specialized mailbox implementation is enabled today because benchmark evidence has not justified it.

Recommended samples:

- `samples/MailboxWorkerSample.dpr` for the basic worker-loop pattern.
- `samples/MailboxWorkerIntegrationSample.dpr` for the realistic worker/control/progress pattern where one side owns a mailbox for commands and the caller owns another mailbox for progress/results.
- `samples/MailboxTopicFamiliesSample.dpr` for the full mailbox subscribe family.
- `samples/MailboxClearShutdownSample.dpr` for `Clear`, `Close(True)`, and `Close(False)`.
- `samples/MailboxLatestWinsSample.dpr` and `samples/MailboxOverflowSample.dpr` for queue-shaping behavior.

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
