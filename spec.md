# EventNexus — MaxLogic Event Bus Specification (spec-bus.md)

**Status:** Draft v0.2 • **Targets:** Delphi 12+ (Win/OSX/iOS/Android) and FPC 3.2.2 (Win/Linux/macOS) • **Priority:** Performance, correctness, portability

> This document specifies the API, semantics, threading model, and performance constraints for the new MaxLogic Event Bus ("maxBus"). It intentionally **does not** provide a drop‑in reimplementation of third‑party code. Design is inspired by concepts from iPub Messaging and NX Horizon, but the API and behavior are our own.

---

## 1. Goals & Non‑Goals

### 1.1 Goals

* Decouple publishers and subscribers via a high‑performance, type‑safe pub/sub bus.
* Support **sync** and **async** delivery, including **main‑thread marshaling**.
* Be **thread‑safe** end‑to‑end.
* Zero/low allocation hot paths; avoid RTTI in steady‑state.
* Portable across Delphi 12+ and **FPC 3.2.2**.
* Integrate with **MaxLogicFoundation/maxAsync.pas** for scheduling and main‑thread marshaling.
* Simple, discoverable API favoring the iPub usage style.
* **Sticky** (latest event cache) and **Coalescing** (burst reduction) are **first‑class required features**.
* Built‑in **Diagnostics** (counters + lightweight timing) from day one.

### 1.2 Non‑Goals

* No reliance on Delphi Attributes where they break FPC portability.
* No global hidden magic; explicit registration APIs must exist for all features.
* No dependency on Embarcadero `System.Messaging`.

---

## 2. Terminology

* **Event**: a record or interface/class instance representing a message payload.
* **Topic**: an identifier used to route events. Can be a **type**, a **GUID**, or a **string** name.
* **Subscriber**: a method callback or procedure reference receiving events.
* **Delivery Mode**: execution context for handlers: `Posting`, `Main`, `Async`, `Background`.
* **Bus**: the dispatcher instance (`ImaxBus`) coordinating subscriptions and posts.

---

## 3. Platform & Compiler Support

### 3.1 Conditional Compilation

Use the following feature flags:

```pascal
{$IFDEF FPC}
  {$MODE DELPHI}
  {$DEFINE max_FPC}
{$ELSE}
  {$DEFINE max_DELPHI}
{$ENDIF}

{$IFDEF MSWINDOWS} {$DEFINE max_HAS_MAINTHREAD} {$ENDIF}
{$IFDEF MACOS}     {$DEFINE max_HAS_MAINTHREAD} {$ENDIF}
{$IFDEF ANDROID}   {$DEFINE max_HAS_MAINTHREAD} {$ENDIF}
{$IFDEF IOS}       {$DEFINE max_HAS_MAINTHREAD} {$ENDIF}
```

### 3.2 Language Features

* **Attributes**: available on Delphi; *not portable* to FPC 3.2.2. Provide attribute‑based opt‑in on Delphi, but keep full manual registration APIs available on both compilers.
* **Anonymous methods**: Delphi supports `reference to procedure`; FPC 3.2.2 requires nested procedures / procedural variables. **We provide overloads** so both compilers build from the same source.

#### 3.2.1 Cross‑compiler handler types

```pascal
{$IFDEF max_FPC}
  type TmaxProc = procedure;                 // nested allowed
  type TmaxProcOf<T> = procedure(const aValue: T);
{$ELSE}
  type TmaxProc = reference to procedure;    // Delphi anonymous method
  type TmaxProcOf<T> = reference to procedure(const aValue: T);
{$ENDIF}
```

When targeting FPC, samples using anonymous methods translate to nested procedures:

```pascal
{$IFDEF max_FPC}
var lSub: ImaxSubscription;
procedure HandleOrder(const aEvt: TOrderPlaced);
begin
  // handle
end;
begin
  lSub := maxBus.Subscribe<TOrderPlaced>(@HandleOrder, Posting);
end;
{$ENDIF}
```

