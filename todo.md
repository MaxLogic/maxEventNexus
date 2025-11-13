# EventNexus TODO

**Status:** v0.2 implementation review (2025-01-10)  
**Current version:** v0.1.0 → targeting v1.0.0

---

## High Priority (v1.0 Blockers)

### T-1001: Implement AutoSubscribe/AutoUnsubscribe (Delphi only)
**Status:** Stub only; no RTTI scanning  
**Spec ref:** spec.md §5.3, §9.4  
**Priority:** High  
**Effort:** Medium (2-3 days)

**Current state:**
- `AutoSubscribe` and `AutoUnsubscribe` are empty stubs in `maxLogic.EventNexus.pas`
- `maxSubscribeAttribute` is defined but unused
- Sample `samples/AutoSubscribeSample.pas` exists but doesn't test actual auto-registration

**Implementation plan:**
1. In `AutoSubscribe(const aInstance: TObject)`:
   - Create `TRttiContext` and get type info for `aInstance.ClassType`
   - Enumerate methods with visibility `mvPublic`, `mvProtected`, `mvPublished`
   - For each method with `[maxSubscribe]` attribute:
     - Extract `Name` (empty → type-based) and `Delivery` from attribute
     - Validate signature: must be `procedure(const aValue: T)` or `procedure` (named-only)
     - Determine parameter type `T` from `TRttiMethod.GetParameters`
     - Call appropriate `Subscribe*` method based on `Name` and `T`
     - Store returned `ImaxSubscription` in `fAutoSubs: TmaxAutoSubDict` (keyed by `aInstance`)
2. In `AutoUnsubscribe(const aInstance: TObject)`:
   - Look up `aInstance` in `fAutoSubs`
   - Iterate stored tokens and call `Unsubscribe` on each
   - Remove entry from `fAutoSubs`
3. Add `fAutoSubs: TmaxAutoSubDict` field to `TmaxBus` (already declared in interface)
4. Initialize/free `fAutoSubs` in `TmaxBus.Create`/`Destroy`

**Edge cases:**
- Method signature mismatch → raise `EmaxInvalidSubscription` with clear message
- Inherited methods with `[maxSubscribe]` → scan base classes recursively
- Multiple attributes on same method → raise exception (ambiguous)
- `AutoSubscribe` called twice on same instance → clear old subscriptions first

**Testing:**
- Add `TTestAutoSubscribe` to `tests/src/MaxEventNexus.Main.Tests.pas`:
  - Test class with `[maxSubscribe]` on typed method → verify delivery
  - Test class with `[maxSubscribe('topic')]` on named method → verify delivery
  - Test `AutoUnsubscribe` → verify no further deliveries
  - Test invalid signature → verify exception raised
  - Test inheritance → verify base class methods registered

**Files to modify:**
- `maxLogic.EventNexus.pas`: implement `AutoSubscribe`/`AutoUnsubscribe` bodies
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestAutoSubscribe` test case
- `samples/AutoSubscribeSample.pas`: verify sample works with real implementation

---

### T-1002: Fix Async Exception Aggregation
**Status:** Partial; some async paths swallow exceptions  
**Spec ref:** spec.md §6, §11  
**Priority:** High  
**Effort:** Small (1 day)

**Current state:**
- `Dispatch` with `Async`/`Main`/`Background` wraps handler in `try..except` and calls `gAsyncError`
- `ScheduleTypedCoalesce` aggregates exceptions into `EmaxAggregateException`
- **Gap:** Non-coalesced async posts aggregate exceptions in `lErrs` but then raise `EmaxAggregateException` which is caught and swallowed by outer `try..except` in `Dispatch`

**Problem code (in `Post<T>` and similar):**
```pascal
lTopic.Enqueue(
  procedure
  var
    lErrs: TmaxExceptionList;
  begin
    // ... dispatch loop ...
    if lErrs <> nil then
      raise EmaxAggregateException.Create(lErrs); // ← raised but caught by Dispatch wrapper
  end);
