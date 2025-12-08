# Tasks

## In Progress

### T-1022 Implement Delphi weak-target references
Summary: Implement proper weak-target support on Delphi using System.WeakReference so method subscriptions do not rely on access-violation probing.

Details:
- Spec: spec.md §6 (Handler lifetime), §10 (Weak Targets), references/weak-references*.md.
- Replace the Delphi branch of TmaxWeakTarget with an implementation backed by System.WeakReference.TWeakReference<TObject> (or equivalent shim) so IsAlive only returns True when the target can still be rehydrated.
- Ensure typed, named, and GUID subscriber records consistently store and consult the weak target before dispatch; keep PruneDead/RemoveByTarget fast and allocation-free on the hot path.
- Retain the current EAccessViolation/EInvalidPointer handling in TInvokeBox/MakeNamedHandlerProc only as a last-resort safety net, not as the primary liveness guard.
- Coordinate with T-1023 to validate behavior when objects are freed without explicit Unsubscribe/UnsubscribeAllFor and when AutoSubscribe is used.

### T-1028 Expose generic methods on Delphi interfaces
Summary: Expose generic Subscribe/Post/Advanced/Queue/Metrics methods on the Delphi interfaces, removing conditional compilation guards, and add regression tests that consume them via ImaxBus.

Details:
- Remove {$IFDEF FPC} guards around generic method declarations in ImaxBus, ImaxBusAdvanced, ImaxBusQueues, ImaxBusMetrics so they are compiled for Delphi as well.
- Ensure that ImaxBus includes Subscribe<T>, Post<T>, TryPost<T>, SubscribeNamedOf<T>, PostNamedOf<T>, TryPostNamedOf<T>, SubscribeGuidOf<T>, PostGuidOf<T>.
- Ensure ImaxBusAdvanced includes EnableSticky<T> (in addition to EnableStickyNamed) and the generic coalesce methods.
- Ensure ImaxBusQueues includes SetPolicyFor<T> and GetPolicyFor<T>.
- Ensure ImaxBusMetrics includes GetStatsFor<T>.
- Add a test case TTestInterfaceGenerics that obtains ImaxBus from maxBus and calls these generic methods without casting to TmaxBus, verifying they work.
- Update documentation to reflect that the generic API is fully available on the interface in both compilers.

### T-1040 Remove global bus lock
Summary: Eliminate the global bus lock (fLock) and implement fine-grained or lock-free structures for topic dictionary access to meet performance requirements.

Details:
- Spec: spec.md §7 (Performance Requirements) requires no global lock around Post.
- Replace the global TMonitor fLock with per-topic or lock-free dictionaries for fTyped, fNamed, fNamedTyped, fGuid.
- Use concurrent dictionaries or striped locks to protect topic lookup and creation.
- Ensure that Subscribe, Unsubscribe, Post, etc. are thread-safe without a single global lock.
- Preserve the existing per-topic locking for queue processing.
- Update tests to verify no global lock contention (T-1038 already provides concurrency tests; ensure they pass).
- Measure performance impact to confirm improvements.

## Next – Today

### T-1003 Add Main-Thread Degradation Policy
Summary: Introduce a configurable policy controlling how Main delivery behaves when invoked off the main thread.

Details:
- Spec: spec.md §8.5.
- Add TmaxMainThreadPolicy = (Strict, DegradeToAsync, DegradeToPosting) plus global gMainThreadPolicy defaulting to DegradeToPosting and maxSetMainThreadPolicy(aPolicy).
- In Dispatch for Main: when the current thread is not the main thread (neither TThread.CurrentThread.ThreadID = fMainThreadId nor IEventNexusScheduler.IsMainThread), first attempt to marshal via IEventNexusScheduler.RunOnMain; if the policy forbids marshaling, branch on gMainThreadPolicy:
  - Strict → raise EmaxMainThreadRequired with a clear message.
  - DegradeToAsync → schedule via IEventNexusScheduler.RunAsync.
  - DegradeToPosting (default) → run handler inline in the calling thread.
- Add TTestMainThreadPolicy in tests/src/MaxEventNexus.Main.Tests.pas to verify each mode across Posting/Main/Async/Background paths.

### T-1033 Rename EmaxAggregateException to EmaxDispatchError
Summary: Rename the aggregate exception class to match spec and ensure async error aggregation uses consistent naming.

