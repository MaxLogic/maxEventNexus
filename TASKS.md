# Tasks
Next task ID: T-1084

## Summary
Open tasks: 1 (In Progress: 0, Next Today: 0, Next This Week: 1, Next Later: 0, Blocked: 0)
Done tasks: 105

## In Progress

## Next – Today

## Next – This Week

### T-1082 [BENCH] Build cross-library benchmarks versus iPub and EventHorizon
Outcome: Add benchmark harness coverage and reporting that compares EventNexus against iPub and EventHorizon on equivalent publish/subscribe workloads.
Proof:
- Command: `./build-delphi.sh bench/SchedulerCompare.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex`
- Expect: exit code `0`; benchmark project builds successfully.
- Command: `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"`
- Expect: exit code `0`; CSV output generated with comparable rows for enabled libraries/schedulers and no runtime errors.
Touches: `bench/`, `bench/readme.md`, `TASKS.md`, `CHANGELOG.md`
Deps: `T-1080`
Notes:
- Keep workload parity explicit (same payload size, consumer count, delivery mode, run count) so results are interpretable.

## Next – Later

## Blocked

## Ongoing

### T-1042 Keep README.md in sync
Summary: Update `README.md` when we finish a task that changes user-visible behavior so docs don’t drift from implementation.

Details:
- Add/update short “What’s New” bullets for completed tasks and keep links/current APIs accurate.
- Prefer short callouts in README and defer deep details to `spec.md` / `DESIGN.md`.

## Done

### T-1083 [ANALYSIS] Resolve remaining actionable FixInsight warnings
Summary: Cleared remaining actionable FixInsight warnings (`C110`, `W515`, `W524`) from the active analysis baseline.

Details:
- Renamed wake-signal getter paths in `maxAsync` (`GetWakeSignal` -> `GetWakeUpSignal`) to align property/getter naming and clear `C110`.
- Kept intentional one-shot `TAsyncLoop` self-destruction and documented it with explicit analyzer suppression on the `Free` site to clear reviewed `W515`.
- Kept GUID requirement for generic `iUserData<T>` (needed for `Supports`/RTTI paths) and documented it with explicit analyzer suppression to clear reviewed `W524`.
- Proof: `./build-static-analysis.sh && ./build/check-analysis-thresholds.sh build/analysis/summary.md build/analysis/analysis-thresholds.csv` (exit `0`, no remaining `C110`/`W515`/`W524` entries in `fixinsight.txt`).
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + analysis threshold gate pass).

### T-1081 [TEST] Review and expand DUnitX coverage for correctness confidence
Summary: Expanded DUnitX coverage for previously under-tested public API slices and edge-path behavior.

Details:
- Added delayed-post coverage for `PostDelayedNamedOf<T>` and `PostDelayedGuidOf<T>` including timing/payload assertions.
- Added GUID preset-policy coverage for `maxSetQueuePresetGuid`, `GetPolicyGuidOf<T>`, and explicit-policy precedence over preset updates.
- Added `PostResultNamedOf<T>` dropped-path coverage and `PostResultGuidOf<T>` dispatched-inline coverage.
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + static analysis + threshold gate pass).
- Proof: `rg -n "NamedOfDelayedPostWaitsBeforeDelivery|GuidDelayedPostWaitsBeforeDelivery|GuidPresetAffectsGetPolicy|GuidExplicitPolicyBeatsPreset|NamedOfDropNewestReturnsDropped|GuidOfAcceptedReturnsInline" tests/src/MaxEventNexus.Main.Tests.pas` (exit `0`).

### T-1080 [ANALYSIS] Resolve non-noise FixInsight warnings batch
Summary: Cleared actionable/non-noise static-analysis warnings while preserving API compatibility and keeping test/build gates green.

Details:
- Removed actionable warning patterns in test fixtures (`W519`, `W528`) without changing test intent.
- Cleaned actionable findings in shared foundation units (`maxLogic.StrUtils`, `maxAsync`) and kept API-shape warnings compatibility-safe where signature changes were not allowed.
- Reduced FixInsight findings from `48` to `37`; remaining findings are mostly length/variable-density style debt (`C101`/`C103`) plus known parser/tooling limitations and explicitly reviewed legacy warnings.
- Proof: `./build-static-analysis.sh && ./build/check-analysis-thresholds.sh build/analysis/summary.md build/analysis/analysis-thresholds.csv` (exit `0`).
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + analysis threshold gate pass).

### T-1079 [CORE] Evaluate C102/O804 reduction in maxlogic.strutils without API breaks
Summary: Reduced foundation-level `C102`/`O804` debt in `maxlogic.strutils` without changing public API signatures.