```

**Fix:**
1. In all `Post*` methods, after the `Enqueue` call, check if `lErrs <> nil`
2. If yes, call `gAsyncError` for each exception in `lErrs` (or once with `EmaxAggregateException`)
3. Alternatively, pass `lErrs` out via a closure variable and handle after `Enqueue` returns

**Proposed solution:**
- Wrap the dispatch loop in a nested procedure that returns `lErrs`
- After `Enqueue`, check `lErrs` and forward to `gAsyncError`
- Ensure `Posting` mode still raises `EmaxAggregateException` (sync behavior)

**Testing:**
- Add `TTestAsyncExceptions` to `tests/src/MaxEventNexus.Main.Tests.pas`:
  - Subscribe `Async` handler that raises exception
  - Set `gAsyncError` hook to capture exceptions
  - Post event
  - Verify hook called with correct topic name and exception

**Files to modify:**
- `maxLogic.EventNexus.pas`: review all `Post*` methods; ensure async exceptions forwarded to `gAsyncError`
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestAsyncExceptions` test case

---

### T-1003: Add Main-Thread Degradation Policy
**Status:** Hardcoded degradation `Main` → `Async`  
**Spec ref:** spec.md §8.5  
**Priority:** High  
**Effort:** Small (1 day)

**Current state:**
- `Dispatch` checks `IsMainThread()`; if false and mode is `Main`, schedules via `RunAsync`
- **Issue:** In console tests (no message pump), `RunOnMain` via `TThread.Queue` may never execute
- **Workaround:** Degradation to `Async` ensures progress but violates `Main` contract

**Proposed solution:**
1. Add `TmaxMainThreadPolicy = (Strict, DegradeToAsync, DegradeToPosting)`
2. Add global `gMainThreadPolicy: TmaxMainThreadPolicy := DegradeToAsync` (default)
3. Add `procedure maxSetMainThreadPolicy(aPolicy: TmaxMainThreadPolicy)`
4. Update `Dispatch` logic:
   ```pascal
   Main:
     if IsMainThread() then
       aHandler() // inline
     else
       case gMainThreadPolicy of
         Strict: raise EmaxMainThreadRequired.Create('Main delivery requires main thread');
         DegradeToAsync: fAsync.RunAsync(aHandler);
         DegradeToPosting: aHandler(); // inline (useful for single-threaded tests)
       end;
   ```

**Testing:**
- Add `TTestMainThreadPolicy` to `tests/src/MaxEventNexus.Main.Tests.pas`:
  - Test `Strict` mode → verify exception raised when posting from worker thread
  - Test `DegradeToAsync` mode → verify delivery via async scheduler
  - Test `DegradeToPosting` mode → verify inline delivery

**Files to modify:**
- `maxLogic.EventNexus.pas`: add `TmaxMainThreadPolicy`, `gMainThreadPolicy`, `maxSetMainThreadPolicy`, update `Dispatch`
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestMainThreadPolicy` test case

---

### T-1004: Implement Metrics Throttling
**Status:** `TouchMetrics` calls callback on every update  
**Spec ref:** spec.md §11.1, §11.2  
**Priority:** High (performance)  
**Effort:** Small (1 day)

**Current state:**
- Every `AddPost`, `AddDelivered`, `AddDropped`, `AddException` calls `TouchMetrics`
- `TouchMetrics` immediately invokes `gMetricSample` callback if assigned
- **Issue:** High-frequency topics generate excessive callback overhead (can be 10k+ calls/sec)

**Proposed solution:**
1. Add `fLastMetricSample: UInt64` field to `TmaxTopicBase` (tick count)
2. Add global `gMetricSampleIntervalMs: Cardinal := 1000` (default 1 second)
3. Add `procedure maxSetMetricSampleInterval(aIntervalMs: Cardinal)`
4. Update `TouchMetrics`:
   ```pascal
   procedure TmaxTopicBase.TouchMetrics;
   var
     lNow: UInt64;
   begin
     if (fMetricName = '') or not Assigned(gMetricSample) then
       Exit;
     lNow := GetTickCount64;
     if (lNow - fLastMetricSample) >= gMetricSampleIntervalMs then
     begin
       fLastMetricSample := lNow;
       gMetricSample(UnicodeString(fMetricName), fStats);
     end;
   end;
   ```

**Alternative (per-CPU counters):**
- Use array of `TmaxTopicStats` indexed by `GetCurrentProcessorNumber mod CPU_COUNT`
- Aggregate on read (in `GetStats*` methods)
- More complex but eliminates contention entirely

**Testing:**
- Add `TTestMetricsThrottling` to `tests/src/MaxEventNexus.Main.Tests.pas`:
  - Set interval to 100ms
  - Post 10k events rapidly
  - Verify callback invoked ≤ 10 times (once per 100ms window)

**Files to modify:**
- `maxLogic.EventNexus.pas`: add throttling logic to `TouchMetrics`, add `maxSetMetricSampleInterval`
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestMetricsThrottling` test case

