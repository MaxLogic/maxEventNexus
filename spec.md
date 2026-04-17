# EventNexus Specification

**Status:** Draft (contract-aligned with current runtime)
**Target:** Delphi 12+
**Priorities:** correctness, predictable concurrency, low-allocation posting path

This spec defines the EventNexus public contract as implemented in this repository.

## 1. Goals and non-goals

### 1.1 Goals

- Provide a type-safe pub/sub event bus with typed, named, and GUID topic models.
- Keep posting path free from global bus lock contention.
- Provide delivery-mode control (`Posting`, `Main`, `Async`, `Background`).
- Support sticky latest-value caching and coalescing for burst reduction.
- Provide queue back-pressure controls and topic metrics.
- Keep tests executable from CLI with DUnitX.

### 1.2 Non-goals

- No generic methods on interfaces (Delphi `E2535` limitation still applies).
- No hard dependency on UI frameworks in core runtime.
- No transport/IPC concerns in the core in-process bus.

## 2. Public API model

## 2.1 Interface layer

- `ImaxBus`:
  - `SubscribeNamed`, `PostNamed`, `TryPostNamed`, `PostDelayedNamed`, `UnsubscribeAllFor`, `Clear`
- `ImaxBusAdvanced`:
  - `EnableStickyNamed`
- `ImaxBusQueues`:
  - `SetPolicyNamed`, `GetPolicyNamed`
- `ImaxBusMetrics`:
  - `GetStatsNamed`, `GetTotals`

These interfaces are intentionally non-generic.

## 2.2 Generic layer

Generic APIs live on `TmaxBus` (class).

Examples:

- `Subscribe<T>`, `Post<T>`, `TryPost<T>`
- `SubscribeStrong<T>` when caller-owned lifetime is acceptable
- `SubscribeNamedOf<T>`, `PostNamedOf<T>`, `TryPostNamedOf<T>`
- `SubscribeNamedOfStrong<T>` when caller-owned lifetime is acceptable
- `SubscribeIn<T>`, `SubscribeNamedIn`, `SubscribeNamedOfIn<T>`, `SubscribeGuidOfIn<T: IInterface>` for receiver-owned mailbox delivery
- `SubscribeGuidOf<T: IInterface>`, `PostGuidOf<T>`, `TryPostGuidOf<T>`
- `SubscribeGuidOfStrong<T>` when caller-owned lifetime is acceptable
- `PostResult<T>`, `PostResultNamed`, `PostResultNamedOf<T>`, `PostResultGuidOf<T>`
- `PostMany<T>`, `PostManyNamedOf<T>`, `PostManyGuidOf<T>`
- `PostDelayed<T>`, `PostDelayedNamed`, `PostDelayedNamedOf<T>`, `PostDelayedGuidOf<T>`
- `SubscribeNamedWildcard('prefix*' | '*', ...)`
- `EnableSticky<T>`, `EnableCoalesceOf<T>`, `EnableCoalesceNamedOf<T>`, `EnableCoalesceGuidOf<T>`
- `SetPolicyFor<T>`, `SetPolicyGuidOf<T>`, `GetPolicyFor<T>`, `GetPolicyGuidOf<T>`
- `GetStatsFor<T>`, `GetStatsGuidOf<T>`

Bridge from interface to class:

```pascal
var
  lBus: TmaxBus;
begin
  lBus := maxBusObj;
end;
```

## 2.3 Subscription lifetime

`Subscribe*` returns `ImaxSubscription`.

- `Unsubscribe` is idempotent.
- Releasing the last interface reference auto-unsubscribes.
- `UnsubscribeAllFor` removes subscriptions owned by the specified target object.
- Object-method `Subscribe<T>` / `SubscribeNamedOf<T>` / `SubscribeGuidOf<T>` use weak-target liveness by default.
- `SubscribeStrong<T>` / `SubscribeNamedOfStrong<T>` / `SubscribeGuidOfStrong<T>` intentionally opt out of weak-target liveness checks; callers must keep the subscriber alive until unsubscribe/release.

## 2.4 Attribute-based auto-subscribe (Delphi)

`AutoSubscribe`/`AutoUnsubscribe` are Delphi helpers built on `maxSubscribeAttribute`.