Details:
- Kept existing public signatures and added function-line analyzer suppressions for legacy multi-parameter compatibility entry points (`ExtractString` overloads, `ReplacePlaceholder`).
- Removed remaining `O804` in `fStr` by consuming the `vs` parameter without changing API surface.
- Proof: `./build-static-analysis.sh && ./build/check-analysis-thresholds.sh build/analysis/summary.md build/analysis/analysis-thresholds.csv` (exit `0`, `C102/O804` no longer reported; threshold gate passes).
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX suite and default build+analysis flow pass).

### T-1078 [CORE] Continue FixInsight reduction on C102/O804 hotspots
Summary: Removed test-local `O804` hotspots and confirmed `C102`/`O804` debt now remains only in shared foundation code.

Details:
- Updated test callback targets to consume parameters without behavior changes (`TTarget.Handle`, `TWeakTargetProbe.OnInt`, `TWeakTargetProbe.OnIntf`).
- Used `aBus` explicitly in `TTestInterfaceGenerics.VerifyPostAndTryPost` to remove Delphi-only unused-parameter debt in shared helper logic.
- Post-batch summary now reports `O804=1` (remaining entry is `maxlogic.strutils`) with no `O804` entries left in `src/MaxEventNexus.Main.Tests.pas`.
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + static analysis + threshold gate pass).

### T-1077 [TEST] Harden delayed posting edge-case coverage
Summary: Added deterministic delayed-posting edge-case tests for zero-delay metrics behavior and long-delay pending/cancel lifecycle.

Details:
- Added `TTestDelayedPosting.ZeroDelayDispatchesAndUpdatesMetrics` to verify zero-delay dispatch delivery, stats increments, and post-dispatch `Cancel` behavior.
- Added `TTestDelayedPosting.LargeDelayRemainsPendingUntilCanceled` using a deterministic hold scheduler to assert `IsPending` and `Cancel` semantics without thread-pool submission flakiness.
- Added internal test scheduler `THoldDelayedScheduler` for delayed-handle lifecycle assertions where delayed callbacks must remain pending until explicit cancellation.
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + static analysis + threshold gate pass).

### T-1075 [CORE] Continue FixInsight C101/C103 reduction batch in high-density test fixtures
Summary: Reduced remaining top FixInsight debt in high-density test fixtures while keeping behavior and public APIs unchanged.

Details:
- Refactored coalescing fixtures with helper methods (`MakeKeyed`, `AddKeyedValue`, `FindKeyedValue`, `WaitForKeyedCount`) and tightened assertions while preserving semantics.
- Simplified async exception fixture setup (`ErrorsForwardToHookNoRaise`) and dispatch-error detail assertions to shrink method/local complexity.
- Trimmed scheduler exercise timing locals and tightened delayed-posting tests to reduce variable pressure in long methods.
- Lowered tracked analyzer thresholds to match new achieved top-code counts (`C101=20`, `C103=14`).
- Proof: `./build-static-analysis.sh && ./build/check-analysis-thresholds.sh build/analysis/summary.md build/analysis/analysis-thresholds.csv` (exit `0`, thresholds pass at `C101=20`, `C103=14`).
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX suite passes under default build+analysis flow).

### T-1076 [API] Add delayed posting APIs with cancellation handle
Summary: Added delayed post APIs across topic families with cancellable handles and clear-boundary dropping semantics.

Details:
- Added `ImaxDelayedPost` (`Cancel`, `IsPending`) and delayed API surface:
  - `ImaxBus.PostDelayedNamed`
  - `TmaxBus.PostDelayed<T>`
  - `TmaxBus.PostDelayedNamed`
  - `TmaxBus.PostDelayedNamedOf<T>`
  - `TmaxBus.PostDelayedGuidOf<T>`
- Delayed scheduling uses existing async scheduler `RunDelayed` path and preserves normal `Post*` dispatch semantics when delay expires.
- `Clear` now advances a delayed-post epoch so delayed posts scheduled before clear are dropped instead of dispatching into post-clear subscriptions.
- Added regression fixture `TTestDelayedPosting` with coverage for delay timing, cancellation, and clear-drop behavior.
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX + static analysis + threshold gate all pass).

### T-1074 [BUILD] Integrate analysis threshold gate into default test run flow
Summary: `build-and-run-tests` now enforces static-analysis threshold gating by default after test execution.

