# ADR-0004: Delphi 12 API Polish Candidates (Phase 2)

- Status: Accepted
- Date: 2026-02-24
- Deciders: EventNexus maintainers

## Context

We audited the current public surface using:

- `rg -n "maxBusObj|ImaxBus|ImaxBusAdvanced|ImaxBusQueues|ImaxBusMetrics|TmaxBus" README.md spec.md maxLogic.EventNexus*.pas`

The audit confirms the active API shape:

- non-generic operations on `ImaxBus`, `ImaxBusAdvanced`, `ImaxBusQueues`, `ImaxBusMetrics`
- generic operations on `TmaxBus`
- typed bridge via `maxBusObj` overloads

We need Delphi 12 modernization without unapproved public-signature breaks.

## Decision

### Approved candidates (no public-signature change)

1. Keep the interface/class split and treat `maxBusObj(...)` as the canonical bridge to generic APIs.
- Public signature impact: none.

2. Harden runtime internals where interface/class bridges are used (checked object casts, invariant-safe paths).
- Public signature impact: none.

3. Prefer explicit-width arithmetic for metrics aggregation/counters (avoid ambiguous 32/64 implicit math in internals).
- Public signature impact: none.

4. Keep scheduler adapters robust under contention/shutdown by using closure-based ownership instead of self-free callback objects.
- Public signature impact: none.

### Rejected/deferred candidates (public-signature impact or compiler constraints)

1. Rename the public interfaces/types for cosmetic casing normalization.
- Impact: breaking rename across all consumers.
- Decision: rejected for current cycle.

2. Collapse `ImaxBus*` interfaces into a single larger interface.
- Impact: breaking contract + migration churn.
- Decision: rejected for current cycle.

3. Remove global entry points (`maxBus`, `maxBusObj`) in favor of constructor-only or DI-only access.
- Impact: breaking usage model.
- Decision: deferred (requires separate migration ADR).

4. Move generic APIs onto Delphi interfaces.
- Impact: not implementable on Delphi (`E2535 Interface methods must not have parameterized methods`).
- Decision: permanently rejected (already aligned with ADR-0002).

## Consequences

- The public API remains stable in Phase 2 unless maintainers explicitly approve a breaking change.
- Delphi 12 modernization continues through internal safety/performance improvements and docs alignment.
- Any future signature-changing proposal requires a dedicated ADR with migration notes before implementation.