- `[maxSubscribe]` (typed): method must be an instance procedure with exactly one value/const parameter.
- `[maxSubscribe('topic')]` (named): method must be an instance procedure with zero or one value/const parameter.
- Unsupported signatures raise `EmaxInvalidSubscription` (e.g., class methods, constructors/destructors, `var/out` params, abstract methods, multiple attributes on one method).
- `AutoSubscribe` rebinds an instance by auto-unsubscribing previously remembered auto-subscriptions for that instance first.

## 2.5 Clear contract

`Clear` is a runtime state reset, not a configuration wipe.

- Removes all current subscriptions (including tracked auto-subscriptions).
- Resets topic runtime state: queued work, sticky cache values, coalesce pending state, counters, and high-water warning state.
- Preserves durable topic configuration and reapplies it after reset:
  - sticky enablement,
  - explicit per-topic queue policy,
  - queue-preset intent,
  - configured coalescing selector/window state.
- Preserves scheduler and bus main-thread identity.
- Pre-clear subscription handles must become inert and must never affect post-clear subscriptions.

## 3. Threading and scheduling

Scheduler abstraction:

```pascal
type
  IEventNexusScheduler = interface
    procedure RunAsync(const aProc: TmaxProc);
    procedure RunOnMain(const aProc: TmaxProc);
    procedure RunDelayed(const aProc: TmaxProc; aDelayUs: Integer);
    function IsMainThread: Boolean;
  end;
```

Shipped adapters:

- `maxLogic.EventNexus.Threading.RawThread`
- `maxLogic.EventNexus.Threading.MaxAsync`
- `maxLogic.EventNexus.Threading.TTask`

Runtime injection:

```pascal
maxSetAsyncScheduler(CreateMaxAsyncScheduler);
```

Delay timing contract:

- `aDelayUs` is a configuration unit, not a guarantee of exact microsecond wake-up precision on Delphi/Windows backends.
- Negative delays clamp to `0`.
- `0` means "eligible immediately".
- Any positive `aDelayUs` must remain delayed, even if an adapter rounds up to the nearest supported timer resolution.
- The shipped `maxAsync` adapter preserves async/delayed semantics on primary-backend submission failure by falling back to dedicated-thread execution; inline execution is a final safety net only if even thread creation fails.

### 3.1 Mailbox delivery

EventNexus also supports receiver-affine delivery through a cooperative mailbox owned by one thread.

Public mailbox contract:

```pascal
const
  cMaxWaitInfinite = High(Cardinal);

type
  ImaxMailbox = interface
    function IsCurrent: Boolean;
    function Describe: string;
    function TryPost(const aProc: TmaxProc): Boolean;
    function PumpOne(aTimeoutMs: Cardinal = cMaxWaitInfinite): Boolean;
    function PumpAll(aMaxItems: Integer = MaxInt): Integer;
    function PendingCount: Integer;
    procedure Close(aDiscardPending: Boolean = True);
    function IsClosed: Boolean;
  end;

  TmaxMailboxPolicy = record
    MaxDepth: Integer;
    Overflow: TmaxMailboxOverflow;
    DeadlineUs: Int64;
  end;
```

`TmaxMailbox` remains the default portable implementation and adds class-only configuration:

```pascal
constructor Create; overload;
constructor Create(const aPolicy: TmaxMailboxPolicy); overload;
```

Typed mailbox-bound subscribe is additive on `TmaxBus`:

```pascal
function SubscribeIn<T>(const aMailbox: ImaxMailbox;
  const aHandler: TmaxProcOf<T>): ImaxSubscription;

function SubscribeNamedIn(const aName: TmaxString;
  const aMailbox: ImaxMailbox; const aHandler: TmaxProc): ImaxSubscription;

function SubscribeNamedOfIn<T>(const aName: TmaxString;
  const aMailbox: ImaxMailbox; const aHandler: TmaxProcOf<T>): ImaxSubscription;

function SubscribeGuidOfIn<T: IInterface>(const aMailbox: ImaxMailbox;
  const aHandler: TmaxProcOf<T>): ImaxSubscription;
```

Mailbox contract:

