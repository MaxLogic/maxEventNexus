# EventNexus Tests

Unit tests are executed with DUnitX.

- Runner project: `tests/MaxEventNexusTests.dpr`
- Build script: `./build-tests.sh`
- Build + run script: `./build-and-run-tests.sh`
- Static analysis baseline: `./build-static-analysis.sh`
- Executable: `tests/MaxEventNexusTests.exe`
- Diagnostics gate: `build-delphi.bat` is invoked with `-enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` by default in test build scripts.

The suite includes our compatibility fixture that executes published-method tests through DUnitX so existing behavioral tests remain active while we migrate/add native fixture coverage.

Mailbox coverage notes:

- `TTestMailbox` pins owner-thread pumping, FIFO per mailbox, typed `SubscribeIn<T>` receiver affinity, unsubscribe skipping queued work, `Clear` purge, `Close(True)` discard, and timeout behavior.
- Mailbox coverage uses the portable mailbox implementation only; it does not depend on Windows messages or other platform-specific wakeup mechanisms.
