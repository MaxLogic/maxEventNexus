# EventNexus Bus Changelog

## [Unreleased]

### Added
- DESIGN.md detailing topics, queues, sticky cache, coalescer, and metrics architecture. (spec-bus.md#1.1-goals)
- Unit test for subscription churn and per-topic ordering. (spec-bus.md#15-testing-matrix)
- Unit test verifying sticky events deliver last value to late subscribers. (spec-bus.md#8-sticky)
- Unit test validating coalesced events deliver latest value per key. (spec-bus.md#8-coalescing)
- Unit test ensuring zero-window coalescing batches sequential posts and delivers only the last value. (spec-bus.md#8-coalescing)
- Unit test confirming queue overflow policies drop or block according to configured behavior. (spec-bus.md#8.7-back-pressure--bounded-queues)
- Metrics counters now track posts, deliveries, drops, and exceptions with tests covering each. (spec-bus.md#11-error-semantics)
- Fuzz test spawns concurrent posters with randomized delivery modes to detect race conditions. (spec-bus.md#15-testing-matrix)
- Unit test confirms Async and Background deliveries execute off the posting thread. (spec-bus.md#4.2-delivery-modes)
- Unit test ensures UnsubscribeAllFor removes all handlers for a target and prevents further dispatch. (spec-bus.md#15-testing-matrix)
- Unit test verifies nested procedure subscriptions are removed via UnsubscribeAllFor on FPC. (spec-bus.md#3-platform--compiler-support)
- Benchmark harness with configurable producers, consumers, payload sizes, and optional sticky/coalesce toggles. (spec-bus.md#16-final-review--proposed-extensions)
- Console sample demonstrating typed, named, and GUID topics with delivery modes, sticky events, coalescing, and queue policy. (spec-bus.md#1.1-goals)
- Unit tests covering named and GUID topics including sticky, coalescing, queue policies, and metrics to raise coverage beyond 85%. (spec-bus.md#15-testing-matrix)
- UI sample demonstrating Main delivery with throttled updates and FPC console counterpart. (spec-bus.md#1.1-goals)
- `fpc.cfg` includes lib/maxEventNexus in search paths for sample builds. (spec-bus.md#3-platform--compiler-support)
- KPI thresholds documented for benchmark harness. (spec-bus.md#16-final-review--proposed-extensions)
- `MaxLogic.fpc.compatibility` unit and `delphimode.inc` copied from GlobalLib for cross-compiler anonymous method support. (spec-bus.md#3-platform--compiler-support)

- Defined `ML_BUS_VERSION` constant and VERSION file to start SemVer at v0.1.0. (spec-bus.md#1.1-goals)


### Fixed
 - Defined `TMLProc` as plain procedure on FPC to align cross-compiler handler types. (spec-bus.md#3-platform--compiler-support)
- Replaced TMethod-based target lookup with explicit subscriber target field for FPC compatibility. (spec-bus.md#3-platform--compiler-support)
- Corrected `SyncObjs` unit casing to `syncobjs` for FPC Linux builds. (spec-bus.md#3-platform--compiler-support)
- Removed obsolete `specialize` keywords so generics compile under FPC 3.2.2 Delphi mode. (spec-bus.md#3-platform--compiler-support)
- Replaced anonymous-thread async adapter with compatibility-backed worker scheduling so FPC builds without Delphi-only `CreateAnonymousThread` usage. (spec-bus.md#3-platform--compiler-support)
- Zero-window coalescing now defers dispatch until after the posting cycle, allowing intermediate posts to merge. (spec-bus.md#8-coalescing)
- Forward-declared typed topics and qualified default delivery enums to progress FPC 3.2.2 builds. (spec-bus.md#3-platform--compiler-support)
- Replaced `TMonitor` with cross-compiler synchronization primitives, enabling FPC builds without Delphi RTL dependencies. (spec-bus.md#3-platform--compiler-support)
- Console sample includes delphimode include and prefixed locals for FPC builds. (spec-bus.md#3-platform--compiler-support)
- UI sample now unsubscribes handler and prevents multiple producer threads. (spec-bus.md#1.1-goals)
- Removed invalid RTLEventWaitFor assignment so FPC builds succeed. (spec-bus.md#3-platform--compiler-support)
- FPC monitor Wait(aTimeout) now reports timeout using TEvent so False returns on elapsed waits. (spec-bus.md#3-platform--compiler-support)
- Generic bus methods restored for FPC 3.2.2 via compatibility unit. (spec-bus.md#3-platform--compiler-support)


## [0.1.0] - 2025-09-11

### Added
- Repository skeleton with src/, tests/, samples/, bench, docs, and .ci directories.
- Core type definitions and interfaces for the bus (`TMLProc`, `IMLBus`, and related).
- Default async adapter wrapping maxAsync for thread marshaling.
- Topic registry with copy-on-write subscriber storage and weak target handling.
- Public API for subscribe/post/unsubscribe with `TryPost*` variants.
- Delivery modes (Posting, Main, Async, Background) preserving per-topic ordering.
- Sticky cache allowing late subscribers to receive the last event.
- Coalescing mechanism with per-topic pending dictionary and key selectors.
- Async error hook for forwarding handler exceptions.
- MaxLogic proprietary LICENSE and NOTICE files.
- Integrated coalescing with queue back-pressure policies honoring overflow rules. (spec-bus.md#8-coalescing)
- Established changelog and contributing guide documenting SemVer and Conventional Commit rules. (spec-bus.md#1.1-goals)
- GitHub issue templates and pull request template to align contributions with spec sections. (spec-bus.md#1.1-goals)
- Documented branching strategy with `dev` and `main` branches and SemVer `vX.Y.Z` tags. (spec-bus.md#1.1-goals)
- Definition of Done outlining test, lint, documentation, and sample criteria. (spec-bus.md#1.1-goals)
- README with quick-start usage example and links to bus specification. (spec-bus.md#1.1-goals)
- Delphi-only `MLSubscribeAttribute` with `AutoSubscribe`/`AutoUnsubscribe` helpers and example sample. (spec-bus.md#5.3-attribute-delphi-only)
- Manual subscription sample demonstrating parity with attribute-based registration. (spec-bus.md#3.2-language-features)
- Migration guide mapping iPub and NX Horizon concepts to EventNexus APIs. (spec-bus.md#13-interop--migration)

### Changed
- Added `RunDelayed` to async adapter and replaced blocking sleeps in coalescing with scheduler-based dispatch, unifying implementation across posting functions. (spec-bus.md#8-coalescing)
- Clarified `aWindowUs` edge-case behavior for negative or sub-millisecond windows. (spec-bus.md#8-coalescing)
- Aggregated synchronous handler exceptions via `EMLAggregateException`, ensuring all Posting-mode errors surface after dispatch. (spec-bus.md#11-error-semantics)
- Count handler exceptions in metrics totals. (spec-bus.md#11-error-semantics)
- Wrapped Delphi-only procedure types and tests with ML_DELPHI conditionals to prep FPC builds. (spec-bus.md#3-platform--compiler-support)
