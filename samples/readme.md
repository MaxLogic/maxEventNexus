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
- `MailboxClearShutdownSample.dpr`: shows `Clear` purging queued mailbox work, `Close(True)` discarding queued items while already-dequeued work may still finish, and `Close(False)` retaining queued items while rejecting future enqueue.
- `MailboxTopicFamiliesSample.dpr`: shows one mailbox hosting typed, exact named, named-of, and GUID mailbox subscriptions together while preserving FIFO order across the mixed queue.
- `MailboxLatestWinsSample.dpr`: shows mailbox coalescing collapsing repeated progress updates per key while unrelated keys keep their original queue order.
- `MailboxOverflowSample.dpr`: shows a bounded mailbox in `MailboxDropNewest` mode dropping later arrivals until the receiver pumps the mailbox.
- `UISample.dpr`: VCL UI sample demonstrating `Main` delivery behavior.
- `UISampleConsole.pas`: console sample for scheduler and coalescing flow.

Mailbox pumping rules for the samples:

- `PumpOne(cMaxWaitInfinite)` is the blocking worker-loop pattern for a dedicated receiver thread.
- `PumpOne(timeout)` is the timed cooperative pattern when the receiver also does other work.
- `PumpAll` is the manual poll pattern for a higher-level loop.

Suggested mailbox reading order:

- Start with `MailboxWorkerSample.dpr` for the basic owner-thread pattern.
- Use `MailboxTopicFamiliesSample.dpr` to see how the full mailbox subscribe family maps onto one mailbox.
- Use `MailboxLatestWinsSample.dpr` and `MailboxOverflowSample.dpr` for receiver-side queue behavior.
- Use `MailboxClearShutdownSample.dpr` for `Clear`, `Close(True)`, and `Close(False)` lifecycle boundaries.

Build all samples through the group project:

- `./build-delphi.sh maxEventNexusGroup.groupproj -config Debug`
