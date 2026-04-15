# EventNexus Samples

Sample programs demonstrating the supported Delphi 12+ EventNexus usage.

Bridge rule for samples:

- Use `TmaxBus` / `maxBusObj(...)` when calling generic bus APIs such as `Subscribe<T>`, `Post<T>`, `PostMany*`, `EnableSticky<T>`, and `EnableCoalesce*`.
- Keep interface-typed references only for non-generic APIs.
- The samples are Delphi-only; stale non-Delphi include patterns are intentionally not used here.

- `AutoSubscribeSample.pas`: attribute-based registration with `AutoSubscribe` / `AutoUnsubscribe`.
- `ManualSubscribeSample.pas`: explicit subscribe/unsubscribe patterns.
- `ConsoleSample.pas`: typed, named, and GUID topics with delivery modes, sticky events, coalescing, and queue policy.
- `MailboxWorkerSample.dpr`: thread A owns a mailbox, thread B posts, and thread A pumps the mailbox and handles on its own thread.
- `MailboxClearShutdownSample.dpr`: shows `Clear` purging queued mailbox work and `Close(True)` discarding queued items while already-dequeued work may still finish.
- `UISample.dpr`: VCL UI sample demonstrating `Main` delivery behavior.
- `UISampleConsole.pas`: console sample for scheduler and coalescing flow.

Mailbox pumping rules for the samples:

- `PumpOne(cMaxWaitInfinite)` is the blocking worker-loop pattern for a dedicated receiver thread.
- `PumpOne(timeout)` is the timed cooperative pattern when the receiver also does other work.
- `PumpAll` is the manual poll pattern for a higher-level loop.

Build all samples through the group project:

- `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug`