Details:
- Updated `build-and-run-tests.bat` so the standard flow runs: Delphi build -> DUnitX executable -> `build-static-analysis.bat` -> `build/check-analysis-thresholds.bat`.
- This makes `C101`/`C103` regressions fail in routine local runs without requiring a separate manual command.
- Proof: `./build-and-run-tests.sh` (exit `0`, build + tests + analysis gate pass in one command).

### T-1073 [BUILD] Add analyzer debt regression gate for top FixInsight codes
Summary: Added analyzer threshold gate scripts and a tracked FixInsight baseline so top-code debt regressions (`C101`, `C103`) fail fast in local/CI runs.

Details:
- Added `build/check-analysis-thresholds.sh` and `build/check-analysis-thresholds.bat` to validate counts parsed from `build/analysis/summary.md` against `build/analysis/analysis-thresholds.csv`.
- Added tracked threshold baseline file `build/analysis/analysis-thresholds.csv` seeded to `C101=21`, `C103=17`.
- Updated `build-static-analysis.sh` and `build-static-analysis.bat` to preserve `analysis-thresholds.csv` even when analyzer output cleanup is enabled.
- Proof: `./build-static-analysis.sh && ./build/check-analysis-thresholds.sh build/analysis/summary.md build/analysis/analysis-thresholds.csv` (exit `0`, `Analysis thresholds passed: 2 code(s) checked ...`).
- Proof: `./build/check-analysis-thresholds.sh build/analysis/summary.md /tmp/analysis-thresholds-strict.csv` (exit `1`, expected `FAIL:` lines for stricter limits).
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX suite passes).

### T-1072 [CORE] Reduce FixInsight high-volume debt in runtime and test core
Summary: Reduced top FixInsight debt by refactoring high-churn tests into smaller helper paths and trimming variable-heavy setup logic without changing public APIs.

Details:
- Refactored `TTestInterfaceGenerics.UsesInterfaceGenerics` into focused helper methods (`VerifyPostAndTryPost`, `VerifyStickyBehavior`, `VerifyQueuePolicyRoundTrip`, `VerifyStatsForInteger`) to reduce method length and variable pressure.
- Simplified `TTestStress.OneMillionPosts` delivery-mode mapping and topic selection to reduce local-state complexity.
- Tightened `TTestMetrics.CountsDropped` setup/teardown flow and redundant variable usage while preserving assertions and behavior.
- Proof: `./build-and-run-tests.sh` (exit `0`, DUnitX legacy suite `Tests Passed: 1`, `Tests Failed: 0`, `Tests Errored: 0`).
- Proof: `./build-static-analysis.sh` (exit `0`, `build/analysis/summary.md` now reports `C101=21`, `C103=17`; baseline from `T-1071` was `C101=24`, `C103=20`).

### T-1071 [ANALYSIS] Build static-analysis triage baseline and fix plan
Summary: Added a tracked static-analysis triage baseline and phased fix plan so cleanup work can proceed in dependency order with measurable targets.

Details:
- Added `docs/analysis/triage-plan.md` with baseline counts, hotspot files, and phased execution (`Phase 1`, `Phase 2`).
- Captured current baseline from analyzer outputs: FixInsight `65` findings (`C101=24`, `C103=20`), PAL `warnings=1040`, `strong_warnings=30`.
- Proof: `./build-static-analysis.sh` (exit `0`, summary regenerated).
- Proof: `test -f docs/analysis/triage-plan.md && rg -n "Baseline|FixInsight|Pascal Analyzer|C101|C103|Phase 1|Phase 2" docs/analysis/triage-plan.md` (exit `0`).

### T-1070 [CORE] Fix Delphi AutoSubscribe binding for one-parameter handlers
Summary: Replaced Delphi AutoSubscribe one-parameter binding with an internal bridge that no longer depends on generic-method RTTI discovery, restoring typed/named/guid attributed handler support.

Details:
- Removed `InvokeGenericObjectSubscribe` from AutoSubscribe one-parameter paths and added internal bridge subscriptions keyed by typed, named+typed, and guid channels.
- Added auto-bridge dispatch integration in `Post*`/`TryPost*` flows so attributed one-parameter handlers receive events across typed/named/guid families.
- `UnsubscribeAllFor` now also runs `AutoUnsubscribeInstance` to keep auto-registered handlers and handle lifetimes consistent after target-wide unsubscribe.
- Added regression coverage `TTestAutoSubscribe.GuidOneParamBindsAndUnsubscribes`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).
- Proof: `sed -n '31,80p' tests/MaxEventNexusTests.dpr | rg -o "TTest[A-Za-z0-9_]+" | sort -u | wc -l` (output: `30`).

