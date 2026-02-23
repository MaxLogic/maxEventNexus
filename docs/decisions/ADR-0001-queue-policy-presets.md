# ADR-0001: Queue Policy Preset Categories

- Status: Accepted
- Date: 2026-02-23
- Deciders: EventNexus maintainers

## Context

EventNexus supports per-topic queue policies (`TmaxQueuePolicy`) and global preset helpers (`maxSetQueuePreset*`).

Without a clear default strategy, topic behavior drifts across modules and teams. We need deterministic defaults that are easy to reason about and easy to override where required.

## Decision

We standardize three preset categories:

- `State`: `MaxDepth=256`, `Overflow=DropOldest`, `DeadlineUs=0`
- `Action`: `MaxDepth=1024`, `Overflow=Deadline`, `DeadlineUs=2000`
- `ControlPlane`: `MaxDepth=1`, `Overflow=Block`, `DeadlineUs=0`

Fallback (`Unspecified`) remains unbounded with `DropNewest` semantics as implemented by `PolicyForPreset`.

Preset assignment hooks:

- `maxSetQueuePresetForType(TypeInfo(...), Preset)`
- `maxSetQueuePresetNamed('...', Preset)`
- `maxSetQueuePresetGuid(Guid, Preset)`

## Override order

1. Explicit per-topic policy (`SetPolicy*`) wins.
2. Preset applies only when topic policy is not explicit.
3. Preset changes update existing topics only when those topics still use implicit policy.

## Metrics/high-water integration

Queue depth high-water warning is represented in per-topic metrics state:

- warning enters when depth `> 10000`
- warning resets when depth `<= 5000`

Transition points trigger metrics sampling, so monitoring can observe both warning and recovery.

## Consequences

- We get predictable default queue behavior by topic category.
- Teams can still override on topic-by-topic basis without losing global defaults.
- Monitoring pipelines can correlate preset choices with depth/warning behavior.