### 3.3 Implementation Plan

* Use `lib/MaxLogicFoundation/maxlogic.fpc.compatibility.pas` for cross‑compiler `TProc` and `TMonitor` types; all queue and wait logic routes through this layer so FPC and Delphi share semantics.
* Replace generic interface methods with a `PTypeInfo`‑driven core. Generic wrappers call into this core, mirroring the typed dispatch style from `reference/NX.Horizon.pas` and avoiding Delphi's “E2535 Interface methods must not have parameterized methods”.
* Swap Delphi‑only RTTI helpers (`TRttiMethod.IsGeneric`, `MakeGenericMethod`) for simple `PTypeInfo` enumeration inspired by `reference/iPub.Rtl.Messaging.pas`.
* Replace `GetTickCount64`/`QWord` timing with `TStopwatch` from `lib/MaxLogicFoundation/maxlogic.fpc.diagnostics.pas` and `UInt64` counters.
* Implement case‑insensitive topic lookup via `SysUtils.CompareText` or a delegated comparer rather than `TStringComparer.OrdinalIgnoreCase`.
* Hide `TThread.Queue/Synchronize` differences behind `ImaxAsync` so dispatching code is compiler‑agnostic.
* **Weak‑target shim**: Delphi uses `System.WeakReference.TWeakReference<TObject>` for method targets; FPC uses a `{Ptr, Gen}` registry. Both paths share the same dispatch‑time “rehydrate‑or‑skip” logic.

---

## 4. Threading Model & maxAsync Integration

### 4.1 Abstraction

`maxAsync.pas` supplies scheduling and main‑thread marshaling. The bus depends on an abstraction (to avoid hard‑wiring):

```pascal
type
  ImaxAsync = interface
    ['{02AB5A8B-8A3F-4F29-9C1E-1A31B8E7B6A9}']
    procedure RunAsync(const aProc: TProc);
    procedure RunOnMain(const aProc: TProc);
    procedure RunDelayed(const aProc: TProc; aDelayUs: Integer);
    function  IsMainThread: Boolean;
  end;
```

**Requirement:** Provide a default adapter `TmaxNexusAsync` that wraps maxAsync. On FPC, supply platform equivalents (e.g., `TThread.Queue/Synchronize` on Lazarus, or custom main‑loop dispatcher).

### 4.2 Delivery Modes

* `Posting`: invoke in the caller thread.
* `Main`: marshal to main/UI thread via `ImaxAsync.RunOnMain`.
* `Async`: dispatch on a worker (thread‑pool) via `ImaxAsync.RunAsync`.
* Coalescing delays schedule via `ImaxAsync.RunDelayed` to avoid blocking sleeps.
* `Background`: if caller is main thread, use `RunAsync`; else invoke inline.

**Note:** Delivery ordering per subscriber is preserved **per topic**; cross‑topic ordering is not guaranteed.

---

## 5. Public API (high‑level)

### 5.1 Core Types

```pascal
type
  TmaxDelivery = (Posting, Main, Async, Background);

  ImaxSubscription = interface
    ['{79C1B0D9-6A9E-4C6B-8E96-88A84E4F1E03}']
    procedure Unsubscribe;
    function  IsActive: Boolean;
  end;

  ImaxBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    // Type‑routed events (by compile‑time type)
    function Subscribe<T>(const aHandler: TProc<T>; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure Post<T>(const aEvent: T);

    // Named topics (case‑insensitive)
    function SubscribeNamed(const aName: string; const aHandler: TProc; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure PostNamed(const aName: string); // fire‑and‑forget

    // Named + payload
    function SubscribeNamedOf<T>(const aName: string; const aHandler: TProc<T>; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure PostNamedOf<T>(const aName: string; const aEvent: T);

    // GUID‑keyed topics (typically for interface types)
    function SubscribeGuidOf<T: IInterface>(const aHandler: TProc<T>; aMode: TmaxDelivery = Posting): ImaxSubscription; // key = T.GUID
    procedure PostGuidOf<T: IInterface>(const aEvent: T);

    // Maintenance
    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear; // remove all listeners (admin/testing)
  end;
```

