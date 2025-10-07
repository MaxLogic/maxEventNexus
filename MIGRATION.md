# EventNexus Migration Guide


## 2025-10-06 — Tokens & Weak-Target Liveness

**Summary**
- Introduced `ISubscription` tokens returned by all `Subscribe*` APIs. Releasing the last reference auto-unsubscribes (idempotent). `Unsubscribe` remains available.
- Added dispatch-time **weak-target liveness** for object-method handlers:
  - **Delphi 12+**: `System.WeakReference.TWeakReference<TObject>` guards the target; invoke only if `TryGetTarget` succeeds.
  - **FPC 3.2.2**: lightweight `(Ptr → Generation)` registry; invoke only if generation matches.
- Queued-before-cancel behavior clarified: already-enqueued items rely on liveness check; dead targets are skipped; subscriptions are pruned lazily.

**Required actions for integrators**
- Prefer storing the returned `ISubscription` in a field; assign it to `nil` in the destructor to auto-unsubscribe.
- If you previously relied on manual `Unsubscribe` only, your code continues to work. Tokens are the recommended pattern.
- No public API signature changes; behavior is safer by default. If you used reflection to access internal handler storage, note that handler records now contain `{CodePtr, WeakTarget}` instead of `{CodePtr, DataPtr}`.

**Notes**
- No dependency on mORMot2; Delphi uses RTL `System.WeakReference`, FPC uses built-in shim.
- See `DESIGN.md` and `spec.md` for architectural details and testing matrix additions.

This guide helps transition existing iPub Messaging or NX Horizon code to EventNexus.

## From iPub Messaging

| iPub concept | EventNexus equivalent |
|--------------|----------------------|
| `Post(name, payload)` | `PostNamedOf<T>(name, payload)` |
| `Post(interface)` | `PostGuidOf<T>(payload)` |
| `Post(type)` | `Post<T>(payload)` |
| `Subscribe(name, handler)` | `SubscribeNamed(name, handler)` |
| `Subscribe(type, handler)` | `Subscribe<T>(handler)` |
| Attributes for auto-wiring | `maxSubscribeAttribute` with `AutoSubscribe`/`AutoUnsubscribe` |

## From NX Horizon

| NX Horizon concept | EventNexus equivalent |
|--------------------|----------------------|
| `Publish<T>` / `Subscribe<T>` | `Post<T>` / `Subscribe<T>` |
| Delivery modes (Immediate/Main/Background) | `Posting`, `Main`, `Async`, `Background` |
| Sticky events | `EnableSticky<T>(True)` or `EnableStickyNamed` |
| Queue throttling | `TmaxQueuePolicy` via `SetPolicyFor` or `SetPolicyNamed` |

EventNexus keeps manual registration APIs available across compilers while offering optional Delphi attributes for convenience.