# EventNexus Bus Changelog

## [Unreleased]

### Changed
- Shipped scheduler adapters (`MaxAsync`, `TTask`, `RawThread`) now share one positive-delay conversion rule: negative clamps to `0`, `0` stays immediate-eligible, and `1..999us` rounds up instead of collapsing inline on some backends. (T-1097)
- Documented intentional `SubscribeStrong*` APIs plus their caller-owned lifetime contract in the spec, README, design notes, and migration guide. (T-1094)
- Clarified delayed/coalescing timing as best-effort rather than exact microsecond wake-up precision, while explicitly requiring positive delays to remain delayed. (T-1095, T-1088)
- Expanded DUnitX coverage for delayed named-of/guid posting, GUID queue-preset precedence, and `PostResult` named-of/guid paths. (T-1081)
- Expanded `TTestPostResult` with GUID queue-pressure assertions for `PostResultGuidOf<T>` (`Queued` and `Dropped` outcomes). (T-1084)
- Added lightweight API coverage proxy reporting with numeric target enforcement (`build/report-api-test-coverage.*`, target file, and default test-flow gate). (T-1084)
- Deferred typed, named-of, and guid-of ordering now serializes same-topic deferred batches inside the bus, with deterministic reorder-scheduler coverage for direct `Post*` and `PostMany*` paths. (T-1091)
- Supported samples now use the Delphi bridge contract (`TmaxBus` / `maxBusObj(...)`) and the sample docs explicitly document Delphi-only generic API usage. (T-1093)
- `bench/SchedulerCompare` now emits cross-library comparison rows (`framework-compare`) for `EventNexus(TTask)`, `iPub`, and `EventHorizon` in the same CSV contract as scheduler rows. (T-1082)
- Benchmark threshold gates now validate only `scheduler-compare` rows, so cross-library rows can coexist without breaking scheduler regression checks. (T-1082)
- Scheduler benchmark project search paths now include `reference/` so iPub/EventHorizon comparison units build in CLI workflows. (T-1082)

### Fixed
- `DefaultAsync` fallback initialization is now synchronized, and the test suite includes a fresh-process race probe to prove concurrent first access still yields a single fallback scheduler instance. (T-1085)
- Delayed `Post*` execution now forwards post-time `EmaxDispatchError` / handler exceptions through the async error hook in both the normal delayed path and the delayed-submission fallback thread. (T-1096)
- `maxAsync` now preserves async/delayed semantics when enqueue or delayed submission fails by falling back to dedicated-thread execution before any final inline safety net, with deterministic scheduler fault-injection coverage. (T-1086)
- Inline `Main` dispatch on the main thread, console `DegradeToPosting`, and inline worker-thread `Background` now re-raise synchronous handler failures as `EmaxDispatchError` while still forwarding the async hook. (T-1089)
- `AutoSubscribe` now rejects attributed class methods, constructors, destructors, repeated attributes, and abstract methods instead of silently skipping invalid bindings. (T-1090)
- Delayed post fallback no longer executes immediately when delayed scheduler submission fails, and delayed handles now invalidate correctly across `Cancel` / `Clear` boundaries. (T-1092)

## [1.1.0] - 2026-02-26