> **Token semantics:** `ImaxSubscription` is a disposable *token*. Releasing the last reference (letting the interface go out of scope or assigning it to `nil`) automatically calls `Unsubscribe` (idempotent). This is the recommended pattern over calling `Unsubscribe` directly.


> **Rationale:**
>
> * Mirrors the *usability* of iPub (named topics, GUID routing for interfaces) while embracing NX‑style **type‑based** topics.
> * Uniform `TProc<T>`/`TProc` handlers support methods, anonymous methods, and stand‑alone procedures. FPC compatibility is achieved with overloaded procedural types when needed.

### 5.2 Default Instance

```pascal
function maxBus: ImaxBus; // Unit: maxLogic.EventNexus // thread‑safe singleton factory
```

### 5.3 Attribute (Delphi‑only, optional)

```pascal
{$IFDEF max_DELPHI}
  maxSubscribeAttribute = class(TCustomAttribute)
  public
    Name: string;               // empty for type/GUID subscription
    Delivery: TmaxDelivery;
    constructor Create(aDelivery: TmaxDelivery); overload;
    constructor Create(const aName: string; aDelivery: TmaxDelivery = Posting); overload;
  end;

  procedure AutoSubscribe(const aInstance: TObject); // scans public+protected by explicit RTTI
  procedure AutoUnsubscribe(const aInstance: TObject);
{$ENDIF}
```

**Note:** The attribute API is sugar over explicit `Subscribe*` calls and must not be required for correctness.

---

## 6. Semantics

1. **Handler lifetime**

   * Returned `ImaxSubscription` is reference‑counted; releasing it auto‑unsubscribes.
   * **Object-method liveness:** For object‑method handlers, the bus stores `{CodePtr, WeakTarget}` and reconstructs the method pointer at dispatch time.
     - **Delphi 12+**: `WeakTarget` = `System.WeakReference.TWeakReference<TObject>`. On invoke, `TryGetTarget` must succeed; otherwise the call is skipped and the subscription is **pruned lazily**.
     - **FPC 3.2.2**: `WeakTarget` = lightweight registry (pointer → generation). On object finalization, the instance’s generation increments. On invoke, if `{Ptr, GenAtSubscribe}` ≠ current generation, skip and **prune lazily**.
   * **Already‑queued work:** Events queued *before* `Unsubscribe` or token release may still reach the dispatcher. The liveness check above guarantees such invocations are **no‑ops** if the target is dead; otherwise they proceed.

2. **Reentrancy**

   * Posting into the same topic from within a handler is allowed. To avoid unbounded recursion, the bus processes posts FIFO per topic.

3. **Ordering**

   * **Per‑subscriber, per‑topic** ordering is preserved.
   * Cross‑subscriber ordering is unspecified. An optional `Priority` extension may be added later.

4. **Error handling**

   * Exceptions in handlers are **captured** and aggregated into an `EmaxDispatchError` containing per‑handler errors. Sync paths re‑raise after dispatch; async paths forward errors to a global error hook:

   ```pascal
   type
     TOnAsyncError = reference to procedure(const aTopic: string; const aE: Exception);
   procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
   ```

5. **Back‑pressure**

   * The bus is not a queueing system. If producers outrun consumers in `Async/Main` modes, tasks may accumulate. Implementers **must** batch or coalesce where callers opt‑in (see §8.4 Sticky/Coalesce).

---

## 7. Performance Requirements