Details:
- Spec: spec.md §11 (Error Semantics) specifies EmaxDispatchError.
- Rename EmaxAggregateException to EmaxDispatchError throughout the codebase and update all references.
- Ensure that the async error hook still receives the correct exception type (likely still Exception).
- Update documentation and changelog accordingly.

### T-1035 Extend GUID topics to advanced controls
Summary: Ensure GUID-keyed topics participate in sticky, coalesce, queue policy, and metrics APIs just like typed/named topics.

Details:
- Spec: spec.md §5.1, §8.4, §8.7, §11.1.
- Teach EnableSticky/EnableCoalesce*/SetPolicy*/GetPolicy*/GetStats* helpers to operate on GUID topics; add GUID-aware cache/pending dictionaries where missing.
- Update metrics aggregation so GUID topics surface via GetStatsNamed/GetTotals consistently.
- Add unit tests covering sticky/coalesce/queue policies for GUID topics plus TryPostGuidOf semantics.

## Next – This Week

### T-1002 Verify async error hook behavior
Summary: Ensure Async/Main/Background deliveries forward handler exceptions to the async error hook without breaking synchronous aggregate semantics.

Details:
- Spec: spec.md §6, §11.
- Confirm current Dispatch implementation behaves as designed: Posting aggregates handler exceptions into EmaxAggregateException; Async/Main/Background route handler exceptions to gAsyncError.
- Add TTestAsyncExceptions to tests/src/MaxEventNexus.Main.Tests.pas that:
  - Registers an Async-mode handler that always raises.
  - Installs a gAsyncError hook capturing topic name and exception instances.
  - Posts an event via Post<Integer> and verifies the hook is invoked and no exception escapes to the caller.
- Extend the test to cover Main and Background modes as well; only adjust implementation if tests expose a discrepancy with the spec.

### T-1004 Implement Metrics Throttling
Summary: Throttle metric callback invocations so high-frequency topics do not call the sampling hook on every counter update.

Details:
- Spec: spec.md §11.1, §11.2.
- Add fLastMetricSample: UInt64 to TmaxTopicBase and gMetricSampleIntervalMs: Cardinal defaulting to 1000 ms.
- Implement maxSetMetricSampleInterval(aIntervalMs: Cardinal).
- Update TouchMetrics to check elapsed time via GetTickCount64 and only invoke gMetricSample when enough time has passed and a metric name is set.
- Add TTestMetricsThrottling to tests/src/MaxEventNexus.Main.Tests.pas.

### T-1005 Fix High-Water Reset Logic
Summary: Make high-water queue depth warnings reset when depth falls back below the low-water threshold.

Details:
- Spec: TmaxTopicBase.CheckHighWater in maxLogic.EventNexus.pas.
- For unbounded topics (MaxDepth = 0), set fWarnedHighWater to True and call TouchMetrics when CurrentQueueDepth > 10000.
- Reset fWarnedHighWater to False (and TouchMetrics) once depth drops to ≤ 5000 so new warnings can fire later.
- Add TTestHighWaterReset to tests/src/MaxEventNexus.Main.Tests.pas.

### T-1009 Remove DEBUG Logging
Summary: Remove or hard-gate DebugLog so production builds aren’t cluttered with debug plumbing.

Details:
- Replace ad-hoc {$IFDEF DEBUG} DebugLog(...) {$ENDIF} calls with either removal or a dedicated {$IFDEF max_TRACE} guard that is off by default.
- Remove gDebugLogPath, gDebugCs, DebugEnsureLog, and DebugLog from maxLogic.EventNexus.pas if no longer needed.
- Optionally add {$UNDEF max_TRACE} to fpc_delphimode.inc.

### T-1016 Add Weak-Target ABA Test
Summary: Add a unit test that verifies weak-target generation/weak refs prevent ABA reuse issues.

Details:
- Spec: spec.md §15 (testing matrix).
- Allocate object at address A, free it, allocate another object reusing A, and check that queued work for the old object does not dispatch to the new instance.
- Implement as TTestWeakTargetABA in tests/src/MaxEventNexus.Main.Tests.pas.

### T-1017 Add Stress Test (1M posts)
Summary: Add a stress test posting 1M events across topics and delivery modes to validate stability.

Details:
- Spec: spec.md §15 (testing matrix).
- Implement TTestStress that posts ~1M events across ~10 topics with mixed delivery modes, asserting no deadlocks or crashes and optionally checking metrics.