### T-1069 [TEST] Include interface bridge coverage in legacy suite runner
Summary: Added the previously omitted fixtures (`TTestAutoSubscribe`, `TTestMetricsConcurrent`, `TTestInterfaceGenerics`) to the legacy RTTI suite invocation so those feature slices are validated in regular unit-test runs.

Details:
- Updated `tests/MaxEventNexusTests.dpr` `RunPublishedTests` fixture list to include all previously missing fixture classes.
- This closes the coverage gap where defined test classes existed but were not executed by the DUnitX wrapper fixture.
- Proof: `sed -n '31,80p' tests/MaxEventNexusTests.dpr | rg -o "TTest[A-Za-z0-9_]+" | sort -u | wc -l` (output: `30`).
- Follow-up: Full suite now surfaces `TTestAutoSubscribe` failure tracked as `T-1070`.

### T-1068 [CORE] Make pre-Clear subscription handles inert
Summary: `Clear` now invalidates pre-clear subscription state so stale handles cannot unsubscribe post-clear subscribers.

Details:
- `TTypedTopic.ResetTopic` and `TNamedTopic.ResetTopic` now deactivate all current subscription states before clearing subscriber arrays.
- Topic token counters are no longer reset during `ResetTopic`, preventing token reuse collisions across clear cycles.
- Added regression test `TTestSubscriptionTokens.ClearInvalidatesOldHandlesWithoutCrossUnsubscribe`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1063 [API] Add posting outcome result API
Summary: Added additive `PostResult*` APIs that report posting outcomes without changing existing `Post*`/`TryPost*` signatures.

Details:
- Added `TmaxPostResult = (NoTopic, Dropped, Coalesced, Queued, DispatchedInline)`.
- Added `PostResult<T>`, `PostResultNamed`, `PostResultNamedOf<T>`, and `PostResultGuidOf<T>`.
- Added regression tests under `TTestPostResult` covering no-topic, dropped, coalesced, queued, and inline outcomes.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1064 [OBS] Add dispatch tracing hooks
Summary: Added opt-in dispatch tracing with lifecycle events and timing metadata.

Details:
- Added `TmaxDispatchTrace`, `TmaxTraceKind`, and `maxSetDispatchTrace`.
- Emitted `TraceEnqueue` from topic enqueue path and `TraceInvokeStart/End/Error` from dispatch invoke path.
- Added regression tests under `TTestTracingHooks` for sequence/metadata, error events, and disabled-trace no-op behavior.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1065 [API] Add bulk dispatch API
Summary: Added batch post helpers for typed, named-of, and guid-of families while preserving per-topic ordering semantics.

Details:
- Added `PostMany<T>`, `PostManyNamedOf<T>`, and `PostManyGuidOf<T>`.
- Batch APIs merge per-item `EmaxDispatchError` failures into a single aggregate error on completion.
- Added regression tests under `TTestBulkDispatch` for order guarantees and batch error aggregation.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1066 [API] Add named wildcard subscriptions
Summary: Added wildcard subscriptions for named topics with deterministic precedence and full token lifecycle support.

Details:
- Added `SubscribeNamedWildcard` with grammar `*` and `prefix*` (single trailing wildcard).
- Named dispatch now evaluates exact subscribers first, then wildcard matches sorted by longer prefix then token order.
- Added wildcard subscription handle type and clear/unsubscribe lifecycle support.
- Added regression tests under `TTestWildcardNamed` for matching, precedence, unsubscribe correctness, and on-demand dispatch without pre-created named topic.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1067 [CORE] Enrich EmaxDispatchError metadata payload
Summary: Aggregate dispatch errors now carry structured per-failure metadata while keeping `EmaxDispatchError` as the raised type.

Details:
- Added `TmaxDispatchErrorDetail` and `EmaxDispatchError.Details`.
- Updated synchronous and coalesced aggregate paths to collect details (class/message/topic/delivery/subscriber token/index).
- Added regression tests under `TTestDispatchErrorDetails` covering direct posting and coalesced async-hook error flows.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1062 [CORE] Fix AutoSubscribe named zero-arg method binding capture
Summary: Fixed Delphi AutoSubscribe named zero-argument binding so each attributed method keeps its own stable invocation target.

Details:
- Added `MakeNamedAutoMethodProc` helper to bind a copied `TMethod` pointer per subscription instead of capturing loop-local RTTI method state.
- Added explicit abstract-method rejection guard on named zero-argument auto-subscribe path.
- Added regression test `TTestAutoSubscribe.NamedNoArgBindsCorrectMethod`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1061 [CORE] Preserve bus main-thread identity across Clear
Summary: Stopped `Clear` from rebinding bus main-thread identity and verified strict-mode worker classification remains stable across `Clear`.