* **Subscribe/Unsubscribe**: O(1) average; avoid global locks—use striped locks or lock‑free lists per topic.
* **Post (no subscribers)**: sub‑microsecond on desktop; minimal branch path.
* **Post (N subscribers)**: linear in N with minimal per‑subscriber overhead (< 50 ns per invocation on x64 desktop target, excluding callback cost).
* **Allocations**: zero allocations on `Post` hot path; pre‑allocate handler nodes from a pool.
* **Contention**: no global critical section around `Post`.

Benchmark scaffolding will be specified separately; CI gates should assert envelopes on Windows x64 and Linux x64.

---

## 8. Feature Set

### 8.1 Topics & Keys

* **Type‑keyed** topics: `Subscribe<T>/Post<T>`; works for records, classes, interfaces.
* **GUID‑keyed** topics: `SubscribeGuidOf<T: IInterface>` uses `T.GUID` as a key.
* **Named** topics: `SubscribeNamed` / `SubscribeNamedOf<T>`; names are **case‑insensitive**.

### 8.2 Delivery Modes

Exactly as in §4.2. A subscriber’s chosen delivery applies to posts for that subscription regardless of the publisher’s thread.

### 8.3 Manual Method Subscription (runtime‑computed names)

Allow dynamic names such as `product_105346_changed`. See API in §5.1 (`SubscribeNamedOf`).

### 8.4 Sticky & Coalescing (**required**)

* **Sticky**: latest event per (topic\[, name]) cached; late subscribers receive it immediately on subscribe (delivery honors the subscriber’s mode).
* **Coalesce**: for rapid bursts, a per‑topic coalescer reduces traffic by delivering only the latest per **coalesce key** during an active window.

```pascal
type
  ImaxBusAdvanced = interface(ImaxBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableSticky<T>(aEnable: Boolean);
    procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
    procedure EnableCoalesceOf<T>(const aKeyOf: TFunc<T,string>; aWindowUs: Integer = 0);
    procedure EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TFunc<T,string>; aWindowUs: Integer = 0);
  end;
```

*`aWindowUs=0` means coalesce within a single dispatch cycle; `>0` uses a time window. Values <1000 µs or negative are treated as 0. Coalesced dispatch must be scheduled via `ImaxAsync.RunDelayed` rather than blocking sleeps.*

### 8.5 Main‑Thread Assurance

When `Main` delivery is requested on platforms without a GUI main thread, `Main` == `Posting`.

### 8.6 Cancellation

`ImaxSubscription.Unsubscribe` is idempotent and thread‑safe. Cancelling during dispatch skips remaining invocations for that handler.


> **Queued work:** Items enqueued prior to `Unsubscribe`/token release may still be dequeued; dispatch applies the **weak‑target liveness** check from §6, so dead targets are skipped. Implementations should **prune** dead subscriptions on first observed liveness failure to keep copy‑on‑write arrays compact.

### 8.7 Back‑Pressure & Bounded Queues (**required, with defaults**)

**Problem:** In `Async/Main` modes, producers can outpace executors leading to unbounded task growth.

**Policy abstraction:** Each topic can declare a **Queue Policy**:

```pascal
type
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);

  TmaxQueuePolicy = record
    MaxDepth: Integer;        // 0 = unbounded (default for generic topics)
    Overflow: TmaxOverflow;    // behavior when queue is full
    DeadlineUs: Int64;        // used when Overflow=Deadline; 0 = immediate drop
  end;

  ImaxBusQueues = interface
    ['{E55F7B60-9B31-4C80-9B2C-8D1F0E26FF9C}']
    procedure SetPolicyFor<T>(const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    function  GetPolicyFor<T>: TmaxQueuePolicy;
  end;
```

**Default policies (may be overridden):**

* **State topics** (UI state, sensor snapshots): `MaxDepth=256`, `Overflow=DropOldest`.
* **Action topics** (commands, audits): `MaxDepth=1024`, `Overflow=Deadline`, `DeadlineUs=2000`.
* **Control‑plane / critical topics** (shutdown, failover): `MaxDepth=1`, `Overflow=Block`.
* **Unspecified topics**: `MaxDepth=0` (unbounded) + **warning** in metrics when depth > 10k.