### T-1018 Add FPC Compatibility Test
Summary: Run the full test suite on FPC 3.2.2 under CI to guarantee cross-compiler parity.

Details:
- Spec: spec.md §3 (platform support).
- Add a CI job (e.g., GitHub Actions) that builds and runs tests with FPC 3.2.2 on Linux x64.
- Ensure build-tests.sh and related scripts support FPC test builds and are wired into CI.
- This supersedes the older T-0018 “Verify FPC compilation” task.

### T-1020 Finalize CHANGELOG.md
Summary: Bring CHANGELOG.md up to date for the v1.0.0 release with all user-visible changes.

Details:
- Move completed high-priority v1.0 work from [Unreleased] into a new [1.0.0] section with a release date.
- Summarize major features, fixes, and any breaking changes.
- Keep task IDs referenced (e.g., “(T-1001)”) for traceability.

### T-1021 Update README.md
Summary: Update README.md with performance notes and advanced usage examples (sticky, coalesce, queue policies).

Details:
- Add a performance section summarizing expected throughput/latency envelopes and links to benchmarks.
- Add examples showing EnableSticky, EnableCoalesce*, and queue policy configuration with TryPost* semantics.
- Keep README focused and practical; defer deep details to spec.md and DESIGN.md.

### T-1023 Add weak-target and auto-unsubscribe tests
Summary: Add focused unit tests covering weak-target liveness, AutoSubscribe cleanup, and UnsubscribeAllFor across Delphi and FPC.

Details:
- Spec: spec.md §6, §15; DESIGN.md “Weak-Target Liveness”; references/weak-references*.md.
- Extend tests/src/MaxEventNexus.Main.Tests.pas with scenarios that:
  - Subscribe object methods (typed, named, GUID) and verify no further deliveries after the object is freed without explicit Unsubscribe, relying on weak targets to prevent use-after-free.
  - Verify AutoSubscribe + AutoUnsubscribe cooperate with UnsubscribeAllFor, including when AutoUnsubscribe is forgotten, and that fAutoSubs does not leak subscriptions.
  - Confirm releasing the last ImaxSubscription reference (assigning the interface to nil) automatically unsubscribes and stops further deliveries.
  - Simulate queued-before-cancel behavior by posting Async/Main work, releasing the subscription before dispatch, and asserting the liveness guard skips execution.
  - Validate that handler exceptions still increment ExceptionsTotal and do not mask weak-target liveness failures.
- Ensure these tests run on both Delphi and FPC, adapting where necessary for anonymous vs nested method forms.

### T-1025 Align spec/docs with actual API
Summary: Reconcile spec.md/README.md with the implemented API, especially around generic interfaces, helpers, and scheduler behavior.

Details:
- Spec: spec.md §5, §8, §11; DESIGN.md.
- Document the Delphi vs FPC differences for generics on interfaces (use of ImaxBusHelper/maxAsBus and ImaxBusAdvanced/ImaxBusQueues helpers) so callers know the supported patterns.
- Clarify how Main delivery degrades under different TmaxMainThreadPolicy modes once T-1003 is implemented, and update examples to use the current scheduling adapters.
- Ensure migration notes (MIGRATION.md) clearly map iPub/NX Horizon concepts to the actual EventNexus APIs as implemented.

### T-1026 Add metrics callback and GetTotals tests
Summary: Add tests around maxSetMetricCallback and ImaxBusMetrics.GetTotals to validate metrics aggregation.

Details:
- Spec: spec.md §11.1, §11.2.
- Add tests that install a metric callback, perform posts across typed, named, and GUID topics, and verify that the callback sees consistent TmaxTopicStats snapshots.
- Add tests for GetTotals aggregating across all topics and verifying PostsTotal/DeliveredTotal/DroppedTotal/ExceptionsTotal and queue depth fields.
- Ensure tests remain cheap to run and do not introduce background timers.

### T-1027 Clarify/default queue policy categories
Summary: Capture the queue-category preset strategy and override hooks so behavior stays transparent.

Details:
- Spec: spec.md §8.7.
- Produce a short ADR outlining how topics map to the “state/action/control-plane” presets, how overrides work, and how this integrates with metrics/high-water warnings (coordinate with T-1029).
- After implementation, update spec.md/README.md with a clear table of defaults plus override guidance, and ensure tests cover the override entry points.