- Each mailbox has one owner thread captured at creation time.
- `PumpOne` and `PumpAll` are owner-thread operations. Pumping from any other thread must fail fast.
- `TryPost` never waits for the receiver to handle the item after admission. Under mailbox `Block` or `Deadline` overflow modes it may still wait for pending capacity to become available before admission succeeds or fails.
- Mailbox pumping is cooperative. EventNexus does not inject work into a foreign thread automatically.
- The default mailbox queue is FIFO and unbounded unless an explicit mailbox-owned policy is configured.
- The default mailbox implementation must stay cross-platform within Delphi-supported desktop targets and must not depend on Windows messages.
- Mailbox capacity is mailbox-wide and shared by direct mailbox `TryPost` calls plus mailbox-bound EventNexus delivery. It is not per-topic and not per-subscription.

Supported owner-thread pumping patterns:

- Blocking worker loop: `Mailbox.PumpOne(cMaxWaitInfinite)`
- Timed cooperative loop: `Mailbox.PumpOne(100)`
- Manual integration loop: `Mailbox.PumpAll`

### 3.2 Mailbox lifecycle and `Clear`

Mailbox delivery extends the existing hard-reset model.

- `Unsubscribe` marks the subscription inactive.
- Already-queued mailbox work for an unsubscribed subscription must be skipped when pumped.
- `Clear` removes current subscriptions and purges queued mailbox work belonging to that bus before returning.
- Pre-clear subscription handles must become inert and must never affect post-clear subscriptions.
- Already-dequeued mailbox work may still finish if it crossed the dequeue boundary before the `Clear` purge started.
- `Close(aDiscardPending = True)` prevents future enqueue, discards queued-but-not-dequeued mailbox items, wakes waiting pump loops, and still allows already-dequeued work to finish.
- `IsClosed` reports whether the mailbox has crossed that close boundary.
- Mailbox-owned overflow policy is durable mailbox configuration and is not reset by `Clear`.

The mailbox roadmap is staged:

- current slice: `ImaxMailbox`, typed `SubscribeIn<T>`, exact named `SubscribeNamedIn`, named typed `SubscribeNamedOfIn<T>`, GUID typed `SubscribeGuidOfIn<T>`, mailbox-level coalescing for payload-carrying mailbox-bound subscriptions, mailbox-owned overflow policy, owner-thread pumping, `Clear` purge, and close semantics
- later slices: benchmark-guided specialization and any later direct-mailbox helper APIs that prove necessary
- current status: no specialized mailbox implementation ships today; the portable mailbox remains the only maintained implementation until benchmark thresholds justify an opt-in platform-specific variant

## 4. Delivery semantics

- `Posting`: inline execution.
- `Main`: execute on main thread if available.
- `Async`: execute on scheduler async path.
- `Background`: execute async only when caller is main thread; otherwise inline.

### 4.1 Main-thread policy in console/service contexts

When `Main` delivery cannot marshal to UI loop:

- `Strict`: raise `EmaxMainThreadRequired`.
- `DegradeToAsync`: route to `RunAsync`.
- `DegradeToPosting`: run inline.

Configuration:

```pascal
maxSetMainThreadPolicy(TmaxMainThreadPolicy.DegradeToPosting);
```

### 4.2 Post and TryPost contract

- `Post*` follows normal dispatch semantics and may raise `EmaxDispatchError` on synchronous aggregate failures.
- `TryPost*` is non-raising for queue admission failure paths and returns:
  - `False` when topic admission is rejected, or when mailbox handoff is attempted during the posting call and every effective receiver rejects before the call returns.
  - `True` when admission succeeds or when the call is a no-op because a topic is not instantiated and not configured sticky.
- `TryPost*` can still raise for synchronous handler failures on accepted posting paths (same aggregate semantics as `Post*`).
- Mailbox-owned overflow is receiver-local. It is not silently inherited from topic queue policy or queue presets.
- If mailbox handoff is attempted during the posting call and every effective receiver rejects before the call returns, `TryPost*` returns `False`.
- Once a post has been accepted onto a later async/deferred topic path, later mailbox overflow for one receiver does not retroactively change the original `TryPost*` result.

### 4.3 PostResult contract