**API additions:**

```pascal
function TryPost<T>(const aEvent: T): Boolean; overload;
function TryPostNamed(const aName: string): Boolean; overload;
function TryPostNamedOf<T>(const aName: string; const aEvent: T): Boolean; overload;
```

Return `False` when dropped by policy.

**Rationale:** Bounded policies keep memory predictable and let callers choose semantics per topic.

### 8.8 Unit & Naming

**Primary unit name:** `maxLogic.EventNexus.pas`. Public entry point `maxBus` lives here for both Delphi and FPC.

**Rationale:** Bounded policies keep memory predictable and let callers choose semantics per topic.

`ImaxSubscription.Unsubscribe` is idempotent and thread‑safe. Cancelling during dispatch skips remaining invocations for that handler.

---

## 9. Usage Examples

### 9.1 Type‑based, record payload

```pascal
type
  TOrderPlaced = record
    Id: Int64;
  end;

var
  lSub: ImaxSubscription;
begin
  lSub := maxBus.Subscribe<TOrderPlaced>(
    procedure (const aEvt: TOrderPlaced)
    begin
      // handle
    end,
    Main);

  maxBus.Post<TOrderPlaced>(TOrderPlaced.Create(42));
end;
```

### 9.2 Interface payload keyed by GUID

```pascal
type
  ILogOutMessage = interface
    ['{CA101646-B801-433D-B31A-ADF7F31AC59E}']
  end;

begin
  maxBus.SubscribeGuidOf<ILogOutMessage>(
    procedure (const aMsg: ILogOutMessage)
    begin
      // react
    end,
    Async);

  maxBus.PostGuidOf<ILogOutMessage>(TLogOutMessage.Create);
end;
```

### 9.3 Named topic + payload

```pascal
maxBus.SubscribeNamedOf<string>('product_105346_changed',
  procedure (const aSku: string)
  begin
    // update UI
  end,
  Posting);

maxBus.PostNamedOf<string>('product_105346_changed', '105346');
```

### 9.4 Attribute sugar (Delphi‑only)

```pascal
{$IFDEF max_DELPHI}
  {$RTTI EXPLICIT METHODS([vcProtected, vcPublic, vcPublished])}
  TForm1 = class(TForm)
  public
    [maxSubscribe(Main)]
    procedure OnLogout(const aMsg: ILogOutMessage);
  end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  AutoSubscribe(Self);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  AutoUnsubscribe(Self);
end;
{$ENDIF}
```

---

## 10. Concurrency & Memory Model

* **Data Races**: The bus’s internal structures are protected by fine‑grained locks (per‑topic). Reader‑heavy paths use atomic snapshots + hazard pointers or versioned arrays to avoid long locks during `Post`.
* **Handler Node Pool**: Lock‑free freelist per topic to recycle nodes.
* **Weak Targets**: For method handlers, store `{TargetPtr(weak), CodePtr}`.
  - **Delphi 12+**: use `System.WeakReference.TWeakReference<TObject>`; invoke only if `TryGetTarget` succeeds.
  - **FPC 3.2.2**: use a registry + generation counter to detect finalized instances; invoke only if generation matches.
  No try/except probing on the hot path.

---

## 11. Error Semantics

* Sync dispatch (`Posting`, non‑main) collects handler errors and raises
  `EmaxAggregateException` with all inner exceptions after all handlers run.
* `Main/Async` errors are forwarded to the global async hook. Implementers must not swallow exceptions silently.
* Add diagnostic counters: posts, deliveries, exceptions, queue depth (if any). Each handler exception increments `ExceptionsTotal`.

---

## 11.1 Diagnostics & Metrics

Provide a minimal, zero‑GC metrics façade always available; reading is lock‑free (snapshot copy):