### T-1029 Implement default queue policy presets
Summary: Apply the state/action/control-plane defaults from the spec when no explicit queue policy is provided.

Details:
- Spec: spec.md §8.7.
- Define simple heuristics/configuration to map topics into "state", "action", or "control-plane" categories (e.g., via explicit registration or sane defaults) and apply the required MaxDepth/Overflow/DeadlineUs values automatically.
- Ensure unnamed typed topics adopt the correct preset on first subscription/post; named topics should inherit defaults unless caller overrides via SetPolicy*.
- Update queue bookkeeping so warnings/metrics reflect the preset policies, and extend tests to cover default policy selection and overflow behavior without manual configuration.
- Document the preset behavior (tie-in with T-1025) and provide an escape hatch for callers needing custom defaults.

### T-1030 Ensure runtime scheduler swaps take effect
Summary: Ensure maxSetAsyncScheduler updates the active bus instance even after construction.

Details:
- Spec: spec.md §4.1 (Threading & maxAsync Integration).
- Under the same lock protecting gBus, update the live TmaxBus.fAsync reference (and any fallback scheduler) whenever maxSetAsyncScheduler is called after the singleton exists; treat nil as a request to revert to the default scheduler.
- Add a test in tests/src/MaxEventNexus.Main.Tests.pas that installs a capturing scheduler after creating maxBus and verifies subsequent Async/Main/Background posts run on the swapped scheduler.
- Confirm no leaks by releasing references to the previous scheduler once swapped, and coordinate with T-1024 for concurrency safety.

### T-1031 Remove Post hot-path heap allocations
Summary: Eliminate steady-state allocations in Post/TryPost paths to satisfy spec performance requirements.

Details:
- Spec: spec.md §7 (Performance Requirements).
- Profile Post<T> and PostNamedOf<T> to identify allocations (e.g., TInvokeBox instances) under Delphi and FPC using FastMM or FPC heap tracing.
- Introduce stack-based invoke shims or per-topic object pools so dispatch uses preallocated records; validate that warmed Post loops allocate zero bytes.
- Extend bench/BenchHarness.pas or add a dedicated regression test that asserts allocation counts remain flat once the bus is warmed.

### T-1036 Make metrics snapshot lock-free
Summary: Serve GetStats*/GetTotals without taking the global bus lock so metrics reads stay cheap under contention.

Details:
- Spec: spec.md §11.1 (Diagnostics & Metrics) and §7 (Performance Requirements) require lock-free/low-contention metrics.
- Refactor TmaxTopicBase stats storage so reads use atomics or per-topic snapshots (e.g., UInt64/UInt32 atomics or versioned records) instead of the monolithic bus lock; ensure TouchMetrics remains cheap.
- Update GetStatsFor/GetStatsNamed/GetTotals to aggregate using lock-free snapshots; document memory-ordering assumptions.
- Add concurrency tests (e.g., TTestMetricsConcurrent) that hammer Post/metrics reads from multiple threads to confirm no deadlocks and acceptable performance.

### T-1039 Document lock-free posting changes
Summary: Update DESIGN.md and CHANGELOG.md to describe the new concurrency model and user-visible behavior.

Details:
- Document that Post no longer takes the global bus lock and reference the per-topic locking strategy.
- Mention any new diagnostics or guidance for integrators in README/DESIGN as appropriate.
- Add changelog entry under [Unreleased] “Changed”.

## Next – Later

### T-1006 Optimize Deadline Wrapper Allocation
Summary: Reduce allocations in Deadline overflow policy by avoiding per-item closure creation when unnecessary.

Details:
- Spec: spec.md §11.2.
- Pre-check at enqueue time: if the queue is empty and the item will run immediately, bypass the deadline wrapper.
- Only wrap items when Deadline policy is active and the item will sit in the queue.
- Consider storing enqueue time in a lightweight record rather than capturing a TStopwatch in a closure.
- Benchmark Post throughput with Deadline enabled.

### T-1007 Mitigate False Sharing in Metrics
Summary: Reduce cache-line contention in metrics counters under multi-threaded load.

Details:
- Spec: spec.md §11.2.
- Pad TmaxTopicStats to a full cache line (e.g., via a _Padding field) to keep hot counters on their own line.
- Optionally explore sharded/per-CPU counters aggregated on read if profiling shows contention.
- Extend BenchHarness to stress metrics in multi-threaded scenarios.