`PostResult*` APIs are additive status-returning variants:

- `NoTopic`: no matching topic instance exists and no sticky/wildcard config causes implicit creation.
- `Dropped`: topic admission was rejected, or mailbox handoff was attempted during the posting call and every effective receiver rejected before the call returned.
- `Coalesced`: event accepted on a coalescing path.
- `Queued`: accepted while topic processing was already active or because delivery was handed off to a receiver-owned mailbox.
- `DispatchedInline`: accepted and not queued/coalesced.

`PostResult*` preserves normal exception behavior: synchronous aggregate failures still raise `EmaxDispatchError`.

Mailbox-aware reporting limits:

- `PostResult*` is a post-time summary, not a per-receiver acknowledgement.
- Mailbox-owned overflow may reject one receiver while another receiver still accepts the same post.
- If mailbox handoff is attempted during the posting call and every effective receiver rejects before the call returns, `PostResult*` returns `Dropped`.
- If the post is accepted onto a later async/deferred topic path, later mailbox overflow does not retroactively change the already-returned `PostResult*`. Those later drops are observed through normal drop metrics or future receiver-specific diagnostics, not through a rewritten post result.

### 4.4 Bulk post contract

`PostMany*` APIs (`typed`, `named-of`, `guid-of`) post items in input order and preserve per-topic ordering.

- They keep single-item dispatch semantics per element.
- If multiple elements fail with `EmaxDispatchError`, failures are merged and raised once after the batch.

### 4.5 Delayed post contract

Delayed APIs (`PostDelayed*`) schedule a normal `Post*` operation after a delay (milliseconds).

- Return type: `ImaxDelayedPost` (`Cancel`, `IsPending`).
- `Cancel` is idempotent and only succeeds while the post is still pending.
- Delayed posts are dropped by `Clear` if they were scheduled before the clear boundary.
- After the delay expires, routing and subscriber delivery-mode selection follow the same rules as immediate `Post*`.
- Delayed-post failures are async-path failures: they are surfaced only through `maxSetAsyncErrorHandler` when an async error handler is installed.
- `PostDelayed*` does not synchronously re-raise a later delayed execution failure back to the original caller.

## 5. Topic families and routing

- Typed topics use `PTypeInfo` key.
- Named topics use case-insensitive string key.
- GUID topics use `TGuid` key.

Topic registries are protected by per-family locks. Posting does not take one global bus lock.

Named wildcard subscriptions:

- Pattern grammar: `*` (match all) or `prefix*` (case-insensitive prefix match).
- Only one trailing `*` is supported.
- Dispatch precedence for a named post:
  - exact named subscribers first,
  - then wildcard subscribers ordered by longer prefix first,
  - ties by earlier subscription token.
- Wildcard subscriptions fully participate in `ImaxSubscription` lifecycle (`Unsubscribe`, auto-unsubscribe on interface release, inert after `Clear`).

## 6. Subscriber storage and weak-target behavior

- Per-topic subscribers are stored in copy-on-write arrays.
- Dispatch reads snapshots, while subscribe/unsubscribe replace arrays.
- Object-method subscriptions track weak target liveness using pointer+generation metadata.
- Strong subscription variants intentionally skip weak-target liveness checks and are for callers that own subscriber lifetime explicitly.
- Stale/dead targets are skipped during dispatch and pruned lazily.

## 7. Sticky and coalescing

### 7.1 Sticky

- If enabled, topic caches latest payload/state.
- Late subscribers receive cached value according to their delivery mode.

### 7.2 Topic-level coalescing

- Optional key selector picks coalesce key per event.
- Pending dictionary keeps latest value per key.
- Flushing uses scheduler `RunDelayed` (`aWindowUs`), not blocking sleeps.
- Negative coalesce window values are clamped to `0`.
- Zero coalesce windows still stay on the delayed path and must not collapse into an inline flush before the current posting burst returns. Implementations may request the smallest positive scheduler delay needed to preserve that boundary.
- Positive coalesce windows must stay delayed; adapters may round up to the nearest supported timer resolution instead of promising exact microsecond wake-up precision.
- Coalesced flush runs on scheduler-delayed path; `Post*`/`TryPost*` do not synchronously raise coalesced handler exceptions.
- If scheduler delayed submission fails, implementation executes scheduled flush work inline as a progress fallback.
- Topic-level coalescing happens before receiver routing and may report `PostResult* = Coalesced`.