```pascal
type
  TmaxTopicStats = record
    PostsTotal: UInt64;
    DeliveredTotal: UInt64;
    DroppedTotal: UInt64;         // due to overflow policy
    ExceptionsTotal: UInt64;
    MaxQueueDepth: UInt32;
    CurrentQueueDepth: UInt32;
  end;

  ImaxBusMetrics = interface
    ['{2C4B91E3-1C0A-4B5C-B8B0-0C1A5C3E6D10}']
    function GetStatsFor<T>: TmaxTopicStats;
    function GetStatsNamed(const aName: string): TmaxTopicStats;
    function GetTotals: TmaxTopicStats; // aggregate across all topics
  end;
```

**Optional hooks:**

```pascal
type
  TOnMetricSample = reference to procedure(const aName: string; const aStats: TmaxTopicStats);
procedure maxSetMetricCallback(const aSampler: TOnMetricSample); // sampling is caller-driven
```

**Note:** The metrics API must be available and cheap even when unused; no background timers.

---

## 11.2 Optimization Guidelines (**new**)

This section lists **implementation** and **usage** optimizations to keep EventNexus lightning‑fast on Delphi/FPC:

**Memory & allocations**

* Use a **per‑topic slab allocator / freelist** for subscription nodes and queued items to keep `Post` allocation‑free in the common case. Prefer bulk allocate+recycle patterns over `GetMem/FreeMem`.
* Consider **FastMM5** as the default memory manager on Windows (commercial license may apply). It shows measurable MT scaling over FastMM4; profile under your workload. citeturn0search4turn0search14turn0search19

**Queues & rings**

* For hot topics, a **ring buffer** with sequence counters can reduce contention and branch mispredictions vs. naive linked queues. Study modern Disruptor design ideas (sequences, barriers) before adopting. citeturn0search5
* Prefer **SPSC/MPSC specializations** when topology allows; generic MPMC queues have higher overhead. Reference proven designs to validate trade‑offs. citeturn0search2turn0search7

**False sharing & cache friendliness**

* **Pad and align** frequently updated counters (e.g., queue head/tail, metrics) to avoid **false sharing** between producers/consumers. Keep write‑heavy fields on separate cache lines from read‑mostly fields. citeturn0search11turn0search6turn0search1
* Favor **struct‑of‑arrays** for hot fields accessed independently across threads.

**Atomics & reclamation**

* Minimize `Interlocked*` ops in the hot path; batch where possible (e.g., bulk dequeue). If using lock‑free structures, adopt a safe reclamation scheme like **Hazard Pointers** for removed nodes. citeturn0search3turn0search18turn0search13

**Dispatch**

* Inline small shims; avoid RTTI during steady‑state dispatch. Pre‑bind method pointers (TargetPtr, CodePtr) and validate liveness cheaply.
* Prefer **flat arrays** of handlers per topic; copy‑on‑write a new array on subscribe/unsubscribe to keep posting lock‑free (readers use snapshot versioning).

**Coalescing & batching**

* Coalesce bursts for state topics and offer **bulk delivery** to handlers that opt‑in (e.g., `TProc<TArray<T>>`) to amortize overhead.

**Main‑thread hops**

* Minimize `Main` marshaling; batch UI notifications and throttle to frame‑rate.

**Diagnostics**

* Counters must be **per‑CPU or sharded** then aggregated to avoid write contention on a single global counter.

**Build & compiler**

* For FPC use `-O3 -OoREGVAR -CpCOREAVX2` (where supported); for Delphi enable inlining (`$INLINE`) and turn off debug RTTI in release.

These guidelines are advisory; validate with microbenchmarks that mirror your real workloads.

---

## 12. API Surface — Complete (initial)

