# ADR-0002: Delphi Interface Generics and Class Bridge

- Status: Accepted
- Date: 2026-02-23
- Deciders: EventNexus maintainers

## Context

We previously tracked work to expose generic methods directly on `ImaxBus*` interfaces and to remove class-cast compatibility shims.

On Delphi 12, generic interface methods are not supported (`E2535 Interface methods must not have parameterized methods`). This is a compiler constraint, not a library implementation issue.

## Decision

- Keep `ImaxBus`, `ImaxBusAdvanced`, `ImaxBusQueues`, and `ImaxBusMetrics` non-generic.
- Keep generic API surface on `TmaxBus`.
- Standardize on a typed bridge API:
  - `maxBusObj: TmaxBus`
  - `maxBusObj(const aIntf: IInterface): TmaxBus`
- Remove legacy `maxAsBus(...)` shim from active API/docs/callsites.

## Consequences

- Interface-generic task targets are closed as not implementable on current Delphi.
- Runtime/tests/samples use `maxBusObj(...)` when bridging from interface references to generic methods.
- Public docs align with Delphi compiler reality and no longer suggest unsupported interface-generic patterns.
