# Tasks

## In Progress

## Next – Today

## Next – This Week

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

### T-1025 Align spec/docs with actual API
Summary: Reconcile spec.md/README.md with the implemented API, especially around generic interfaces, helpers, and scheduler behavior.

Details:
- Spec: spec.md §5, §8, §11; DESIGN.md.
- Document the Delphi vs FPC differences for generics on interfaces (use of ImaxBusHelper/maxAsBus and ImaxBusAdvanced/ImaxBusQueues helpers) so callers know the supported patterns.
- Clarify how Main delivery degrades under different TmaxMainThreadPolicy modes once T-1003 is implemented, and update examples to use the current scheduling adapters.
- Ensure migration notes (MIGRATION.md) clearly map iPub/NX Horizon concepts to the actual EventNexus APIs as implemented.

### T-1027 Clarify/default queue policy categories
Summary: Capture the queue-category preset strategy and override hooks so behavior stays transparent.

Details:
- Spec: spec.md §8.7.
- Produce a short ADR outlining how topics map to the “state/action/control-plane” presets, how overrides work, and how this integrates with metrics/high-water warnings (coordinate with T-1029).
- After implementation, update spec.md/README.md with a clear table of defaults plus override guidance, and ensure tests cover the override entry points.

### T-1039 Document lock-free posting changes
Summary: Update DESIGN.md and CHANGELOG.md to describe the new concurrency model and user-visible behavior.

Details:
- Document that Post no longer takes the global bus lock and reference the per-topic locking strategy.
- Mention any new diagnostics or guidance for integrators in README/DESIGN as appropriate.
- Add changelog entry under [Unreleased] “Changed”.

## Next – Later

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

## Blocked

## Ongoing

### T-1042 Keep README.md in sync
Summary: Update `README.md` when we finish a task that changes user-visible behavior so docs don’t drift from implementation.

Details:
- Add/update short “What’s New” bullets for completed tasks and keep links/current APIs accurate.
- Prefer short callouts in README and defer deep details to `spec.md` / `DESIGN.md`.

## Done

### T-1022 Implement Delphi weak-target references
Summary: Implement proper weak-target support on Delphi so method subscriptions do not rely on access-violation probing.

Details:
- Implemented a Delphi weak-target shim (generation registry + `FreeInstance` hook) so dispatch-time liveness checks can reliably skip freed targets and lazily prune dead subscriptions.
- Added `TTestWeakTargets` covering typed, named-of, and GUID-of method subscriptions after the target is freed.

### T-1041 Fix coalescing flush and exception-path invoke ownership
Summary: Fix coalescing dispatch reliability and remove exception-path double-frees in invoke boxing.

Details:
- Coalescing now schedules a single per-topic flush and clears pending state when there are no subscribers, preventing later posts from being starved.
- Removed `lBox.Free` from exception capture paths because invoke boxes free themselves in their generated handler procs.

### T-1040 Remove global bus lock
Summary: Eliminate the global bus lock and use fine-grained synchronization for topic registries.

Details:
- Replaced the single `fLock` monitor with per-registry locks and made per-topic subscriber COW mutation thread-safe.
- Updated dispatch/queue logic to avoid serializing posts across unrelated topics.

### T-1003 Add Main-Thread Degradation Policy
Summary: Introduce a configurable policy controlling how `Main` delivery behaves when invoked off the main thread.

Details:
- Added `TmaxMainThreadPolicy` + `maxSetMainThreadPolicy(...)` and implemented Strict/DegradeToAsync/DegradeToPosting behavior.
- Added unit tests covering each policy mode.

### T-1035 Extend GUID topics to advanced controls
Summary: Ensure GUID-keyed topics participate in coalescing, queue policy, and metrics APIs like typed/named topics.

Details:
- Added `TryPostGuidOf`, GUID coalescing (`EnableCoalesceGuidOf`), GUID queue policy (`SetPolicyGuidOf`/`GetPolicyGuidOf`), and GUID stats (`GetStatsGuidOf`).
- Added unit tests for GUID coalescing and GUID queue policy/metrics.

### T-1031 Remove Post hot-path heap allocations
Summary: Eliminate steady-state allocations in Post/TryPost paths to satisfy spec performance requirements.

Details:
- Updated Posting-mode dispatch loops to avoid per-subscriber heap allocations on the hot Post/TryPost path (Delphi/FPC), and moved exception metrics accounting into the invoke shims so Posting calls can dispatch without allocating helper closures.

