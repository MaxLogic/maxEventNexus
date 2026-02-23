# ADR-0003: Extension Scope Freeze for Current Delivery

- Status: Accepted
- Date: 2026-02-23
- Deciders: EventNexus maintainers

## Context

Spec section 14 lists several optional extensions that were tracked as blocked tasks pending API/semantics approval:

- priority subscriptions
- bulk dispatch
- wildcard topic groups
- tracing hooks
- serializer plug-in (IPC)
- disruptor-style sequences

These items are design-heavy and each requires deeper API and correctness validation than the current delivery scope allows.

## Decision

For the current delivery window, we explicitly **defer** these extensions and keep section 14 as proposed-only scope.

- No partial APIs are introduced.
- No hidden/experimental runtime hooks are added in core for these features.
- Re-entry requires a dedicated ADR per feature (or feature group) with explicit contracts.

## Consequences

- Blocked ambiguity is removed; corresponding tasks are closed as deferred-by-decision.
- Core roadmap remains focused on current correctness, testing, diagnostics, and Delphi-12 modernization work.
- Future implementation starts from approved ADR contracts rather than speculative backlog text.