---

### T-1005: Fix High-Water Reset Logic
**Status:** Warning triggers but never resets  
**Spec ref:** `TmaxTopicBase.CheckHighWater` in maxLogic.EventNexus.pas  
**Priority:** Medium  
**Effort:** Trivial (30 min)

**Current state:**
- `fWarnedHighWater` set to `True` when `CurrentQueueDepth > 10000`
- Comment says "reset when depth <= 5000" but code never executes reset

**Fix:**
```pascal
procedure TmaxTopicBase.CheckHighWater;
begin
  if fPolicy.MaxDepth = 0 then
  begin
    if (not fWarnedHighWater) and (fStats.CurrentQueueDepth > 10000) then
    begin
      fWarnedHighWater := True;
      TouchMetrics;
    end
    else if fWarnedHighWater and (fStats.CurrentQueueDepth <= 5000) then
    begin
      fWarnedHighWater := False;
      TouchMetrics; // notify that warning cleared
    end;
  end;
end;
```

**Testing:**
- Add `TTestHighWaterReset` to `tests/src/MaxEventNexus.Main.Tests.pas`:
  - Enqueue 11k items → verify `fWarnedHighWater = True`
  - Dequeue to 4k → verify `fWarnedHighWater = False`
  - Enqueue to 11k again → verify second warning