### T-1036 Make metrics snapshot lock-free
Summary: Serve GetStats*/GetTotals without taking the global bus lock so metrics reads stay cheap under contention.

Details:
- Topic stats snapshots now read atomic counters without taking the bus lock; metrics aggregation reads from an immutable index snapshot.
- Added concurrency coverage to hammer posting and metrics reads concurrently.

### T-1033 Rename EmaxAggregateException to EmaxDispatchError
Summary: Rename the aggregate exception class to match spec and ensure async error aggregation uses consistent naming.

Details:
- Renamed the aggregate dispatch exception type to `EmaxDispatchError` and updated callers.
- Updated documentation and changelog accordingly.

### T-1005 Fix High-Water Reset Logic
Summary: Make high-water queue depth warnings reset when depth falls back below the low-water threshold.

Details:
- High-water reset now emits a metric sample on reset and added `TTestHighWaterReset`.

### T-1004 Implement Metrics Throttling
Summary: Throttle metric callback invocations so high-frequency topics do not call the sampling hook on every counter update.

Details:
- Added `gMetricSampleIntervalMs` (default 1000ms) + `maxSetMetricSampleInterval(...)` and per-topic `fLastMetricSample` to throttle `maxSetMetricCallback`.
- Added `TTestMetricsThrottling` and ensured high-water edges emit a sample so warnings can re-trigger.

### T-1002 Verify async error hook behavior
Summary: Ensure Async/Main/Background deliveries forward handler exceptions to the async error hook without breaking synchronous aggregate semantics.

Details:
- Added `TTestAsyncExceptions.ErrorsForwardToHookNoRaise`, covering Main/Async/Background exception forwarding to `maxSetAsyncErrorHandler` without exceptions escaping to the caller.

### T-1006 Optimize Deadline Wrapper Allocation
Summary: Reduce allocations in Deadline overflow policy by avoiding per-item wrapper creation when unnecessary.

Details:
- Deadline staleness wrappers are only created when the item can actually sit in the queue (i.e., backlog exists); immediate execution skips the wrapper.

### T-1030 Ensure runtime scheduler swaps take effect
Summary: Ensure maxSetAsyncScheduler updates the active bus instance even after construction.

Details:
- `maxSetAsyncScheduler` now updates the live singleton bus (when already constructed) so subsequent Async/Main/Background deliveries use the new scheduler.
- Added `TTestSchedulers.SchedulerSwapUpdatesLiveBus`.

### T-1009 Remove DEBUG Logging
Summary: Remove DebugLog so production builds aren’t cluttered with debug plumbing.

Details:
- Removed DEBUG logging helpers and all call-sites from `maxLogic.EventNexus.Core.pas`.

### T-1016 Add Weak-Target ABA Test
Summary: Add a unit test that verifies weak-target generation prevents ABA reuse issues.

Details:
- Added `TTestWeakTargetABA` covering address reuse and queued work safety.

### T-1017 Add Stress Test (1M posts)
Summary: Add a stress test posting 1M events across topics and delivery modes to validate stability.

Details:
- Added `TTestStress.OneMillionPosts` using the inline scheduler to avoid thread explosion.

### T-1026 Add metrics callback and GetTotals tests
Summary: Add tests around maxSetMetricCallback and ImaxBusMetrics.GetTotals to validate metrics aggregation.

Details:
- Added `TTestMetricsCallbackTotals` verifying callback snapshots and GetTotals aggregation across topic types.

### T-1023 Add weak-target and auto-unsubscribe tests
Summary: Add focused unit tests covering weak-target liveness and auto-unsubscribe/token teardown.

Details:
- Added tests covering token auto-unsubscribe, queued-before-cancel skipping, and Delphi-only AutoSubscribe cleanup.

### T-1029 Implement default queue policy presets
Summary: Apply the state/action/control-plane defaults when no explicit queue policy is provided.

Details:
- Added `TmaxQueuePreset` + `maxSetQueuePresetNamed/maxSetQueuePresetForType/maxSetQueuePresetGuid`.
- Applied presets on topic creation and via GetPolicy* when a preset exists but the topic hasn’t been created yet.

### T-1021 Update README.md
Summary: Update README.md with performance notes and advanced usage examples (sticky, coalesce, queue policies).

Details:
- Updated README with new features callouts, Delphi vs FPC usage notes, and advanced usage snippets.

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
- Notes: Delphi 12+ and FPC use a generation registry; liveness is checked on dispatch.

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