```pascal
type
  TmaxString = type UnicodeString;

{$IFDEF max_FPC}
  TmaxProc      = procedure;                  // nested procvars
  TmaxProcOf<T> = procedure(const aValue: T);
{$ELSE}
  TmaxProc      = reference to procedure;     // anonymous methods
  TmaxProcOf<T> = reference to procedure(const aValue: T);
{$ENDIF}

  TmaxDelivery = (Posting, Main, Async, Background);
  TmaxOverflow = (DropNewest, DropOldest, Block, Deadline);

  ImaxSubscription = interface
    ['{79C1B0D9-6A9E-4C6B-8E96-88A84E4F1E03}']
    procedure Unsubscribe;
    function  IsActive: Boolean;
  end;

  ImaxBus = interface
    ['{1B8E6C9E-5F96-4F0C-9F88-0B7B8E885D4A}']
    function Subscribe<T>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure Post<T>(const aEvent: T);
    function TryPost<T>(const aEvent: T): Boolean; overload;

    function SubscribeNamed(const aName: TmaxString; const aHandler: TmaxProc; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure PostNamed(const aName: TmaxString);
    function TryPostNamed(const aName: TmaxString): Boolean; overload;

    function SubscribeNamedOf<T>(const aName: TmaxString; const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure PostNamedOf<T>(const aName: TmaxString; const aEvent: T);
    function TryPostNamedOf<T>(const aName: TmaxString; const aEvent: T): Boolean; overload;

    function SubscribeGuidOf<T: IInterface>(const aHandler: TmaxProcOf<T>; aMode: TmaxDelivery = Posting): ImaxSubscription;
    procedure PostGuidOf<T: IInterface>(const aEvent: T);

    procedure UnsubscribeAllFor(const aTarget: TObject);
    procedure Clear;
  end;

  // Advanced controls (sticky/coalesce/queues)
  ImaxBusAdvanced = interface(ImaxBus)
    ['{AB5E6E6D-8B1F-4B63-8B59-8A3B9D8C71B1}']
    procedure EnableSticky<T>(aEnable: Boolean);
    procedure EnableStickyNamed(const aName: string; aEnable: Boolean);
    procedure EnableCoalesceOf<T>(const aKeyOf: TFunc<T,string>; aWindowUs: Integer = 0);
    procedure EnableCoalesceNamedOf<T>(const aName: string; const aKeyOf: TFunc<T,string>; aWindowUs: Integer = 0);
  end;

  // Queue policy control
  TmaxQueuePolicy = record
    MaxDepth: Integer;
    Overflow: TmaxOverflow;
    DeadlineUs: Int64;
  end;

  ImaxBusQueues = interface
    ['{E55F7B60-9B31-4C80-9B2C-8D1F0E26FF9C}']
    procedure SetPolicyFor<T>(const aPolicy: TmaxQueuePolicy);
    procedure SetPolicyNamed(const aName: string; const aPolicy: TmaxQueuePolicy);
    function  GetPolicyFor<T>: TmaxQueuePolicy;
  end;

  // Metrics
  TmaxTopicStats = record
    PostsTotal: UInt64;
    DeliveredTotal: UInt64;
    DroppedTotal: UInt64;
    ExceptionsTotal: UInt64;
    MaxQueueDepth: UInt32;
    CurrentQueueDepth: UInt32;
  end;

  ImaxBusMetrics = interface
    ['{2C4B91E3-1C0A-4B5C-B8B0-0C1A5C3E6D10}']
    function GetStatsFor<T>: TmaxTopicStats;
    function GetStatsNamed(const aName: string): TmaxTopicStats;
    function GetTotals: TmaxTopicStats;
  end;

function maxBus: ImaxBus; // thread-safe singleton factory

// Optional hooks
type
  TOnAsyncError = reference to procedure(const aTopic: string; const aE: Exception);
  TOnMetricSample = reference to procedure(const aName: string; const aStats: TmaxTopicStats);

procedure maxSetAsyncErrorHandler(const aHandler: TOnAsyncError);
procedure maxSetMetricCallback(const aSampler: TOnMetricSample);
```