**Files to modify:**
- `maxLogic.EventNexus.pas`: fix `TmaxTopicBase.CheckHighWater` method
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestHighWaterReset` test case

---

## Medium Priority (v1.0 Polish)

### T-1006: Optimize Deadline Wrapper Allocation
**Status:** Creates closure for every enqueued item  
**Spec ref:** spec.md §11.2  
**Priority:** Medium (performance)  
**Effort:** Medium (1-2 days)

**Current state:**
- `Enqueue` wraps `aProc` in a closure that checks `lEnqueueTimer.ElapsedMilliseconds` before invoking
- **Issue:** Allocates closure even if deadline is far in future or item will execute immediately

**Proposed solution:**
1. Pre-check at enqueue time: if `fQueue.Count = 0` (will execute immediately), skip wrapper
2. Only wrap if item is queued *and* `Deadline` policy is active
3. Store `lEnqueueTimer` in a per-item record instead of closure capture

**Alternative:**
- Use a single shared wrapper per topic (store timer in thread-local or per-item record)
- Requires refactoring `fQueue` to store `{Proc, EnqueueTime}` pairs

**Testing:**
- Benchmark `Post` throughput with `Deadline` policy
- Verify no regression in deadline enforcement accuracy

**Files to modify:**
- `maxLogic.EventNexus.pas`: optimize `TmaxTopicBase.Enqueue` deadline wrapper logic
- `bench/BenchHarness.pas`: add deadline policy benchmark

---

### T-1007: Mitigate False Sharing in Metrics
**Status:** `fStats` fields adjacent, no cache-line padding  
**Spec ref:** spec.md §11.2  
**Priority:** Medium (performance)  
**Effort:** Small (1 day)

**Current state:**
- `TmaxTopicStats` is a plain record with 6 fields (48 bytes on x64)
- Multiple threads updating different counters will cause cache-line ping-pong

**Proposed solution:**
1. Pad `TmaxTopicStats` to 64-byte alignment:
   ```pascal
   TmaxTopicStats = record
     PostsTotal: UInt64;
     DeliveredTotal: UInt64;
     DroppedTotal: UInt64;
     ExceptionsTotal: UInt64;
     MaxQueueDepth: UInt32;
     CurrentQueueDepth: UInt32;
     _Padding: array[0..7] of Byte; // pad to 64 bytes
   end;
   ```
2. **Alternative:** Use per-CPU counters (array indexed by processor number) and aggregate on read

**Testing:**
- Benchmark multi-threaded `Post` with metrics enabled
- Measure cache misses (requires profiler like VTune or perf)

**Files to modify:**
- `maxLogic.EventNexus.pas`: add cache-line padding to `TmaxTopicStats`
- `bench/BenchHarness.pas`: add multi-threaded metrics benchmark

---

### T-1008: Optimize Copy-on-Write Scaling
**Status:** Copies entire array on every `Post`  
**Spec ref:** spec.md §11.2  
**Priority:** Medium (performance)  
**Effort:** Medium (2-3 days)

**Current state:**
- `TTypedTopic<T>.Snapshot` calls `copy(fSubs)` (dynamic array copy)
- Acceptable for <100 subscribers but scales poorly (O(N) copy on every post)

**Proposed solution:**
1. Use versioned immutable arrays:
   - Add `fVersion: UInt64` field to `TTypedTopic<T>`
   - Increment `fVersion` on `Add`/`RemoveByToken`
   - Readers snapshot `{fSubs, fVersion}` atomically
   - Skip copy if `fVersion` unchanged since last snapshot
2. **Alternative:** Use lock-free linked list with hazard pointers (complex; defer to v1.1)

**Testing:**
- Benchmark `Post` with 1k subscribers
- Verify <10% overhead vs. single subscriber

**Files to modify:**
- `maxLogic.EventNexus.pas`: add `fVersion` field, implement versioned snapshot
- `bench/BenchHarness.pas`: add subscriber-count scaling benchmark

---

### T-1009: Remove DEBUG Logging
**Status:** `{$IFDEF DEBUG} DebugLog(...) {$ENDIF}` scattered throughout code  
**Spec ref:** N/A (code cleanup)  
**Priority:** Low  
**Effort:** Trivial (1 hour)

**Action:**
- Remove all `DebugLog` calls or gate behind `{$IFDEF max_TRACE}` (off by default)
- Remove `gDebugLogPath`, `gDebugCs`, `DebugEnsureLog`, `DebugLog` from `maxLogic.EventNexus.pas`

**Files to modify:**
- `maxLogic.EventNexus.pas`: remove or conditionalize debug logging
- `fpc_delphimode.inc`: add `{$UNDEF max_TRACE}` by default

---

## Low Priority (v1.1+ Extensions)

### T-1010: Priority Subscriptions
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Medium (2-3 days)

**Implementation plan:**
1. Add `Priority: SmallInt` field to `TTypedSubscriber<T>` and `TNamedSubscriber`
2. Sort subscribers by priority (descending) on `Add`/`RemoveByToken`
3. Stable sort within same priority (preserve insertion order)
4. Add `SubscribeWithPriority<T>(aHandler, aMode, aPriority)` overload

**Testing:**
- Add `TTestPriority`: subscribe 3 handlers with priorities 10, 0, -10; verify execution order

**Files to modify:**
- `maxLogic.EventNexus.pas`: add priority field and sorting logic
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestPriority` test case

---

### T-1011: Bulk Dispatch API
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Medium (2-3 days)

**Implementation plan:**
1. Add `TmaxProcOfArray<T> = reference to procedure(const aValues: TArray<T>)`
2. Add `SubscribeBulk<T>(aHandler: TmaxProcOfArray<T>; aBatchSize: Integer)`
3. Accumulate events in per-topic buffer; flush when `aBatchSize` reached or timeout expires

**Testing:**
- Add `TTestBulkDispatch`: post 100 events; verify handler called ≤10 times with batches of 10

**Files to modify:**
- `maxLogic.EventNexus.pas`: add bulk subscription and batching logic
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestBulkDispatch` test case

---

### T-1012: Topic Groups / Wildcards
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Large (1 week)

**Implementation plan:**
1. Support glob patterns in `SubscribeNamed`: `orders.*` matches `orders.placed`, `orders.shipped`, etc.
2. Use trie or regex matcher for efficient lookup
3. **Caution:** Wildcard matching on `Post` hot path; benchmark carefully

**Testing:**
- Add `TTestWildcards`: subscribe to `orders.*`; post to `orders.placed` and `orders.shipped`; verify both delivered

**Files to modify:**
- `maxLogic.EventNexus.pas`: add wildcard matching logic to named topic lookup
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestWildcards` test case

---