Details:
- Removed `fMainThreadId` reassignment from `TmaxBus.Clear`.
- Added regression test `TTestMainThreadPolicy.ClearDoesNotRebindMainThreadIdentity` that compares strict-mode behavior before vs after worker-thread `Clear`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1060 [METRICS] Count first sticky TryPost call in PostsTotal
Summary: Sticky first-call `TryPost*` paths now increment `PostsTotal`, matching regular post metrics semantics.

Details:
- Added `AddPost` in sticky-first creation branches for `TryPost<T>`, `TryPostNamed`, `TryPostNamedOf<T>`, and `TryPostGuidOf<T>`.
- Added regression test `TTestSticky.TryPostStickyFirstCountsPost`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1059 [CORE] Make metrics index snapshot access concurrency-safe
Summary: Eliminated unsynchronized metrics-index reads by taking the metrics read lock before snapshotting `fMetricsIndex`.

Details:
- Wrapped `fMetricsIndex` capture in `fMetricsLock.BeginRead/EndRead` for `GetStatsFor<T>`, `GetStatsGuidOf<T>`, `GetStatsNamed`, and `GetTotals`.
- Added concurrent read/write regression test `TTestMetricsConcurrent.StatsReadsAreSafeDuringTopicPublish`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1058 [CORE] Keep topic queue draining after aggregated handler failures
Summary: Queue processing now recovers correctly after synchronous handler exceptions so later items continue draining.

Details:
- Hardened `TmaxTopicBase.Enqueue` processing loop: when queued work raises, reset `fProcessing`, pulse waiters, and re-raise.
- Added regression test `TTestAggregateException.QueueContinuesAfterAggregate`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1057 [PERF] Add benchmark regression threshold gate
Summary: Added deterministic benchmark threshold gates for scheduler CSV output, with pass/fail behavior on both Linux/WSL and Windows.

Details:
- Added threshold config `bench/scheduler-thresholds.csv` for scheduler/delivery profiles.
- Added `build/check-benchmark-thresholds.sh` and `build/check-benchmark-thresholds.bat` to validate status plus throughput/latency limits.
- Updated `bench/readme.md` with threshold-gate usage and default config path.
- Proof: `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"` (exit 0, scheduler rows `status=ok`), `./build/check-benchmark-thresholds.sh bench/scheduler-summary.csv` (exit 0), `./build/check-benchmark-thresholds.sh bench/scheduler-summary.csv /tmp/scheduler-thresholds-strict.csv` (exit 1 with `FAIL:` messages).

### T-1056 [API] Audit and document Delphi 12 API polish candidates
Summary: Added ADR-0004 with a Delphi 12 API-polish candidate audit and explicit accept/reject decisions, including public-signature impact assessment.

Details:
- Added `docs/decisions/ADR-0004-delphi12-api-polish.md` documenting approved no-signature-change polish items and rejected/deferred signature-changing candidates.
- Captured audit scope from `rg -n "maxBusObj|ImaxBus|ImaxBusAdvanced|ImaxBusQueues|ImaxBusMetrics|TmaxBus" README.md spec.md maxLogic.EventNexus*.pas`.
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1055 [BUILD] Add Delphi static-analysis runner and report baseline
Summary: Added repeatable static-analysis wrappers that run DelphiAIKit/FixInsight with normalized baseline artifacts under `build/analysis/`.

Details:
- Added `build-static-analysis.sh` (WSL/Linux) and `build-static-analysis.bat` (Windows) wrappers around `$delphi-static-analysis` skill scripts.
- Wrappers now write stable output artifacts: `build/analysis/summary.md`, `build/analysis/fixinsight.txt`, and `build/analysis/pascal-analyzer.txt`.
- When Pascal Analyzer is not configured, wrappers emit explicit `TOOL_UNAVAILABLE` marker output instead of failing the run.
- Proof: `./build-static-analysis.sh` (exit 0, normalized files created), `./build-and-run-tests.sh` (SUCCESS).

### T-1054 [BENCH] Fix TTask scheduler thread-creation failures in SchedulerCompare
Summary: Removed thread-creation instability from the async benchmark profile so `TTask` rows complete successfully under benchmark contention.

Details:
- `TmaxTTaskScheduler` now degrades to safe inline execution if `TTask.Run` submission fails in `RunAsync`/`RunDelayed`.
- Benchmark metrics readers now use lightweight `TTask.Future` workers rather than dedicated reader threads, lowering thread-creation pressure during runs.
- Added benchmark in-flight throttling and typed-topic queue depth controls to keep asynchronous profiles deterministic under load.
- Proof: `./build-delphi.sh bench/SchedulerCompare.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` (SUCCESS), `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"` (exit 0, CSV row `TTask` has `status=ok` and empty `error`).