### Added
- `tests/src/MaxEventNexus.Testing.pas` with a DUnitX-backed `TmaxTestCase` compatibility layer and RTTI published-method suite runner. (T-1044, T-1045)
- Added posting outcome APIs `PostResult<T>`, `PostResultNamed`, `PostResultNamedOf<T>`, and `PostResultGuidOf<T>` returning `TmaxPostResult`. (T-1063)
- Added dispatch tracing surface `maxSetDispatchTrace` with `TmaxDispatchTrace` events (`TraceEnqueue`, `TraceInvokeStart`, `TraceInvokeEnd`, `TraceInvokeError`). (T-1064)
- Added bulk dispatch helpers `PostMany<T>`, `PostManyNamedOf<T>`, and `PostManyGuidOf<T>`. (T-1065)
- Added named wildcard subscriptions via `SubscribeNamedWildcard` with deterministic precedence (`exact`, then longer-prefix wildcard, then token order). (T-1066)
- Added structured aggregate error metadata via `EmaxDispatchError.Details` / `TmaxDispatchErrorDetail`. (T-1067)
- Added delayed posting APIs (`PostDelayed<T>`, `PostDelayedNamed`, `PostDelayedNamedOf<T>`, `PostDelayedGuidOf<T>`) with cancellable handle `ImaxDelayedPost`. (T-1076)
- Added regression suites `TTestPostResult`, `TTestTracingHooks`, `TTestBulkDispatch`, `TTestWildcardNamed`, and `TTestDispatchErrorDetails`. (T-1063..T-1067)
- Added delayed-posting hardening coverage for zero-delay metrics/cancel semantics and deterministic long-delay pending/cancel lifecycle assertions. (T-1077)

### Changed
- Runtime units are now Delphi-only (FPC conditionals removed from `maxLogic.EventNexus*` public/runtime paths) and the full group project builds in Debug with updated samples/bench wiring. (T-1043)
- Test runner switched from `TSynTests` to DUnitX (`tests/MaxEventNexusTests.dpr`), with existing behavioral coverage executed through the DUnitX fixture. (T-1044, T-1045)
- Legacy suite runner now includes all previously omitted fixtures (`TTestAutoSubscribe`, `TTestMetricsConcurrent`, `TTestInterfaceGenerics`), expanding regular unit-test coverage. (T-1069)
- Test build scripts now target Delphi Debug explicitly (`build-tests.sh` / `build-tests.bat`) to match the DUnitX harness path used by CI/local runs. (T-1046)
- Rewrote README, design, migration, and spec docs for Delphi-only support and DUnitX workflows; removed stale cross-compiler guidance from active docs. (T-1047, T-1025)
- Documented queue preset category defaults/override behavior plus high-water metric signaling in the public docs/spec. (T-1027)
- Documented that `Post` no longer uses a global bus lock and clarified per-topic synchronization strategy. (T-1039)
- Named-topic keys now use comparer-driven case-insensitive lookups (no uppercase normalization helper in hot paths). (T-1049)
- Core topic counters now use native `TInterlocked` operations directly, and core string handling uses Delphi-native `string` aliasing. (T-1050)
- Typed/named topic snapshots now use versioned cache reuse to avoid repeated subscriber-array copies when no structural mutations occur. (T-1008)
- Added diagnostics-policy enforcement in `build-delphi.bat` with regex allowlist (`build/diagnostics-policy.regex`); test scripts now fail on untriaged warnings/hints. (T-1052)
- Added `build-static-analysis.sh` / `build-static-analysis.bat` wrappers to run Delphi static-analysis baselines via DelphiAIKit/FixInsight and normalize outputs under `build/analysis/` (with explicit tool-unavailable markers when needed). (T-1055)
- Reduced FixInsight top-code debt in the core test suite by refactoring long/variable-heavy coverage paths (`C101/C103` baseline `24/20` to `21/17`) without public API changes. (T-1072)
- Continued FixInsight debt reduction in high-density test fixtures and tightened tracked thresholds to `C101=20`, `C103=14`. (T-1075)
- Reduced test-local `O804` static-analysis debt in high-density fixtures; remaining `C102/O804` findings are now isolated to shared foundation `maxlogic.strutils`. (T-1078)
- Reduced shared foundation `C102/O804` static-analysis debt in `maxlogic.strutils` using compatibility-safe suppressions and cleanup, without public API signature changes. (T-1079)
- Cleared additional non-noise FixInsight warnings across tests/foundation units (`W519`, `W528`, `W505`), while keeping API compatibility and analyzer thresholds green. (T-1080)
- Cleared remaining actionable FixInsight warnings (`C110`, `W515`, `W524`) in `maxAsync` with compatibility-safe fixes/suppressions and no behavior regressions. (T-1083)
- Added analyzer-threshold gate scripts (`build/check-analysis-thresholds.sh` + `.bat`) with tracked FixInsight limits (`build/analysis/analysis-thresholds.csv`) to fail on `C101`/`C103` regressions. (T-1073)
- Default test-run entrypoints now include analyzer gating (`build-and-run-tests.bat` runs static analysis + `check-analysis-thresholds` after DUnitX execution). (T-1074)
- Added ADR-0004 with Delphi 12 API-polish accept/reject decisions and explicit public-signature impact guardrails for Phase 2 work. (T-1056)
- Added benchmark threshold gates (`build/check-benchmark-thresholds.sh` + `.bat`) with scheduler profile limits from `bench/scheduler-thresholds.csv` to fail CI/local runs on latency/throughput regressions. (T-1057)
- Replaced legacy `maxAsBus(...)` shim with typed bridge overloads `maxBusObj` / `maxBusObj(aIntf)` and migrated runtime docs/tests/samples accordingly. (T-1048)
- Scheduler benchmark now has a documented output contract (clock source + nearest-rank percentiles + CSV schema/status columns) and supports contention-focused metrics-reader load profiles. (T-1019)
- Async benchmark harness now applies bounded queue/in-flight guards, uses `TTask.Future` metrics readers, and caps `maxAsync` to one in-process async run to avoid cumulative memory-pressure failures during scheduler comparisons. (T-1053, T-1054)
- Topic metric counters now use padded counter slots to reduce cross-counter cache-line contention under concurrent posting. (T-1007)
- Extension backlog governance moved to explicit ADR control: initial freeze via ADR-0003, partial unfreeze for delivered items (`T-1063..T-1067`), and roadmap drop for remaining legacy extension tasks (`T-1010`, `T-1014`, `T-1015`). (T-1010..T-1015, T-1063..T-1067)
- Config/metrics lock primitives are now Delphi 12 `TLightweightMREW`-based instead of monitor objects, preserving existing mutation semantics while modernizing lock infrastructure. (T-1051)
- Clarified spec behavior for coalesced delivery exception surfacing and scoped high-water warning thresholds to unbounded queues (`MaxDepth = 0`). (T-1058..T-1062)
- Refined spec contracts for `TryPost*`, `Clear`, AutoSubscribe, and coalescing edge behavior; extension backlog items 1-5 were unfrozen and reactivated (`T-1063..T-1067`). (T-1063..T-1068)

