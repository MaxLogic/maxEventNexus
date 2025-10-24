# EventNexus Architecture

This document outlines the internal architecture of the MaxLogic Event Bus. It complements `spec.md` and focuses on the moving parts and their relationships.

## Topics
* **Typed** topics keyed by generic type `T`.
* **Named** topics keyed by case-insensitive `string`.
* **GUID** topics keyed by `TGuid`.
All topic lookups are stored in dictionaries mapping the topic identifier to subscriber lists.

## Subscriber Storage
* Each topic keeps a **copy-on-write (COW)** array of handlers to preserve ordering during mutation and enable lock-free iteration during dispatch.
* Handlers are stored as records containing the callback `CodePtr`, a **weak target** reference, the delivery mode, and flags required by sticky/coalesce features.

## Subscriptions & Tokens
* `Subscribe*` returns an **ISubscription token**. Releasing the last interface reference automatically **unsubscribes** (idempotent). `Unsubscribe` remains available for explicit teardown.
* Tokens internally track `Active` (atomic bool) and an **in-flight counter** so `Cancel` can be implemented as: mark inactive → remove from the topic list (copy-on-write) → optionally wait for in-flight invokes to finish (policy-dependent).

## Weak-Target Liveness (Delphi/FPC)
* For **object-method** handlers, each entry stores `{CodePtr, WeakTarget}` and reconstructs the `TMethod` on dispatch.
  * **Delphi 12+**: `WeakTarget = System.WeakReference.TWeakReference<TObject>`. Invoke only if `TryGetTarget` succeeds.
  * **FPC 3.2.2**: `WeakTarget` is a lightweight registry `(Ptr → Generation)`. On finalization, the generation increments. Invoke only if `{Ptr, GenAtSubscribe} == CurrentGen`.
* **Rationale**: protects against forgotten unsubscribe, async races, and ABA reuse. **No try/except probes** on the hot path.
* **Pruning**: when a dead target is detected, the subscription is marked and **pruned lazily** on the next mutation/sweep to keep COW arrays compact.

## Dispatch Path
1. **Post** looks up the topic and snapshots the **copy-on-write** handler array.
2. For each handler:
   * Skip if `Active=false`.
   * Rehydrate `WeakTarget`; if missing/stale → mark for prune and continue.
   * Increment **in-flight**; invoke according to **Delivery**:
     * `Posting`: same thread.
    * `Main`: marshal via `IEventNexusScheduler.RunOnMain`.
     * `Async` / `Background`: enqueue on the configured executor.
   * Decrement **in-flight** after completion.
3. **Queued-before-cancel** items: if a handler was enqueued before its token was released, the **liveness check** ensures it becomes a **no-op** once the target dies or the subscription is canceled.

## Subscriber Storage (details)
* Per-topic **copy-on-write array** of handler records to minimize contention and preserve per-subscriber order.
* Handler record fields: `CodePtr`, `WeakTarget`, `Delivery`, `Flags(Sticky, CoalesceKeyPresent)`, and links to per-topic state when needed.
* Copy-on-write happens only on structural changes (subscribe/unsubscribe/prune); dispatch is lock-free on the array snapshot.

## Queues (executors)
* `Main`/`Async`/`Background` marshal through the `IEventNexusScheduler` abstraction so Delphi/FPC differences are isolated.
* Queue policy (`TmaxQueuePolicy`) defines max depth, overflow behavior and optional deadlines. Drops are recorded in metrics.

## Sticky Cache & Coalescer
* **Sticky**: optional last-value cache per topic; late subscribers get the cached event immediately.
* **Coalesce**: optional per-topic key function; pending item replaced by the latest with the same key; zero-window coalescing defers dispatch until the posting cycle completes.

## Cancellation & Races
* `Unsubscribe` and token release are **idempotent** and thread-safe.
* In-flight coordination uses an atomic counter or `TCountdownEvent` to ensure `Cancel` can choose to wait/non-wait (implementation policy).
* No global bus lock is required; per-topic operations use COW arrays and versioned lists.
* Dead/canceled handlers are **pruned lazily**; maintenance occurs on the next write or via a periodic sweep.

## Metrics & Diagnostics
* Per-topic counters: posts, deliveries, drops, exceptions, peak depth, prunes.
* Async error hook reports exceptions from background deliveries along with the topic identifier.

## Compatibility Notes
* **iPub** and **NX.Horizon** rely on manual unsubscribe; EventNexus adds a **weak-target guard** and **token auto-unsubscribe** for safety-by-default while keeping method-handler ergonomics.
