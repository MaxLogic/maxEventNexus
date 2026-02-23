# EventNexus Samples

Sample programs demonstrating current Delphi EventNexus usage.

- `AutoSubscribeSample.pas`: attribute-based registration with `AutoSubscribe` / `AutoUnsubscribe`.
- `ManualSubscribeSample.pas`: explicit subscribe/unsubscribe patterns.
- `ConsoleSample.pas`: typed, named, and GUID topics with delivery modes, sticky events, coalescing, and queue policy.
- `UISample.dpr`: VCL UI sample demonstrating `Main` delivery behavior.
- `UISampleConsole.pas`: console sample for scheduler and coalescing flow.

Build all samples through the group project:

- `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug`