### Fixed
- Sample and benchmark programs now call generic bus APIs through `maxBusObj(...)` typed bridge helpers so they compile against the current Delphi interface surface. (T-1043, T-1048)
- `TmaxMaxAsyncScheduler` and `TmaxTTaskScheduler` now degrade to inline execution if async task submission fails, preventing benchmark-profile dispatch failures from transient thread/scheduler allocation errors. (T-1053, T-1054)
- Topic queue processing now resets `fProcessing` and wakes waiters when synchronous handler dispatch raises, preventing stalled queues after aggregate failures. (T-1058)
- Metrics-index snapshots are now read under the metrics read lock in `GetTotals`/`GetStats*`, removing concurrent read/write races. (T-1059)
- Sticky first-call `TryPost*` paths now increment `PostsTotal` (`TryPost<T>`, named, named-of, guid-of), matching metrics semantics in all posting paths. (T-1060)
- `Clear` no longer rebinds bus main-thread identity; strict main-thread policy behavior now remains stable across clear cycles. (T-1061)
- AutoSubscribe named zero-argument handlers now bind per-method pointers safely instead of capturing loop-local RTTI method state. (T-1062)
- Delphi AutoSubscribe one-parameter handlers now bind for typed/named/guid attributed methods without generic-method RTTI lookup, removing `SubscribeNamedOf` binding failures. (T-1070)
- Pre-`Clear` subscription handles are now inert: `Clear` deactivates subscription states and avoids token reuse collisions across clear cycles. (T-1068)

## [1.0.0] - 2025-12-15