### T-1008 Optimize Copy-on-Write Scaling
Summary: Improve copy-on-write subscriber snapshot behavior so Post scales well with many subscribers.

Details:
- Spec: spec.md §11.2.
- Introduce a version field on per-topic subscriber arrays; update on add/remove and let Post reuse snapshots when the version hasn’t changed.
- Avoid copying the whole subscriber array on every Post when there are no structural mutations.
- Add benchmarks for Post with 1k+ subscribers.

### T-1010 Priority Subscriptions
Summary: Allow subscribers to register with priorities so dispatch order can be influenced.

Details:
- Spec: spec.md §16 (proposed extensions).
- Add Priority: SmallInt to typed and named subscriber records and sort by priority (descending), preserving insertion order within each priority.
- Add SubscribeWithPriority<T>(...) overloads.
- Add TTestPriority to tests/src/MaxEventNexus.Main.Tests.pas.

### T-1011 Bulk Dispatch API
Summary: Provide a bulk dispatch API so handlers can receive batches of events and amortize per-event overhead.

Details:
- Spec: spec.md §16 (proposed extensions).
- Define TmaxProcOfArray<T> = reference to procedure(const aValues: TArray<T>).
- Add SubscribeBulk<T>(aHandler: TmaxProcOfArray<T>; aBatchSize: Integer) and buffers per topic.
- Flush batches based on size or time.
- Test via TTestBulkDispatch in tests/src/MaxEventNexus.Main.Tests.pas.

### T-1012 Topic Groups / Wildcards
Summary: Support wildcard patterns (e.g., orders.*) for named topics to subscribe to groups.

Details:
- Spec: spec.md §16 (proposed extensions).
- Extend SubscribeNamed to accept glob-style patterns and implement efficient matching that doesn’t blow up the Post hot path.
- Add TTestWildcards to tests/src/MaxEventNexus.Main.Tests.pas.

### T-1013 Tracing Hooks (OpenTelemetry-style)
Summary: Add tracing hooks so callers can observe Post/enqueue/dispatch/deliver events with timestamps and topic names.

Details:
- Spec: spec.md §16 (proposed extensions).
- Define TOnTraceEvent = reference to procedure(const aTopicName, aEventType: string; aTimestampUs: Int64) and a setter.
- Invoke the hook at key points; support correlation IDs via context or thread-local state.
- Add TTestTracing to tests/src/MaxEventNexus.Main.Tests.pas.

### T-1014 Serializer Plug-in (IPC bridge)
Summary: Introduce a serializer plug-in abstraction to support cross-process event forwarding.

Details:
- Spec: spec.md §16 (proposed extensions).
- Define IEventSerializer with Serialize<T>/Deserialize<T> and a maxSetSerializer(...) function.
- Integrate serializer into Post paths that bridge to IPC while keeping in-process dispatch untouched.
- Add maxLogic.EventNexus.Serialization.pas and TTestIPC in tests/src/MaxEventNexus.Main.Tests.pas.

### T-1015 Disruptor-Style Sequences
Summary: Explore a Disruptor-style ring-buffer implementation for ultra-hot topics.

Details:
- Spec: spec.md §16 (proposed extensions).
- Implement SPSC/MPSC ring buffers with sequence numbers and barriers and expose a CreateDisruptorTopic<T>(aCapacity: Integer): ImaxBus factory.
- Use lock-free CAS and reason carefully about memory ordering.
- Add a benchmark in BenchHarness comparing Disruptor topics vs standard queues.

### T-1019 Benchmark Suite
Summary: Build a richer benchmark suite measuring latency and throughput across subscriber counts, delivery modes, and compilers.

Details:
- Spec: spec.md §11.2, bench/readme.md.
- Extend bench/BenchHarness.pas to compute latency percentiles (p50/p99/p999) and throughput for varying subscriber counts.
- Output CSV for external plotting and document methodology and KPIs in bench/readme.md.

## Blocked

## Done

### T-1001 Implement AutoSubscribe/AutoUnsubscribe (Delphi only)
Summary: Implement AutoSubscribe/AutoUnsubscribe using RTTI and maxSubscribeAttribute so attribute-based subscriptions work as specified on Delphi.

