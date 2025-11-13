# EventNexus Bus Tasks

 1. Wire in the FPC weak-target registry promised in spec.md so non-Delphi builds get real liveness checks instead of the current stub.
 2. Replace the raw-thread TmaxRawThreadScheduler fallback with the maxAsync-backed adapter described in the updated spec/README.
  3. After those land, rerun the full test matrix and bench runs to confirm no regressions.

▌

tasks:

  - id: T-0018
    title: "Verify FPC compilation"
    description: "Compile and run tests on FPC 3.2.2 for Win64 and Linux64 targets."
    spec_reference: "spec-bus.md#3-platform--compiler-support"
    acceptance_criteria:
      - "FPC test matrix passes"
    priority: High
    state: ToDo

  - id: T-0019
    title: "Achieve unit test coverage >=85%"
    description: "Provide comprehensive tests for bus features: subscribe/unsubscribe churn, ordering, sticky, coalesce, queues, metrics, and exceptions."
    spec_reference: "spec-bus.md#15-testing-matrix"
    acceptance_criteria:
      - ">=85% line and branch coverage on src/"
    priority: High
    state: ToDo

  - id: T-0051
    title: "Work around FPC interface generics"
    description: "Design FPC-compatible alternatives for generic methods in ImaxBus so FPC 3.2.2 builds succeed."
    spec_reference: "spec-bus.md#3-platform--compiler-support"
    acceptance_criteria:
      - "Prototype bus compiles with FPC without generic method errors"
    priority: High
    state: ToDo

  - id: T-0053
    title: "Introduce PTypeInfo-based ImaxBus for FPC"
    description: "Replace generic interface methods with PTypeInfo-driven alternatives to allow FPC 3.2.2 compilation."
    spec_reference: "spec-bus.md#3-platform--compiler-support"
    acceptance_criteria:
      - "Bus unit compiles under FPC without generic method errors"
    priority: High
    state: ToDo

  - id: T-0055
    title: "Refactor bus core to PTypeInfo-based API"
    description: "Replace generic methods in ImaxBus with non-generic, PTypeInfo-driven operations and provide generic helper wrappers so FPC and Delphi share a single interface."
    spec_reference: "spec-bus.md#33-implementation-plan"
    acceptance_criteria:
      - "ImaxBus exposes only non-generic methods"
      - "Helper generics compile on Delphi and FPC"
    priority: High
    state: ToDo

  - id: T-0030
    title: "Generate API docs"
    description: "Produce documentation from unit headers with inline examples."
    spec_reference: "spec-bus.md#1.1-goals"
    acceptance_criteria:
      - "API docs build and include examples"
    priority: Medium
    state: ToDo

  - id: T-0032
    title: "Package artifacts"
    description: "Produce release packages with Delphi and FPC build outputs."
    spec_reference: "spec-bus.md#19-release-engineering"
    acceptance_criteria:
      - "Artifacts contain lib/, include/, docs/"
    priority: Medium
    state: OnHold

  - id: T-0033
    title: "Sign artifacts"
    description: "Sign or checksum release artifacts as required."
    spec_reference: "spec-bus.md#19-release-engineering"
    acceptance_criteria:
      - "Checksums verified for release files"
    priority: Medium
    state: OnHold

  - id: T-0034
    title: "Mitigate deadlock risk"
    description: "Provide tests and documentation for Block overflow leading to UI deadlocks."
    spec_reference: "spec-bus.md#20-risk-register--mitigations"
    acceptance_criteria:
      - "Tests detect blocking on main thread"
    priority: Medium
    state: ToDo

  - id: T-0035
    title: "Monitor unbounded memory risk"
    description: "Use metrics thresholds and recommend policy overrides to avoid unbounded memory use."
    spec_reference: "spec-bus.md#20-risk-register--mitigations"
    acceptance_criteria:
      - "Docs and tests cover memory warning behavior"
    priority: Medium
    state: ToDo

  - id: T-0036
    title: "Improve weak target detection"
    description: "Add robust target-liveness checks and finalize hooks to prevent mis-detection."
    spec_reference: "spec-bus.md#20-risk-register--mitigations"
    acceptance_criteria:
      - "Tests show weak targets removed without leaks"
    priority: Medium
    state: ToDo

  - id: T-0037
    title: "Enforce spec PR policy"
    description: "Require spec diffs for all behavior-changing pull requests."
    spec_reference: "spec-bus.md#21-governance--change-control"
    acceptance_criteria:
      - "PR template validates spec links"
    priority: Medium
    state: OnHold

  - id: T-0038
    title: "Label pull requests"
    description: "Tag PRs with spec, impl, tests, docs, or perf labels."
    spec_reference: "spec-bus.md#21-governance--change-control"
    acceptance_criteria:
      - "Repository has required labels"
    priority: Medium
    state: OnHold

  - id: T-0039
    title: "Weekly dev to main cut"
    description: "Merge dev into main weekly when CI green."
    spec_reference: "spec-bus.md#21-governance--change-control"
    acceptance_criteria:
      - "Schedule documented; automation in place"
    priority: Medium
    state: OnHold

  - id: T-0049
    title: "Resolve FPC generic interface errors"
    description: "Adjust generic interface implementations so FPC 3.2.2 compiles EventNexus."
    spec_reference: "spec-bus.md#3-platform--compiler-support"
    acceptance_criteria:
      - "ConsoleSample builds under FPC"
    priority: Medium
    state: ToDo

  - id: T-0054
    title: "Provide FPC generic wrappers"
    description: "Add helper functions or type helpers so FPC consumers can call Subscribe<T>/Post<T> over the new typed API."
    spec_reference: "spec-bus.md#3-platform--compiler-support"
    acceptance_criteria:
      - "FPC code uses generic-style helpers matching Delphi API"
    priority: Medium
    state: ToDo

  - id: T-0040
    title: "Introduce freelist pools"
    description: "Use per-topic freelist/slab pools to make Post allocation-free on hot path."
    spec_reference: "spec-bus.md#17-optimization-passes"
    acceptance_criteria:
      - "Benchmarks show reduced allocations"
    priority: Low
    state: OnHold

  - id: T-0041
    title: "Avoid false sharing"
    description: "Align or pad counters and queue indices."
    spec_reference: "spec-bus.md#17-optimization-passes"
    acceptance_criteria:
      - "Cache-line padding verified in profiles"
    priority: Low
    state: ToDo

  - id: T-0042
    title: "Evaluate ring-buffer specialization"
    description: "Assess ring-buffer channels for SPSC/MPSC topics while keeping generic API."
    spec_reference: "spec-bus.md#17-optimization-passes"
    acceptance_criteria:
      - "Evaluation documented with performance data"
    priority: Low
    state: ToDo

  - id: T-0043
    title: "Batch atomic operations"
    description: "Reduce atomic usage by batching operations where feasible."
    spec_reference: "spec-bus.md#17-optimization-passes"
    acceptance_criteria:
      - "Microbenchmarks show no correctness regression"
    priority: Low
    state: ToDo

  - id: T-0044
    title: "Validate completion criteria"
    description: "Ensure tasks 1–15 complete and task 16 prepared but disabled by default."
    spec_reference: "spec-bus.md#22-done-when"
    acceptance_criteria:
      - "Checklist confirms items 1–15 complete"
    priority: Low
    state: ToDo

  - id: T-0045
    title: "Cut first release"
    description: "CI green, samples run, docs ready, and v0.1.0 tagged."
    spec_reference: "spec-bus.md#22-done-when"
    acceptance_criteria:
      - "Tag v0.1.0 exists with release notes"
    priority: Low
    state: ToDo


  - id: T-0056
    title: "Stabilize subscriber array semantics"
    description: "Rework subscriber storage to preserve registration order and keep subscription indices consistent per copy-on-write design."
    spec_reference: "design.md#subscriber-storage"
    acceptance_criteria:
      - "Add/remove operations maintain FIFO order for handlers"
      - "Subscription.Unsubscribe and UnsubscribeAllFor remove the correct handler after prior removals"
      - "Unit tests cover rapid subscribe/unsubscribe cycles without index corruption"
    priority: High
    state: Done

  - id: T-0057
    title: "Emit metric samples"
    description: "Invoke maxSetMetricCallback with up-to-date stats so external samplers observe changes without polling."
    spec_reference: "spec.md#11.1-diagnostics--metrics"
    acceptance_criteria:
      - "Metric callback fires on post/delivery/error/queue-depth changes"
      - "Unit tests verify callback receives expected stats deltas"
      - "No callback => zero overhead in hot path"
    priority: Medium
    state: Done

  - id: T-0058
    title: "Correct TryPost semantics"
    description: "Ensure TryPost/TryPostNamed/TryPostNamedOf return False only when events are dropped per queue policy, including coalesced dispatch paths."
    spec_reference: "spec.md#8.7-back-pressure--bounded-queues"
    acceptance_criteria:
      - "TryPost* returns True when enqueue succeeds or no drop occurs"
      - "Coalesced topics propagate enqueue failures"
      - "Unit tests cover DropNewest/Deadline policies"
    priority: High
    state: Done

  - id: T-0059
    title: "Integrate maxAsync adapter"
    description: "Replace the ad-hoc raw-thread scheduler with a maxAsync-backed adapter and platform fallbacks per spec."
    spec_reference: "spec.md#4-threading-model--maxasync-integration"
    acceptance_criteria:
      - "Default IEventNexusScheduler delegates to maxAsync on Delphi"
      - "FPC build provides equivalent scheduling semantics"
      - "Background delivery remains inline off-main thread"
    priority: High
    state: Done

  - id: T-0060
    title: "Implement weak subscriber targets"
    description: "Store subscriber targets via weak references and prune dead objects before dispatch."
    spec_reference: "design.md#subscriber-storage"
    acceptance_criteria:
      - "Object listeners auto-drop after destruction without leaks"
      - "Weak reference handling covered by unit tests"
      - "No extra allocations on Post hot path"
    priority: High
    state: Done

  - id: T-0061
    title: "Warn on deep unbounded queues"
    description: "Emit metrics warnings when unbounded topic queues exceed 10k depth, as required for monitoring memory pressure."
    spec_reference: "spec.md#8.7-back-pressure--bounded-queues"
    acceptance_criteria:
      - "Threshold breach increments a warning counter surfaced via metrics"
      - "Metric callback receives warning state"
      - "Tests cover threshold crossing and reset"
    priority: Medium
    state: Done
