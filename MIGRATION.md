# EventNexus Migration Guide

This guide helps transition existing iPub Messaging or NX Horizon code to EventNexus.

## From iPub Messaging

| iPub concept | EventNexus equivalent |
|--------------|----------------------|
| `Post(name, payload)` | `PostNamedOf<T>(name, payload)` |
| `Post(interface)` | `PostGuidOf<T>(payload)` |
| `Post(type)` | `Post<T>(payload)` |
| `Subscribe(name, handler)` | `SubscribeNamed(name, handler)` |
| `Subscribe(type, handler)` | `Subscribe<T>(handler)` |
| Attributes for auto-wiring | `MLSubscribeAttribute` with `AutoSubscribe`/`AutoUnsubscribe` |

## From NX Horizon

| NX Horizon concept | EventNexus equivalent |
|--------------------|----------------------|
| `Publish<T>` / `Subscribe<T>` | `Post<T>` / `Subscribe<T>` |
| Delivery modes (Immediate/Main/Background) | `Posting`, `Main`, `Async`, `Background` |
| Sticky events | `EnableSticky<T>(True)` or `EnableStickyNamed` |
| Queue throttling | `TMLQueuePolicy` via `SetPolicyFor` or `SetPolicyNamed` |

EventNexus keeps manual registration APIs available across compilers while offering optional Delphi attributes for convenience.