### 7.3 Mailbox-level coalescing

Mailbox-level coalescing is a separate receiver-side layer.

- Mailbox-level coalescing happens after topic routing, inside one receiver mailbox, and never changes the existing topic-level coalescing contract.
- The public trigger is additive overloads on payload-carrying mailbox-bound subscribe APIs, not a direct mailbox API in this phase.

Overload shape:

```pascal
function SubscribeIn<T>(const aMailbox: ImaxMailbox;
  const aHandler: TmaxProcOf<T>;
  const aMailboxCoalesceKeyOf: TmaxKeyFunc<T>): ImaxSubscription; overload;

function SubscribeNamedOfIn<T>(const aName: TmaxString;
  const aMailbox: ImaxMailbox; const aHandler: TmaxProcOf<T>;
  const aMailboxCoalesceKeyOf: TmaxKeyFunc<T>): ImaxSubscription; overload;

function SubscribeGuidOfIn<T: IInterface>(const aMailbox: ImaxMailbox;
  const aHandler: TmaxProcOf<T>;
  const aMailboxCoalesceKeyOf: TmaxKeyFunc<T>): ImaxSubscription; overload;
```

Contract:

- Without a mailbox coalescing selector, mailbox delivery remains strict FIFO.
- The mailbox coalescing key type is `TmaxString` and uses ordinal string equality.
- An empty mailbox coalescing key is valid and means one shared latest-pending bucket for that mailbox-bound subscription.
- Mailbox-level coalescing scope is per mailbox-bound subscription, not cross-subscription even when multiple subscriptions share one mailbox.
- The effective replacement identity is one stable receiver-subscription discriminator plus the mailbox coalescing key.
- If a matching pending item already exists for that receiver-subscription identity, the newer item replaces the pending item while keeping the original queue position.
- At most one pending item exists per receiver-subscription identity plus mailbox coalescing key.
- Only pending mailbox work can be replaced. Already-dequeued work is in-flight and is never rewritten.
- The dequeue boundary is the pending-to-in-flight transition for mailbox-level coalescing.
- If the previous item for a key is already in-flight, the next post creates a new pending item for that key.
- Replacing a pending item does not move unrelated queued work and therefore preserves FIFO order for unrelated keys.

Interaction with existing behavior:

- Topic-level coalescing may still collapse events before mailbox enqueue. Mailbox-level coalescing may then replace already-routed pending mailbox work for one receiver.
- Topic-level `PostResult* = Coalesced` remains unchanged. Accepted mailbox enqueue, including mailbox-level replacement, remains `Queued`.
- `Unsubscribe` makes queued mailbox work inert. Mailbox coalescing index entries for that work may be cleaned lazily when the queued item is dequeued or purged.
- `Clear` must purge queued mailbox work and mailbox coalescing index state owned by that bus before returning.
- `Close(True)` discards pending mailbox items and mailbox coalescing index state together.
- `Close(False)` preserves queued mailbox items and their mailbox coalescing index state, but future enqueue and future replacement attempts must still fail because the mailbox is closed.
- Direct mailbox `TryPostCoalesced(...)` is intentionally out of scope for this phase and may be considered later if we find a real non-bus use case.

## 8. Queue policy and back-pressure

Queue policy:

```pascal
type
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);

  TmaxQueuePolicy = record
    MaxDepth: Integer;
    Overflow: TmaxOverflow;
    DeadlineUs: Int64;
  end;
```

- `MaxDepth = 0` means unbounded.
- `DeadlineUs` is used by `Deadline` mode.

### 8.1 Queue preset categories (default strategy)

Preset values are provided by `TmaxBus.PolicyForPreset`:

| Preset | MaxDepth | Overflow | DeadlineUs | Intended use |
|---|---:|---|---:|---|
| `State` | 256 | `DropOldest` | 0 | state snapshots where latest wins |
| `Action` | 1024 | `Deadline` | 2000 | bursty action streams |
| `ControlPlane` | 1 | `Block` | 0 | strict control messages |
| `Unspecified` | 0 | `DropNewest` | 0 | default fallback |