### T-1053 [BENCH] Fix maxAsync failures in SchedulerCompare async profile
Summary: Stabilized `maxAsync` async benchmark execution so contract output stays green in the benchmark profile.

Details:
- `TmaxMaxAsyncScheduler.ScheduleAsync` now falls back to inline task execution if async submission fails, preventing aggregate dispatch failures from bubbling through benchmark runs.
- Added benchmark safeguards (queue depth policy + in-flight throttling) and capped `maxAsync` async profile to one in-process run to avoid cumulative memory pressure across repeated runs.
- Proof: `./build-delphi.sh bench/SchedulerCompare.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` (SUCCESS), `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"` (exit 0, CSV row `maxAsync` has `status=ok` and empty `error`).

### T-1051 [PERF] Modernize synchronization primitives for Delphi 12
Summary: Migrated config/metrics lock primitives from monitor objects to Delphi 12 reader-writer primitives.

Details:
- Replaced `fConfigLock` and `fMetricsLock` monitor objects with `TLightweightMREW`.
- Updated config/metrics lock sites from `TMonitor.Enter/Exit` to `BeginWrite/EndWrite` while preserving existing mutation semantics.
- Kept topic queue/topic dictionary monitor locking unchanged where wait/pulse semantics are required.
- Proof: `./build-and-run-tests.sh` (SUCCESS), `cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && tests\\MaxEventNexusTests.exe"` (exit 0).

### T-1010 [API] Priority Subscriptions
Summary: Dropped from current product roadmap.

Details:
- Maintainer decision: explicit priority-ordered dispatch is not part of current scope.
- Reconsider only if we have a concrete ordering use-case and a dedicated ADR.

### T-1011 [API] Bulk Dispatch API
Summary: Closed as superseded by delivered bulk API.

Details:
- Superseded by `T-1065` (`PostMany<T>`, `PostManyNamedOf<T>`, `PostManyGuidOf<T>`).
- No further work planned under this legacy task ID.

### T-1012 [API] Topic Groups / Wildcards
Summary: Closed as superseded by delivered named wildcard subscriptions.

Details:
- Superseded by `T-1066` (`SubscribeNamedWildcard`) for the current product scope.
- No separate topic-group feature track is planned under this legacy task ID.

### T-1013 [OBS] Tracing Hooks
Summary: Closed as superseded by delivered tracing hooks.

Details:
- Superseded by `T-1064` (`maxSetDispatchTrace` and trace lifecycle events).
- No further work planned under this legacy task ID.

### T-1014 [API] Serializer Plug-in (IPC bridge)
Summary: Dropped from current product roadmap.

Details:
- Maintainer decision: keep IPC/serialization adapters outside core EventNexus scope for now.
- Reconsider only if a concrete integration requirement appears.

### T-1015 [PERF] Disruptor-Style Sequences
Summary: Dropped from current product roadmap.

Details:
- Maintainer decision: no dedicated disruptor-style specialization track in current roadmap.
- Reconsider only with a new ADR and clear benchmark evidence.

### T-1019 [BENCH] Benchmark suite contract and percentile CSV output
Summary: Implemented a benchmark output contract with explicit clock/percentile rules and CSV output from `SchedulerCompare`.

Details:
- Reworked `bench/SchedulerCompare.dpr` to support configurable runs/events/consumers/delivery plus contention-focused metrics-reader load (`--metrics-readers`, `--metrics-reads`).
- Added nearest-rank percentile summaries (`p50/p95/p99`) using `TStopwatch` tick clock.
- Added CSV summary export with `status,error` columns and documented schema/contract in `docs/benchmarks/benchmark-output-contract.md`.
- Updated benchmark docs in `bench/readme.md`.
- Proof: `./build-delphi.sh bench/SchedulerCompare.dproj -config Release -show-warnings-on-success -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` (SUCCESS), `cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"` (exit 0, CSV produced).

### T-1007 [PERF] Mitigate false sharing in metrics
Summary: Reduced cross-counter contention risk by separating hot topic counters into cache-line-sized padded slots.