### T-1013: Tracing Hooks (OpenTelemetry-style)
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Medium (2-3 days)

**Implementation plan:**
1. Add `TOnTraceEvent = reference to procedure(const aTopicName, aEventType: string; aTimestampUs: Int64)`
2. Call hook on `Post`, `Enqueue`, `Dispatch`, `Deliver` with event type and timestamp
3. Support correlation IDs via thread-local storage or context parameter

**Testing:**
- Add `TTestTracing`: enable hook; post event; verify 4 trace calls

**Files to modify:**
- `maxLogic.EventNexus.pas`: add tracing hook and call sites
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestTracing` test case

---

### T-1014: Serializer Plug-in (IPC bridge)
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Large (1-2 weeks)

**Implementation plan:**
1. Define `IEventSerializer` interface with `Serialize<T>` and `Deserialize<T>`
2. Add `maxSetSerializer(const aSerializer: IEventSerializer)`
3. On `Post`, serialize event and forward to IPC transport (named pipe, socket, etc.)
4. On receive, deserialize and dispatch locally

**Testing:**
- Add `TTestIPC`: post event in process A; verify delivery in process B

**Files to modify:**
- `maxLogic.EventNexus.pas`: add serializer interface and integration points
- New unit: `maxLogic.EventNexus.Serialization.pas`
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestIPC` test case

---

### T-1015: Disruptor-Style Sequences
**Spec ref:** spec.md §16 (proposed extensions)  
**Priority:** Low (v1.1)  
**Effort:** Very Large (2-3 weeks)

**Implementation plan:**
1. Implement SPSC/MPSC ring buffer with sequence numbers and barriers
2. Expose `CreateDisruptorTopic<T>(aCapacity: Integer): ImaxBus` factory
3. Use lock-free CAS for producer/consumer coordination
4. **Caution:** Complex; requires deep understanding of memory ordering

**Testing:**
- Benchmark vs. `TMonitor`-based queue; verify >10x throughput on hot topics

**Files to modify:**
- New unit: `maxLogic.EventNexus.Disruptor.pas`
- `bench/BenchHarness.pas`: add disruptor vs. standard queue benchmark

---

## Testing Gaps

### T-1016: Add Weak-Target ABA Test
**Spec ref:** spec.md §15 (testing matrix)  
**Priority:** Medium  
**Effort:** Small (1 day)

**Plan:**
- Allocate object at address A, free, allocate different object at same address A
- Verify generation/weak-ref prevents delivery to wrong object