Configuration hooks:

- `maxSetQueuePresetForType(TypeInfo(...), Preset)`
- `maxSetQueuePresetNamed('...', Preset)`
- `maxSetQueuePresetGuid(Guid, Preset)`

Override rules:

- Explicit per-topic `SetPolicy*` always wins.
- `PostNamedOf<T>` topics resolve implicit queue policy in this order: explicit `SetPolicyNamed(aName, ...)` policy, then `maxSetQueuePresetNamed(aName, ...)`, then `maxSetQueuePresetForType(TypeInfo(T), ...)`, then `Unspecified`.
- Preset applies only when topic policy is not explicit.
- Preset updates re-apply to already-created topics only if those topics still use implicit policy, including existing `PostNamedOf<T>` topics still inheriting name/type presets.

### 8.2 Mailbox-owned capacity and overflow

Mailbox capacity is a separate receiver-owned control plane.

- Mailbox-owned policy is configured on the mailbox itself and is not silently inherited from topic queue policy, topic queue presets, or delivery mode.
- The default mailbox policy remains unbounded so existing code keeps current behavior until a mailbox is configured explicitly.
- `TmaxMailboxPolicy` intentionally mirrors the topic overflow vocabulary through `TmaxMailboxOverflow` / `DeadlineUs` so topic and mailbox overflow names stay aligned, but the two policies remain independent.

Policy shape:

```pascal
type
  TmaxMailboxPolicy = record
    MaxDepth: Integer;
    Overflow: TmaxMailboxOverflow;
    DeadlineUs: Int64;
  end;
```

Contract:

- `MaxDepth = 0` means unbounded pending capacity.
- Capacity counts pending queue entries only. Already-dequeued in-flight mailbox work does not consume pending capacity.
- Mailbox-level coalescing replacement does not consume a new queue slot. Replacing an existing pending item must still succeed when the mailbox is full, but never after the mailbox has been closed.
- `Close(False)` preserves already-pending entries and their mailbox coalescing index state, but future enqueue and future replacement still fail because the mailbox is closed.
- `Clear` does not reset mailbox policy. `Clear` only purges bus-owned queued mailbox work for that bus.
- Direct mailbox posts and mailbox-bound EventNexus delivery share the same mailbox capacity.

Overflow modes:

- `MailboxDropNewest`: reject the new pending item immediately.
- `MailboxDropOldest`: evict the oldest pending mailbox entry, remove any mailbox coalescing index state attached to that entry, then admit the new item.
- `MailboxBlock`: wait until pending capacity becomes available or the mailbox closes.
- `MailboxDeadline`: wait until pending capacity becomes available, the deadline expires, or the mailbox closes.

Direct `ImaxMailbox.TryPost` semantics:

- `TryPost` returns `True` when the item is admitted into the mailbox queue.
- `TryPost` returns `False` when `aProc` is unassigned, when the mailbox is closed, when `MailboxDropNewest` rejects, or when `MailboxDeadline` expires before capacity becomes available.
- Under `MailboxDropOldest`, `TryPost` returns `True` for the newly admitted item even though an older pending item was discarded.
- Under `MailboxBlock` or `MailboxDeadline`, `TryPost` may wait on the calling thread. Callers are responsible for avoiding self-deadlock if the mailbox owner thread is also the only thread that can pump the mailbox.
- `Close(True)` / `Close(False)` wake blocked posters so they do not wait forever on a terminal mailbox.

Mailbox-bound EventNexus delivery semantics:

- Topic policy decides whether a post reaches dispatch. Mailbox policy decides whether one mailbox-bound receiver admits the already-routed work.
- Temporary mailbox overflow is not receiver death and must never auto-unsubscribe the mailbox-bound subscription.
- Closed mailbox rejection is terminal receiver shutdown. EventNexus may lazily retire that mailbox-bound subscription after detecting the closed-mailbox rejection.
- Mailbox rejection drops delivery for that receiver only. The same post may still be accepted by other subscribers or other mailboxes.
- Topic drop metrics must count mailbox-bound delivery rejection because the routed delivery failed to enter the receiver mailbox.

