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
- `SubscribeStrong*` variants intentionally bypass this weak-target path for callers that own subscriber lifetime explicitly.

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

## Dispatch tracing

`maxSetDispatchTrace` exposes two different trace granularities:

- `TraceEnqueue` is topic-level. It signals that a post entered or activated the topic's internal queue/direct-dispatch gate.
- `TraceInvokeStart`, `TraceInvokeEnd`, and `TraceInvokeError` are subscriber-invocation-level traces.

That means `TmaxDispatchTrace.Delivery` is intentionally interpreted differently by trace kind:

- for `TraceEnqueue`, it reflects topic-queue semantics and is currently emitted as `Posting`,
- for `TraceInvoke*`, it reflects the subscriber delivery mode that `Dispatch` used (`Posting`, `Main`, `Async`, `Background`).

## Main-thread policy in console contexts

When `Main` delivery is requested but no UI main-thread marshaling is available (`IsConsole`):

- `Strict`: raise `EmaxMainThreadRequired`.
- `DegradeToAsync`: reroute to async scheduler.
- `DegradeToPosting`: run inline.

Global configuration is set via `maxSetMainThreadPolicy`.

## Scheduler adapters

The shipped scheduler adapters are intentionally different:

- `MaxAsync` is the recommended default and may fall back to dedicated-thread execution if its primary backend rejects work.
- `RawThread` bypasses the Delphi thread pool and creates a dedicated `TThread` for each async or delayed work item.
- `TTask` is the explicit RTL thread-pool adapter.

## Mailbox delivery model

Receiver-affine delivery is handled through a mailbox owned by exactly one thread.

- The receiver thread creates an `ImaxMailbox`.
- The receiver subscribes through `TmaxBus.SubscribeIn<T>(...)`.
- A post from another thread does not execute the handler directly on that posting thread.
- EventNexus enqueues a bus-owned work item into the receiver mailbox.
- The receiver thread pumps the mailbox and executes the handler on itself.

The mailbox contract is cooperative by design.

- `PumpOne` and `PumpAll` are owner-thread operations and must fail fast on the wrong thread.
- `TryPost(const aProc: TmaxProc)` is the direct mailbox enqueue primitive used both by demos and by bus integration.
- The baseline mailbox is FIFO and unbounded.
- The portable baseline uses RTL synchronization primitives and stays cross-platform across Delphi-supported desktop targets.

This is intentionally different from `Main`/`Async`/`Background` delivery:

- scheduler delivery selects a runtime queue owned by the scheduler
- mailbox delivery selects a queue owned by the receiver itself

## Sticky cache and coalescing

Sticky:

- Topic stores last payload/state.
- Late subscribers are fed cached value according to subscriber delivery mode.

Topic-level coalescing:

- Optional key selector maps event to coalesce key.
- Pending dictionary stores latest event per key.
- Flush is scheduled by scheduler (`RunDelayed`) to avoid blocking waits.
- Scheduler delay requests are best-effort; positive sub-millisecond values may round up to backend timer resolution, but they must not collapse into immediate execution.

Mailbox-level coalescing:

- Mailbox-level coalescing is a separate receiver-side layer that runs after topic routing.
- The trigger is planned as additive mailbox-bound subscribe overloads with a mailbox coalescing selector, not a direct mailbox API in this phase.
- The effective mailbox coalescing identity is `(subscription token, mailbox coalescing key)`, so two subscriptions sharing one mailbox do not collapse each other accidentally.
- The mailbox coalescing key uses `TmaxString` ordinal equality; an empty key is valid and means one latest-pending bucket for that subscription.
- Queue plus side index remains the preferred runtime shape: queue owns order, side index finds the current pending node for a mailbox coalescing identity.
- Replacing a pending mailbox item keeps its queue slot instead of moving it to the tail, so unrelated keys keep FIFO order.
- The dequeue boundary is the pending-to-in-flight transition. In-flight mailbox work is never rewritten.
- Topic-level coalescing and mailbox-level coalescing may both be enabled: topic-level collapse happens before routing, mailbox-level collapse happens after routing inside one receiver mailbox.

## Clear reset model

`Clear` is treated as a runtime-state reset.

- It removes live subscriptions plus queued or pending runtime work.
- It drops sticky cached values, pending coalesce buckets, and delayed posts created before the clear boundary.
- It preserves durable configuration: sticky enablement, explicit queue policy, queue presets, coalescing selectors/windows, and scheduler/main-thread identity.
- For mailbox-bound subscriptions, it must also purge queued mailbox work owned by the bus before returning.
- Already-dequeued mailbox work may still finish, but queued mailbox work must not survive the clear boundary.

Mailbox lifecycle rules:

- `Unsubscribe` makes queued mailbox work inert at pump time.
- Mailbox-level coalescing index entries for an unsubscribed receiver must be removed together with queued work for that receiver.
- `Close(aDiscardPending = True)` discards queued mailbox items, wakes waiters, and rejects future enqueue.
- `Close(False)` keeps pending mailbox items and mailbox-level coalescing index state intact, but future enqueue or replacement still fails because the mailbox is closed.
- `IsClosed` reports that close boundary.
- Future roadmap items are mailbox-level coalescing implementation, mailbox-owned overflow policy, and any later direct-mailbox coalescing helper if a real use case appears.

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
