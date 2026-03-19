# EventNexus Samples

Sample programs demonstrating the supported Delphi 12+ EventNexus usage.

Bridge rule for samples:

- Use `TmaxBus` / `maxBusObj(...)` when calling generic bus APIs such as `Subscribe<T>`, `Post<T>`, `PostMany*`, `EnableSticky<T>`, and `EnableCoalesce*`.
- Keep interface-typed references only for non-generic APIs.
- The samples are Delphi-only; stale FPC-only include patterns are intentionally not used here.

- `AutoSubscribeSample.pas`: attribute-based registration with `AutoSubscribe` / `AutoUnsubscribe`.
- `ManualSubscribeSample.pas`: explicit subscribe/unsubscribe patterns.
- `ConsoleSample.pas`: typed, named, and GUID topics with delivery modes, sticky events, coalescing, and queue policy.
- `UISample.dpr`: VCL UI sample demonstrating `Main` delivery behavior.
- `UISampleConsole.pas`: console sample for scheduler and coalescing flow.

Build all samples through the group project:

- `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug`