Details:
- AutoSubscribe scans public/protected/published methods (including inherited ones) on aInstance.ClassType for [maxSubscribe], validates signatures, determines topic kind (typed, named, GUID), and subscribes via Subscribe*, SubscribeNamed*/SubscribeNamedOf*, or SubscribeGuidOf as appropriate.
- AutoUnsubscribe looks up stored ImaxSubscription tokens in fAutoSubs keyed by instance, unsubscribes them, and clears the entry; AutoSubscribe first clears any previous auto subscriptions for the same instance to avoid leaks and double registration.
- Invalid signatures (non-procedure methods, more than one parameter, var/out parameters, or missing parameter for typed topics) raise EmaxInvalidSubscription, covered by TTestAutoSubscribe.InvalidSignatureRaises in tests/src/MaxEventNexus.Main.Tests.pas.
- Attribute-based subscriptions are exercised end-to-end by TTestAutoSubscribe.RegistersTypedNamedAndInherited, TTestAutoSubscribe.AutoUnsubscribeClearsHandlers, and the AutoSubscribeSample program in samples/AutoSubscribeSample.pas.

### T-0056 Stabilize subscriber array semantics
Summary: Ensure copy-on-write subscriber arrays work correctly under churn and preserve ordering.

Details:
- Status: DONE.
- Notes: COW arrays for typed/named topics are in place; ordering verified by unit tests.

### T-0057 Emit metric samples
Summary: Implement TouchMetrics so metric snapshots can be sampled cheaply from outside.

Details:
- Status: DONE.
- Notes: TouchMetrics calls the configured metric callback; throttling is tracked separately in T-1004.

### T-0058 Correct TryPost semantics
Summary: Ensure TryPost* returns False when the new item is dropped and True when it is enqueued (even if an older item is dropped).

Details:
- Status: DONE.
- Notes: Semantics now match spec.md §8.7.

### T-0059 Integrate maxAsync adapter
Summary: Integrate maxLogic.EventNexus.Threading.MaxAsync as an async scheduler adapter.

Details:
- Status: DONE.
- Notes: maxAsync adapter implemented and wired via maxSetAsyncScheduler.

### T-0060 Implement weak subscriber targets
Summary: Implement weak-target handling for method subscribers across Delphi and FPC.

Details:
- Status: DONE.
- Notes: FPC uses a generation registry; Delphi uses raw pointers for now; liveness checked on dispatch.

### T-1024 Make maxBus singleton factory thread-safe
Summary: Guarded `maxBus` construction and async scheduler swapping with a global monitor and added regression tests.

Details:
- Added `gBusLock` in maxLogic.EventNexus.pas to serialize singleton creation, scheduler retrieval, and runtime swaps, ensuring `maxSetAsyncScheduler` updates the live bus safely.
- Introduced `TTestBusSingleton.SingletonIsThreadSafe` and `SchedulerSwapUpdatesLiveBus` to verify multi-threaded `maxBus` calls share the same instance and that custom schedulers take effect immediately.
- CHANGELOG documents the user-visible behavior change and tests reference T-1024.

### T-0061 Warn on deep unbounded queues
Summary: Warn via metrics when unbounded queues grow too deep.

Details:
- Status: DONE.
- Notes: CheckHighWater triggers at 10k depth; reset behavior is refined under T-1005.

### T-0018 Verify FPC compilation
Summary: Original task to verify FPC builds for the project, now superseded.

Details:
- Status: DONE (superseded).
- Reason: Replaced by T-1018 Add FPC Compatibility Test, which covers CI and runtime tests.

### T-0019 Achieve unit test coverage >=85%
Summary: Original explicit coverage goal for src/; now treated as an implicit target.

Details:
- Status: DONE (folded into general testing work).
- Reason: Coverage is tracked implicitly via ongoing test tasks; no separate status field needed.

### T-0030 Generate API docs
Summary: Task to generate API documentation.

Details:
- Status: DONE (removed from v1.0 scope).
- Reason: Deferred to post-v1.0; not a release blocker.

### T-0032 Package artifacts
Summary: Task to package release artifacts.

Details:
- Status: DONE (removed from v1.0 scope).
- Reason: Deferred to post-v1.0; tracked in release process instead.

### T-0033 Sign artifacts
Summary: Task to sign release artifacts.

Details:
- Status: DONE (removed from v1.0 scope).
- Reason: Deferred to post-v1.0; not needed for initial release.