**FPC Notes:** Where anonymous methods are not supported, the implementation will provide overloads taking procvars/nested procedures and will avoid Delphi‑only units or attributes in core paths.

---

## 13. Interop & Migration

* From iPub: map `Post(name, payload)` → `PostNamedOf<T>`; `Post(interface)` → `PostGuidOf<T>`; attribute usage → `maxSubscribe` (Delphi only). Case‑insensitive names retained. fileciteturn2file0L60-L92
* From NX Horizon: `Publish<T>`/`Subscribe<T>` features and delivery modes available; type‑categorized events are first class. citeturn0search1

---

## 14. Security & Safety

* Avoid executing untrusted code on main thread by default; keep `Posting` as default delivery.
* Do not log payload contents in production (PII risk). Provide pluggable logger.

---

## 15. Testing Matrix

* **Compilers**: Delphi 12 Win64, Win32; FPC 3.2.2 Win64/Linux64.
* **Scenarios**: subscribe/unsubscribe churn; burst posting; cross‑thread posting; main‑thread marshaling; exception aggregation; object lifetime auto‑cleanup; stress with 1M posts; **queue overflow policies**; **sticky/coalesce correctness**; metrics accuracy.


* **Token auto‑unsubscribe**: dropping the last `ISubscription` reference cancels the subscription; verify no residual deliveries.
* **Queued‑prior‑to‑cancel**: ensure queued tasks observe the liveness check; dead targets are skipped and the subscription is pruned.
* **ABA guard**: allocate/free/allocate at same address; verify generation/weak ref prevents delivery to a different object.

---

## 16. Final Review & Proposed Extensions (**curated**)

**Ready for v1**

* Cross‑compiler API (Delphi 12+, FPC 3.2.2) with handler overloads.
* Required **Sticky/Coalesce** with per‑topic configuration.
* **Queue Policies** with sane defaults and `TryPost*`.
* **Metrics** façade and async error hook.

**Proposed v1.1+ extensions**

1. **Priority subscriptions:** optional `Priority: SmallInt` per handler; stable order within same priority.
2. **Bulk dispatch API:** allow subscribers to receive `TArray<T>` batches for bursty topics.
3. **Topic groups & wildcard names:** `orders.*` to subscribe to many named topics with a single registration (watch cost on Post path).
4. **Tracing hooks:** OpenTelemetry‑style callbacks with sampler; correlation IDs passed via context.
5. **Serializer plug‑in:** optional serializer for cross‑process transports (not in‑process); e.g., to bridge to IPC.
6. **Disruptor‑style sequences (advanced):** for ultra‑hot topics, offer an alternative **sequence/ring** channel with strict SPSC/MPSC topology and back‑pressure via capacity; keep the generic API unchanged. citeturn0search5

**Risks & mitigations**

* Overuse of `Block` overflow can deadlock UI threads → recommend `PostBlocking` only in worker contexts; CI test to detect blocking on main thread.
* Memory pressure with unbounded topics → metrics warn at thresholds, doc recommends defaults in §8.7.

---

## 17. Distinctiveness & IP Note

This spec defines **original** names, interfaces, and behaviors. It does not replicate third‑party source code. Any similarities are conceptual and common to pub/sub systems.
& IP Note
This spec defines **original** names, interfaces, and behaviors. It does not replicate third‑party source code. Any similarities are conceptual and common to pub/sub systems.


## 18. references

see:
  - ./lib/maxEventNexus/reference/iPub.README.md
  - ./lib/maxEventNexus/reference/iPub.Rtl.Messaging.pas
  - ./lib/maxEventNexus/reference/NX.Horizon.pas

---

# References

`./reference/weak-references-with-mormot2.md ` - about weak references using mormot2
`./reference/weak-references.md` - about delphi weak / unsafe references
