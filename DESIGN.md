# EventNexus Architecture

This document explains how EventNexus is assembled internally and how the runtime pieces interact.

## Topic model

EventNexus supports three topic families:

- Typed topics keyed by `PTypeInfo` (`Subscribe<T>`, `Post<T>` on `TmaxBus`).
- Named topics keyed by `string` (`SubscribeNamed`, `PostNamed` on `ImaxBus`).
- GUID topics keyed by `TGuid` (`SubscribeGuidOf<T>`, `PostGuidOf<T>` on `TmaxBus`).

Each family has its own dictionary and lock, so unrelated topic families do not serialize through one global bus lock.

## API surface split (Delphi constraint)

Delphi blocks generic methods on interfaces (`E2535`), so we intentionally split public API:

- Interfaces (`ImaxBus`, `ImaxBusAdvanced`, `ImaxBusQueues`, `ImaxBusMetrics`) expose non-generic named operations.
- Class `TmaxBus` exposes generic typed/named/GUID operations.
- `maxBusObj(...)` is the bridge from interface references to class generic methods.

## Subscriber storage

Each concrete topic (`TTypedTopic<T>`, `TNamedTopic`) stores subscribers in copy-on-write arrays.

- Subscribe/unsubscribe creates a new array snapshot.
- Dispatch reads a stable snapshot.
- Weak-target liveness checks prune dead entries lazily.

This keeps mutation cost predictable and keeps dispatch iteration simple.

## Weak-target liveness

For object-method subscriptions we capture a weak target token (pointer + generation).

- Object destruction increments generation via the weak registry hook.
- Dispatch compares stored generation vs current generation.
- Mismatch means stale target; invocation is skipped and subscription is pruned.

This avoids AV-probing as a liveness strategy.

## Dispatch and locking

`TmaxBus.Dispatch` routes by `TmaxDelivery`:

- `Posting`: immediate call.
- `Main`: marshal to scheduler main queue when available.
- `Async`: scheduler async queue.
- `Background`: async from main thread; inline from worker threads.

`Post` no longer takes a global bus lock.

- Topic lookup uses per-family locks (`fTypedLock`, `fNamedLock`, `fNamedTypedLock`, `fGuidLock`).
- Per-topic queueing/processing is synchronized inside `TmaxTopicBase`.
- Metrics index updates are copy-on-write and protected by a dedicated metrics lock.

## Main-thread policy in console contexts

When `Main` delivery is requested but no UI main-thread marshaling is available (`IsConsole`):

- `Strict`: raise `EmaxMainThreadRequired`.
- `DegradeToAsync`: reroute to async scheduler.
- `DegradeToPosting`: run inline.

Global configuration is set via `maxSetMainThreadPolicy`.

## Sticky cache and coalescing

Sticky:

- Topic stores last payload/state.
- Late subscribers are fed cached value according to subscriber delivery mode.

Coalescing:

- Optional key selector maps event to coalesce key.
- Pending dictionary stores latest event per key.
- Flush is scheduled by scheduler (`RunDelayed`) to avoid blocking waits.

## Queue policy and presets

Every topic has `TmaxQueuePolicy`:

- `MaxDepth` (0 means unbounded).
- `Overflow` strategy (`DropNewest`, `DropOldest`, `Block`, `Deadline`).
- `DeadlineUs` for `Deadline` mode.

Presets are configured globally by topic category (`State`, `Action`, `ControlPlane`) and only applied when topic policy is not explicit.

## Metrics and warnings

Per-topic counters track posts, delivered, dropped, exceptions, max queue depth, and current queue depth.

High-water warning behavior:

- warning state flips on when queue depth exceeds 10_000,
- resets when queue depth drops to 5_000 or below,
- transitions trigger metric touch so external samplers can observe both warning and recovery.

`GetStats*` and `GetTotals` read topic snapshots from the metrics index.

## Testing model

The active unit-test harness is DUnitX (`tests/MaxEventNexusTests.dpr`).

- `./build-tests.sh` builds test binary.
- `./build-and-run-tests.sh` builds and runs fixture suite.