**Files to modify:**
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestWeakTargetABA` test case

---

### T-1017: Add Stress Test (1M posts)
**Spec ref:** spec.md §15 (testing matrix)  
**Priority:** Medium  
**Effort:** Small (1 day)

**Plan:**
- Post 1M events across 10 topics with mixed delivery modes
- Verify no deadlocks, memory leaks, or crashes

**Files to modify:**
- `tests/src/MaxEventNexus.Main.Tests.pas`: add `TTestStress` test case

---

### T-1018: Add FPC Compatibility Test
**Spec ref:** spec.md §3 (platform support)  
**Priority:** High  
**Effort:** Small (1 day)

**Plan:**
- Run full test suite on FPC 3.2.2 (Linux x64)
- Verify all tests pass

**Files to modify:**
- CI configuration: add FPC 3.2.2 build job
- `build-tests.sh`: ensure FPC build succeeds

---

## Performance Benchmarks

### T-1019: Benchmark Suite
**Spec ref:** spec.md §11.2, bench/readme.md  
**Priority:** Medium  
**Effort:** Medium (2-3 days)

**Plan:**
- Measure `Post` latency (p50, p99, p999) for 1/10/100/1000 subscribers
- Measure throughput (posts/sec) for sync vs. async delivery
- Compare Delphi vs. FPC performance
- Output CSV for plotting

**Files to modify:**
- `bench/BenchHarness.pas`: add latency percentile calculation
- `bench/readme.md`: document benchmark methodology and KPIs

---

## Documentation

### T-1020: Finalize CHANGELOG.md
**Priority:** High  
**Effort:** Small (1 day)

**Action:**
- Document v0.1.0 → v1.0.0 changes
- List breaking changes (if any)

**Files to modify:**
- `CHANGELOG.md`: add v1.0.0 section

---

### T-1021: Update README.md
**Priority:** High  
**Effort:** Small (1 day)

**Action:**
- Add performance notes
- Add advanced usage examples (sticky, coalesce, queue policies)

**Files to modify:**
- `README.md`: expand with performance section and advanced examples

---

## Completed Tasks (Archive)

### ✅ T-0056: Stabilize subscriber array semantics
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** Copy-on-write arrays working correctly; ordering preserved

---

### ✅ T-0057: Emit metric samples
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** `TouchMetrics` implemented; callback fires on updates

---

### ✅ T-0058: Correct TryPost semantics
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** Returns False on drops; True on enqueue success

---

### ✅ T-0059: Integrate maxAsync adapter
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** `maxLogic.EventNexus.Threading.MaxAsync` integrated

---

### ✅ T-0060: Implement weak subscriber targets
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** FPC generation registry + Delphi raw pointer fallback

---

### ✅ T-0061: Warn on deep unbounded queues
**Status:** DONE  
**Completed:** 2025-01-XX  
**Notes:** `CheckHighWater` triggers at 10k depth (reset logic missing → T-1005)

---

## Removed Tasks (Out of Scope / Obsolete)

### ❌ T-0018: Verify FPC compilation
**Reason:** Superseded by T-1018 (more comprehensive FPC testing)

---

### ❌ T-0019: Achieve unit test coverage >=85%
**Reason:** Implicit in all test tasks; not a standalone deliverable

---

### ❌ T-0030: Generate API docs
**Reason:** Deferred to post-v1.0; not blocking release

---

### ❌ T-0032: Package artifacts
**Reason:** Deferred to post-v1.0; not blocking release

---

### ❌ T-0033: Sign artifacts
**Reason:** Deferred to post-v1.0; not blocking release

---

### ❌ T-0034: Mitigate deadlock risk
**Reason:** Covered by T-1003 (main-thread policy)

---

### ❌ T-0035: Monitor unbounded memory risk
**Reason:** Covered by T-1005 (high-water reset)

---

### ❌ T-0036: Improve weak target detection
**Reason:** Already implemented (T-0060 completed)

---

### ❌ T-0037: Enforce spec PR policy
**Reason:** Process/governance; not a code task

---

### ❌ T-0038: Label pull requests
**Reason:** Process/governance; not a code task

---

### ❌ T-0039: Weekly dev to main cut
**Reason:** Process/governance; not a code task

---

### ❌ T-0040: Introduce freelist pools
**Reason:** Deferred to v1.1 (optimization pass)

---

### ❌ T-0041: Avoid false sharing
**Reason:** Superseded by T-1007 (more specific)

---

### ❌ T-0042: Evaluate ring-buffer specialization
**Reason:** Deferred to v1.1 (T-1015 Disruptor)

---

### ❌ T-0043: Batch atomic operations
**Reason:** Deferred to v1.1 (optimization pass)

---

### ❌ T-0044: Validate completion criteria
**Reason:** Implicit in release checklist; not a code task

---

### ❌ T-0045: Cut first release
**Reason:** Implicit in release process; not a code task

---

### ❌ T-0049: Resolve FPC generic interface errors
**Reason:** Already resolved (FPC builds successfully)

---

### ❌ T-0051: Work around FPC interface generics
**Reason:** Already resolved (compatibility unit in place)

---

### ❌ T-0053: Introduce PTypeInfo-based ImaxBus for FPC
**Reason:** Already resolved (helper pattern working)

---

### ❌ T-0054: Provide FPC generic wrappers
**Reason:** Already resolved (ImaxBusHelper implemented)

---

### ❌ T-0055: Refactor bus core to PTypeInfo-based API
**Reason:** Already resolved (current architecture works)

---

## Notes

- **Versioning:** Current v0.1.0 → targeting v1.0.0 after high-priority tasks
- **Breaking changes:** None anticipated; all changes are additive or internal
- **FPC parity:** All features except `AutoSubscribe` (Delphi-only) are cross-compiler compatible
- **Performance targets:** See spec.md §7 for latency/throughput requirements
- **Test coverage goal:** ≥85% line/branch coverage on src/ (implicit in all test tasks)

---

**Last updated:** 2025-01-10  
**Maintainer:** MaxLogic Team
