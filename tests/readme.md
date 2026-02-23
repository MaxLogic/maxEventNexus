# EventNexus Tests

Unit tests are executed with DUnitX.

- Runner project: `tests/MaxEventNexusTests.dpr`
- Build script: `./build-tests.sh`
- Build + run script: `./build-and-run-tests.sh`
- Static analysis baseline: `./build-static-analysis.sh`
- Executable: `tests/MaxEventNexusTests.exe`
- Diagnostics gate: `build-delphi.bat` is invoked with `-enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex` by default in test build scripts.

The suite includes our compatibility fixture that executes published-method tests through DUnitX so existing behavioral tests remain active while we migrate/add native fixture coverage.