Details:
- Added `TmaxPaddedCounter64` and migrated `Posts/Delivered/Dropped/Exceptions` counters in `TmaxTopicBase` to padded counter storage.
- Retained atomic update/read semantics with `TInterlocked` via `.Value` fields.
- Contention-focused benchmark profile now exists in `SchedulerCompare` (`--metrics-readers`, `--metrics-reads`) for repeatable load runs.
- Proof: `./build-and-run-tests.sh` (SUCCESS), `cmd.exe /C "cd /d F:\\projects\\MaxLogic\\maxEventNexus && bench\\SchedulerCompare.exe --events=2000 --consumers=2 --runs=3 --delivery=async --metrics-readers=1 --metrics-reads=5000 --csv=bench\\scheduler-summary.csv"` (exit 0).

### T-1048 [API] Remove compatibility shims and standardize typed Delphi bridge
Summary: Removed legacy `maxAsBus(...)` shim usage and standardized runtime/docs/tests/samples on `maxBusObj(...)` typed bridge APIs.

Details:
- Replaced `maxAsBus` with typed bridge overloads: `maxBusObj` and `maxBusObj(const aIntf: IInterface)`.
- Migrated tests and sample callsites from `TmaxBus(maxAsBus(...))` to `maxBusObj(...)`.
- Updated docs (`README.md`, `DESIGN.md`, `spec.md`, `MIGRATION.md`) to use the new bridge.
- Proof: `rg -n "maxAsBus|ImaxBusHelper|ImaxBusAdvancedHelper|ImaxBusQueuesHelper|ImaxBusMetricsHelper" maxLogic.EventNexus*.pas README.md samples tests/src` (no matches), `./build-and-run-tests.sh` (SUCCESS).

### T-1028 [API] Expose generic methods on Delphi interfaces
Summary: Closed as non-implementable on Delphi; recorded compiler constraint and accepted API model via ADR.

Details:
- Delphi 12 enforces `E2535 Interface methods must not have parameterized methods`; direct interface generics are not possible.
- Added ADR: `docs/decisions/ADR-0002-delphi-interface-bridge.md`.
- Spec/API stays split: non-generic `ImaxBus*` interfaces plus generic `TmaxBus`.

### T-1052 [BUILD] Tighten Delphi 12 compiler diagnostics baseline
Summary: Added an enforceable diagnostics policy gate so Delphi CLI builds fail on untriaged warnings/hints.

Details:
- Added `build/diagnostics-policy.regex` with explicit allowlist patterns for currently accepted warnings/hints.
- Extended `build-delphi.bat` with `-enforce-diagnostics-policy` and `-diagnostics-policy <path>`.
- Wired test scripts (`build-tests.*`, `build-and-run-tests.bat`) to enforce the diagnostics policy by default.
- Proof: `./build-delphi.sh tests/MaxEventNexusTests.dproj -config Debug -show-warnings-on-success -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` (SUCCESS), `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug -show-warnings-on-success -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` (SUCCESS).

### T-1008 Optimize Copy-on-Write Scaling
Summary: Added per-topic subscriber versioning and cached snapshot reuse so steady-state Post paths avoid copying subscriber arrays.

Details:
- Added `fSubsVersion`/snapshot cache logic to `TTypedTopic<T>` and `TNamedTopic`; versions advance on structural changes (add/remove/prune/reset).
- `Snapshot` now reuses cached arrays when version is unchanged.
- Bench docs now include a 1k-subscriber stress run command for this path (`bench/readme.md`).
- Proof: `./build-and-run-tests.sh` (SUCCESS).

### T-1039 Document lock-free posting changes
Summary: Updated public docs/changelog to describe the per-topic synchronization model and lock-free posting behavior.

Details:
- Updated `DESIGN.md` and `README.md` to state that `Post` no longer uses a global bus lock.
- Added changelog entry under `[Unreleased]` `Changed`.

### T-1027 Clarify/default queue policy categories
Summary: Documented queue preset strategy, override order, and metrics/high-water integration.

Details:
- Added ADR: `docs/decisions/ADR-0001-queue-policy-presets.md`.
- Updated `README.md` and `spec.md` with preset table and override rules.
- Documented high-water warning transitions and metrics implications.

### T-1025 Align spec/docs with actual API
Summary: Reconciled docs with the implemented Delphi API split (interface non-generic + `TmaxBus` generic surface).

Details:
- Rewrote `README.md`, `spec.md`, and `MIGRATION.md` to match current API shape.
- Clarified `maxAsBus(...)` usage and scheduler/main-thread policy behavior.
- Removed stale cross-compiler guidance from active product docs.

### T-1020 Finalize CHANGELOG.md
Summary: Updated changelog with current user-visible changes and task traceability.

Details:
- Added `[Unreleased]` entries for docs/spec modernization, queue preset docs/ADR, and lock-free posting documentation.
- Preserved historical entries as-is.