### T-0034 Mitigate deadlock risk
Summary: Task to address potential deadlocks, folded into main-thread policy work.

Details:
- Status: DONE (superseded).
- Reason: Covered by T-1003 Add Main-Thread Degradation Policy.

### T-0035 Monitor unbounded memory risk
Summary: Task to monitor unbounded queue growth.

Details:
- Status: DONE (superseded).
- Reason: Covered by T-1005 Fix High-Water Reset Logic and metrics.

### T-0036 Improve weak target detection
Summary: Task to improve weak-target detection behavior.

Details:
- Status: DONE.
- Reason: Implemented as part of T-0060; this entry is now archival.

### T-0037 Enforce spec PR policy
Summary: Governance task for enforcing spec PR policy.

Details:
- Status: DONE (tracked elsewhere).
- Reason: Process/governance is handled outside TASKS.md.

### T-0038 Label pull requests
Summary: Governance task for PR labeling.

Details:
- Status: DONE (tracked elsewhere).
- Reason: Process-only; no longer tracked here.

### T-0039 Weekly dev to main cut
Summary: Governance task for a weekly dev→main merge cadence.

Details:
- Status: DONE (tracked elsewhere).
- Reason: Part of team process, not a code task.

### T-0040 Introduce freelist pools
Summary: Optimization task to introduce freelist pools for allocations.

Details:
- Status: DONE (deferred).
- Reason: Deferred to a future optimization pass (v1.1+); not needed for v1.0.

### T-0041 Avoid false sharing
Summary: Early task aiming to address false sharing in general.

Details:
- Status: DONE (superseded).
- Reason: Replaced by more concrete metrics-focused T-1007.

### T-0042 Evaluate ring-buffer specialization
Summary: Investigate ring-buffer specialization for hot topics.

Details:
- Status: DONE (superseded).
- Reason: Folded into T-1015 Disruptor-Style Sequences.

### T-0043 Batch atomic operations
Summary: General task to batch atomic operations for performance.

Details:
- Status: DONE (deferred).
- Reason: Deferred to a later optimization round; not required for v1.0.

### T-0044 Validate completion criteria
Summary: Task to validate “Definition of Done” criteria.

Details:
- Status: DONE.
- Reason: Now part of standard release checklist documentation.

### T-0045 Cut first release
Summary: Task representing the initial release cut.

Details:
- Status: DONE.
- Reason: Covered by release process; no longer tracked separately.

### T-0049 Resolve FPC generic interface errors
Summary: Task to resolve FPC generic interface issues.

Details:
- Status: DONE.
- Reason: FPC builds successfully; helper/compat units are in place.

### T-0051 Work around FPC interface generics
Summary: Implement workarounds for FPC interface generics limitations.

Details:
- Status: DONE.
- Reason: Compatibility layer implemented; task archived.

### T-0053 Introduce PTypeInfo-based ImaxBus for FPC
Summary: Task to refactor FPC ImaxBus usage to PTypeInfo-based APIs.

Details:
- Status: DONE.
- Reason: Current architecture already uses the desired approach.

### T-0054 Provide FPC generic wrappers
Summary: Task to provide generic wrappers for FPC builds.

Details:
- Status: DONE.
- Reason: ImaxBusHelper and related wrappers are implemented.

### T-0055 Refactor bus core to PTypeInfo-based API
Summary: Task to refactor the bus core away from generic interface methods.

Details:
- Status: DONE.
- Reason: Bus core now uses PTypeInfo-driven internals as planned.

### T-1038 Add concurrency tests for lock-free posting
Summary: Extend tests/src/MaxEventNexus.Main.Tests.pas with stress cases that detect global-lock regressions.

Details:
- Add TTestNoGlobalLock (or similar) that spawns multiple threads posting to different topics and asserts throughput/absence of deadlock via timing or instrumentation.
- Cover typed, named, and GUID topics plus TryPost variants to ensure queue policies still work without the global lock.
- Use high-resolution timers/logging to flag if posting still blocks longer than expected.

Status:
- DONE. Implemented TTestNoGlobalLock.CrossTopicPostsDoNotSerializeOnGlobalLock and NamedAndGuidPostsDoNotSerializeOnGlobalLock in tests/src/MaxEventNexus.Main.Tests.pas. Both tests spawn multiple threads across typed, named, GUID topics and TryPostNamedOf to verify no apparent global-lock serialization.