### Added
- DESIGN.md detailing topics, queues, sticky cache, coalescer, and metrics architecture. (spec.md#1.1-goals)
- Unit test for subscription churn and per-topic ordering. (spec.md#15-testing-matrix)
- Unit test verifying sticky events deliver last value to late subscribers. (spec.md#8-sticky)
- Unit test validating coalesced events deliver latest value per key. (spec.md#8-coalescing)
- Unit test ensuring zero-window coalescing batches sequential posts and delivers only the last value. (spec.md#8-coalescing)
- Unit test confirming queue overflow policies drop or block according to configured behavior. (spec.md#8.7-back-pressure--bounded-queues)
- Metrics counters now track posts, deliveries, drops, and exceptions with tests covering each. (spec.md#11-error-semantics)
- Fuzz test spawns concurrent posters with randomized delivery modes to detect race conditions. (spec.md#15-testing-matrix)
- Unit test confirms Async and Background deliveries execute off the posting thread. (spec.md#4.2-delivery-modes)
- Unit test ensures UnsubscribeAllFor removes all handlers for a target and prevents further dispatch. (spec.md#15-testing-matrix)
- Unit test verifies nested procedure subscriptions are removed via UnsubscribeAllFor on FPC. (spec.md#3-platform--compiler-support)
- Benchmark harness with configurable producers, consumers, payload sizes, and optional sticky/coalesce toggles. (spec.md#16-final-review--proposed-extensions)
- Console sample demonstrating typed, named, and GUID topics with delivery modes, sticky events, coalescing, and queue policy. (spec.md#1.1-goals)
- Unit tests covering named and GUID topics including sticky, coalescing, queue policies, and metrics to raise coverage beyond 85%. (spec.md#15-testing-matrix)
- UI sample demonstrating Main delivery with throttled updates and FPC console counterpart. (spec.md#1.1-goals)
- `fpc.cfg` includes lib/maxEventNexus in search paths for sample builds. (spec.md#3-platform--compiler-support)
- KPI thresholds documented for benchmark harness. (spec.md#16-final-review--proposed-extensions)
- `MaxLogic.fpc.compatibility` unit and `delphimode.inc` copied from GlobalLib for cross-compiler anonymous method support. (spec.md#3-platform--compiler-support)
- Configurable Main-thread degradation policy via `TmaxMainThreadPolicy` + `maxSetMainThreadPolicy`. (T-1003)
- GUID-topic advanced controls: `TryPostGuidOf`, GUID coalescing, GUID queue policies, and GUID stats retrieval. (T-1035)
- Metric sampling throttling via `maxSetMetricSampleInterval` to limit callback frequency on high-rate topics. (T-1004)
- Queue policy presets (`TmaxQueuePreset` + `maxSetQueuePreset*`) to apply spec defaults unless an explicit policy is set. (T-1029)
- Defined `max_BUS_VERSION` constant and VERSION file to start SemVer at v0.1.0. (spec.md#1.1-goals)

### Changed
- Renamed the aggregate dispatch exception type from EmaxAggregateException to EmaxDispatchError. (T-1033)
- Removed the global bus lock in favor of finer-grained synchronization for topic dictionaries and per-topic state. (T-1040)
- Removed DEBUG logging plumbing from the core bus unit. (T-1009)
- `maxSetAsyncScheduler` now updates the live singleton bus so runtime scheduler swaps take effect immediately. (T-1030)
- Posting-mode Post/TryPost dispatch avoids per-subscriber heap allocations on the hot path. (T-1031)
- Metrics reads (`GetTotals`/`GetStats*`) no longer take bus locks; per-topic stats snapshots are served from atomic counters. (T-1036)

### Fixed
- Defined `TmaxProc` as plain procedure on FPC to align cross-compiler handler types. (spec.md#3-platform--compiler-support)
- Replaced TMethod-based target lookup with explicit subscriber target field for FPC compatibility. (spec.md#3-platform--compiler-support)
- Corrected `SyncObjs` unit casing to `syncobjs` for FPC Linux builds. (spec.md#3-platform--compiler-support)
- Removed obsolete `specialize` keywords so generics compile under FPC 3.2.2 Delphi mode. (spec.md#3-platform--compiler-support)
- Replaced anonymous-thread async adapter with compatibility-backed worker scheduling so FPC builds without Delphi-only `CreateAnonymousThread` usage. (spec.md#3-platform--compiler-support)
- Zero-window coalescing now defers dispatch until after the posting cycle, allowing intermediate posts to merge. (spec.md#8-coalescing)
- Fixed Delphi weak-target liveness for object-method subscribers. (T-1022)
- Fixed coalescing flush scheduling and exception-path invoke-box ownership. (T-1041)
- High-water reset now emits a metric sample on reset so warnings can re-trigger later. (T-1005)
- Forward-declared typed topics and qualified default delivery enums to progress FPC 3.2.2 builds. (spec.md#3-platform--compiler-support)
- Replaced `TMonitor` with cross-compiler synchronization primitives, enabling FPC builds without Delphi RTL dependencies. (spec.md#3-platform--compiler-support)
- Console sample includes delphimode include and prefixed locals for FPC builds. (spec.md#3-platform--compiler-support)
- UI sample now unsubscribes handler and prevents multiple producer threads. (spec.md#1.1-goals)
- Removed invalid RTLEventWaitFor assignment so FPC builds succeed. (spec.md#3-platform--compiler-support)
- FPC monitor Wait(aTimeout) now reports timeout using TEvent so False returns on elapsed waits. (spec.md#3-platform--compiler-support)
- Generic bus methods restored for FPC 3.2.2 via compatibility unit. (spec.md#3-platform--compiler-support)


## [0.1.0] - 2025-09-11

### Added
- Repository skeleton with src/, tests/, samples/, bench, docs, and .ci directories.
- Core type definitions and interfaces for the bus (`TmaxProc`, `ImaxBus`, and related).
- Default async adapter wrapping maxAsync for thread marshaling.
- Topic registry with copy-on-write subscriber storage and weak target handling.
- Public API for subscribe/post/unsubscribe with `TryPost*` variants.
- Delivery modes (Posting, Main, Async, Background) preserving per-topic ordering.
- Sticky cache allowing late subscribers to receive the last event.
- Coalescing mechanism with per-topic pending dictionary and key selectors.
- Async error hook for forwarding handler exceptions.
- MaxLogic proprietary LICENSE and NOTICE files.
- Integrated coalescing with queue back-pressure policies honoring overflow rules. (spec.md#8-coalescing)
- Established changelog and contributing guide documenting SemVer and Conventional Commit rules. (spec.md#1.1-goals)
- GitHub issue templates and pull request template to align contributions with spec sections. (spec.md#1.1-goals)
- Documented branching strategy with `dev` and `main` branches and SemVer `vX.Y.Z` tags. (spec.md#1.1-goals)
- Definition of Done outlining test, lint, documentation, and sample criteria. (spec.md#1.1-goals)
- README with quick-start usage example and links to bus specification. (spec.md#1.1-goals)
- Delphi-only `maxSubscribeAttribute` with `AutoSubscribe`/`AutoUnsubscribe` helpers and example sample. (spec.md#5.3-attribute-delphi-only)
- Manual subscription sample demonstrating parity with attribute-based registration. (spec.md#3.2-language-features)
- Migration guide mapping iPub and NX Horizon concepts to EventNexus APIs. (spec.md#13-interop--migration)

### Changed
- Added `RunDelayed` to async adapter and replaced blocking sleeps in coalescing with scheduler-based dispatch, unifying implementation across posting functions. (spec.md#8-coalescing)
- Clarified `aWindowUs` edge-case behavior for negative or sub-millisecond windows. (spec.md#8-coalescing)
- Aggregated synchronous handler exceptions via `EmaxAggregateException`, ensuring all Posting-mode errors surface after dispatch. (spec.md#11-error-semantics)
- Count handler exceptions in metrics totals. (spec.md#11-error-semantics)
- Wrapped Delphi-only procedure types and tests with max_DELPHI conditionals to prep FPC builds. (spec.md#3-platform--compiler-support)