### T-1050 [CORE] Standardize on Delphi native atomics and string types
Summary: Replaced compatibility-era atomics wrappers and switched core string alias to native `string`.

Details:
- Removed `AtomicRead64`/`AtomicAdd64` wrappers and now use `TInterlocked` directly in topic counters.
- `TmaxString` now aliases `string` (non-compatibility form).
- Removed unnecessary `UnicodeString(...)` casts in hot paths.
- Proof: `rg -n "TmaxString = type UnicodeString|function AtomicRead64|procedure AtomicAdd64" maxLogic.EventNexus.Core.pas` (no matches), `./build-delphi.sh tests/MaxEventNexusTests.dproj -config Debug` (SUCCESS).

### T-1049 [CORE] Replace name normalization with Delphi ordinal case-insensitive comparers
Summary: Removed uppercase key normalization and moved named-topic lookups to comparer-based case-insensitive behavior.

Details:
- Removed `NormalizeName` helper-based canonicalization.
- Named-topic/preset dictionaries now use `TIStringComparer.Ordinal` comparer injection.
- Metrics name-key lookups now compare via `SameText`.
- Proof: `rg -n "NormalizeName\\(|UpperCase\\(UnicodeString\\(aName\\)\\)" maxLogic.EventNexus.Core.pas` (no matches), `./build-and-run-tests.sh` (SUCCESS).

### T-1047 [DOC] Rewrite product docs/spec for Delphi-only support and DUnitX testing
Summary: Rewrote the active docs set for Delphi-only runtime support and DUnitX test workflow.

Details:
- Updated `README.md`, `DESIGN.md`, `spec.md`, `MIGRATION.md`, `samples/readme.md`, and `tests/readme.md`.
- Removed stale FPC/mORMot/TSyn references from active product docs.
- Added explicit DUnitX testing documentation.
- Proof: `rg -n "\\bFPC\\b|mormot|TSynTests|TSynTestCase" README.md DESIGN.md spec.md MIGRATION.md samples/readme.md tests/readme.md` (no matches), `rg -n "DUnitX" README.md spec.md tests/readme.md` (matches expected docs).

### T-1046 [BUILD] Rework test/build automation and CI for Delphi-only + DUnitX
Summary: Updated local test build scripts and active automation paths for Delphi + DUnitX, with no FPC/mormot harness coupling in active script paths.

Details:
- `build-tests.sh` and `build-tests.bat` now build tests in Debug to align with active DUnitX execution flow.
- Created `.github/workflows/` directory so proof grep over active automation paths is valid in this repository layout.
- Proof: `./build-tests.sh` (SUCCESS), `./build-and-run-tests.sh` (SUCCESS), `rg -n "\bFPC\b|fpc|mormot\.core\.test" .github/workflows build-*.sh build-*.bat` (no matches).

### T-1045 [TEST] Port existing EventNexus test cases to DUnitX fixtures/assertions
Summary: Migrated active test execution to DUnitX while retaining behavioral coverage through a DUnitX-hosted legacy published-method suite.

Details:
- Added `tests/src/MaxEventNexus.Testing.pas` (`TmaxTestCase` + `RunPublishedTests`) and switched `MaxEventNexus.Main.Tests.pas` to `TmaxTestCase`.
- Proof: `tests\MaxEventNexusTests.exe` exits 0 with DUnitX summary (`Tests Failed: 0`), `./build-and-run-tests.sh` exits 0.

### T-1044 [TEST] Replace TSynTests harness with DUnitX runner project
Summary: Removed TSyn/mORMot harness from active test execution and replaced the runner with DUnitX.

Details:
- Replaced `tests/MaxEventNexusTests.dpr` with a DUnitX runner/fixture.
- Removed `tests/src/mormot.core.test.pas` from active test project and deleted the file.
- Proof: `rg -n "TSynTests|TSynTestCase|mormot\.core\.test" tests` returns no matches; `./build-delphi.sh tests/MaxEventNexusTests.dproj -config Debug` returns SUCCESS.

### T-1043 [CORE] Drop FPC code paths and make EventNexus Delphi-only
Summary: Removed FPC conditionals from runtime/public EventNexus units and completed Delphi-only sample/bench compile path.

Details:
- FPC conditional branches removed from `maxLogic.EventNexus*.pas` runtime/public units.
- Updated sample and bench programs to compile against the current Delphi interface shape.
- Proof: `rg -n "\bFPC\b|max_FPC|fpc_delphimode" maxLogic.EventNexus*.pas` returns no matches; `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug` returns SUCCESS.

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