### 8.3 High-water warning integration

Queue depth warning state is tracked in topic metrics for **unbounded queues only** (`MaxDepth = 0`):

- warning enters at depth `> 10000`
- warning resets at depth `<= 5000`

State transitions trigger metric sampling path, so monitoring can detect both rise and recovery.

## 9. Metrics and diagnostics

Per-topic stats (`TmaxTopicStats`):

- `PostsTotal`
- `DeliveredTotal`
- `DroppedTotal`
- `ExceptionsTotal`
- `MaxQueueDepth`
- `CurrentQueueDepth`

API:

- `GetStatsNamed`
- `GetStatsFor<T>` / `GetStatsGuidOf<T>` (class path)
- `GetTotals`

Callback hooks:

- `maxSetMetricCallback`
- `maxSetMetricSampleInterval`
- `maxSetDispatchTrace`

Dispatch trace emits opt-in events:

- `TraceEnqueue`
- `TraceInvokeStart`
- `TraceInvokeEnd`
- `TraceInvokeError`

Trace payload includes topic, delivery mode, duration (`InvokeEnd`/`InvokeError`), and error class/message for error events.

Trace event semantics:

- `TraceEnqueue` is a topic-queue event. It means a post entered or activated the topic's internal processing/queue path.
- `TraceEnqueue.Delivery` is topic-level queue semantics and is not a per-subscriber delivery-mode report. Current runtime uses `Posting` for this topic-gate signal.
- `TraceInvokeStart`, `TraceInvokeEnd`, and `TraceInvokeError` are per-invocation events. Their `Delivery` field is the subscriber delivery mode actually used for that invocation.

## 10. Error behavior

- Synchronous posting paths aggregate handler exceptions and raise `EmaxDispatchError`.
- `EmaxDispatchError.Details` carries structured metadata per failure:
  - exception class/message,
  - topic metric key,
  - delivery mode,
  - subscriber token,
  - subscriber kind (`Unknown`, `Exact`, `Wildcard`),
  - subscriber index.
- `SubscriberIndex` is zero-based within the reported `SubscriberKind` when a specific subscriber is known.
- Wildcard subscriber failures must report `SubscriberKind = Wildcard`; they must not rely on negative `SubscriberIndex` sentinel values.
- Coalesced delivery exceptions are treated as async-path failures and are forwarded to the async error hook when configured.
- Async/main/background/delayed delivery paths forward errors to global async hook when set.
- When no async error hook is installed, delayed-path failures are swallowed after the delayed execution path; they do not travel back to the original `PostDelayed*` caller.

Hook installation:

```pascal
maxSetAsyncErrorHandler(
  procedure(const aTopic: string; const aE: Exception)
  begin
    // integration hook
  end);
```

## 11. Performance constraints

- No global bus lock around `Post`.
- Keep steady-state posting path allocation-light.
- Keep per-topic ordering guarantees while allowing concurrency across unrelated topics.

## 12. Testing contract (DUnitX)

Active harness is DUnitX.

Baseline commands:

- `./build-tests.sh`
- `./build-and-run-tests.sh`
- optional direct execution: `tests/MaxEventNexusTests.exe`

Test sources live in `tests/src`.

Benchmark contract is maintained by `bench/SchedulerCompare.dpr` with CSV/percentile schema documented in `docs/benchmarks/benchmark-output-contract.md`.

## 13. Documentation contract

`README.md`, `DESIGN.md`, `MIGRATION.md`, sample docs, and test docs must reflect the current Delphi-only runtime and DUnitX harness.

When runtime behavior changes, update docs and changelog in the same change.

## 14. Extension status

Maintainer request on **2026-02-24** unfroze the first five extension items; all five are now implemented:

1. Posting outcome result API (`PostResult*`).
2. Dispatch tracing hooks (`maxSetDispatchTrace` + trace event record).
3. Bulk dispatch API (`PostMany*`).
4. Named-topic wildcard subscriptions (`SubscribeNamedWildcard`).
5. Richer dispatch error metadata (`EmaxDispatchError.Details`).

Dropped from current roadmap:

6. Disruptor-style specialized sequences (reactivate only via a new ADR with clear benchmark justification).
