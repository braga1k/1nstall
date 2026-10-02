# Review validation — 2026-10-02

This records local evidence for the 3.2.0-review prerelease, not a production-readiness claim or quality score. The owner authorized publication with isolated Windows testing deferred. The publication workflow runs headless Windows CI and verifies uploaded asset hashes before publishing. Its actual result/logs accompany the release; the local results below remain separately identified.

## Environment and provenance

- x64 Windows kernel 10.0.26100; registry build 26100, UBR 9457, DisplayVersion 24H2. Registry ProductName reports Windows 10 Pro, so the kernel/build is recorded without inferring a marketing version.
- Windows PowerShell 5.1.26100.9444; CLR 4.0.30319.42000; Python 3.14.3; Windows .NET Framework x64 compiler.
- Source baseline: upstream `c97f780a05726bbaaea11d0636170a9126bd0cf5`. Shell Git/network access was unavailable. Source files were retrieved byte-for-byte through the GitHub connector and materialized as local baseline `fad035715607e3c6ad0b69db4a639bd5214adcea`. Upstream prebuilt executables and old PNG previews were omitted; icon and third-party notices are preserved.
- Work and artifacts reside in a writable temporary directory. Copy the review ZIP somewhere permanent before clearing temporary files.
- WinGet's executable alias exists but `winget --version` produced no output in this sandbox. PowerShell 7 was unavailable. Live supported WinGet inventory/update behavior is therefore not confirmed here.
- No disposable Windows VM was provisioned. No everyday app or personal data was used as a destructive fixture.

## Actual results

| Check | Baseline | Final | Evidence / scope |
|---|---|---|---|
| Catalog/profile audit | PASS | PASS | 325 apps, 24 categories, 20 profiles, 911 research rows; Python 3.14.3 |
| Existing helper self-test | PASS | PASS | Packaged self-test log; logic, not publisher installation |
| Existing WPF smoke suite | PASS | PASS | Layouts, selection/dependencies, profile rejection, reduced motion, glass fallback, consent; fictional removal rows |
| New headless reliability suite | Not present | PASS, 66 checks | Pure logic plus actual disposable child-process/filesystem fixtures; no publisher installers |
| New manager WPF suite | Not present | PASS | Essentials, details, installed/ambiguous states, updates/holds, history, snapshot preview, diagnostics, programmatic focus traversal |
| .NET Windows build | PASS | PASS | Standalone x64 EXE; compiler warnings treated as errors; SHA-256/input metadata; extracted-source build also passes with Git absent |
| Packaged behavior without source | Not recorded | PASS, all three modes | Self-test, smoke-test, manager-test run from the separate release-review folder |
| Native compositor capture | Not run at baseline | Environment failure | `Graphics.CopyFromScreen`: “The handle is invalid”; not classified as a product pass or regression |
| Windows CI | Not present | Workflow prepared | Headless Windows 2022 workflow; remote Actions run unavailable until owner pushes |
| Signing | Unsigned | Unsigned | No authorized credentials supplied; optional signing code added |

Final logs are in [validation/](validation/). Earlier intermediate failures were fixed before the final checks. The redaction regression caught and fixed a path pattern that initially left the tail of a personal path visible.

## What the regression checks demonstrate

Windows argument quoting round-trips spaces, quotes and trailing backslashes through a real fixture executable. Concurrent stdout/stderr draining handles 200 KB on each pipe. The suite rejects injected package identifiers and override flags. Exact/source-bound identity, compound packages, duplicate registrations, guided apps and partial export omissions are covered.

Fixtures cover missing WinGet, simulated offline/failure/cancellation/restart HRESULTs, and zero exit without verified state remaining Unknown. Recursive dependency cycles, missing dependencies and dependency failures are checked. Stop-after-current is checked with an actual slow child process; the active fixture completes and subsequent entries are cancelled.

Update checks cover exact reviewed versions, unknown versions, changed state, local exclusions, corrupted exclusion files, ordinary/blocking/gating pins, unfamiliar localized empty output, truncated tables and uncorrelated product-code pins. These are parser/predicate tests, not a live WinGet upgrade. Profiles cover old selections, version-2 snapshots, malformed/oversized data, unknown fields and executable-content rejection. Diagnostic export covers Windows/UNC/Unix paths, tokens, URL credentials/query values and email redaction. Corrupt history is preserved and reported.

## Screenshots and visual limits

The before/after PNGs are captured from the running WPF visual tree using `RenderTargetBitmap`. They demonstrate layout and fictional workflow states; they are not desktop compositor screenshots and do not prove real installed/update state. The native desktop helper could see only a Parsec window, not the WPF surface launched in the shell session.

| Workflow | Before | After |
|---|---|---|
| Library / first use | [All apps](images/review/before.png) | [Essentials](images/review/after.welcome.png), [glass](images/review/after.glass.png) |
| Smaller window | [baseline narrow](images/review/before.narrow.png) | [760×600](images/review/after.narrow.png) |
| Installed status | Existing separate uninstall list | [Exact installed identity fixture](images/review/after.installed.png) |
| Details | No corresponding workflow | [Details](images/review/after.details.png) |
| Updates | No corresponding workflow | [Review list](images/review/after.updates.png), [hold](images/review/after.held.png) |
| Troubleshooting | Existing operation pane | [History](images/review/after.history.png), [diagnostic preview](images/review/after.diagnostics.png) |
| Portable snapshot | Existing selection profiles | [Import preview](images/review/after.snapshot.png) |

100%, 150% and 200% **raster renders** are included as `after.render-*.png`. They are not OS display scaling tests. Programmatic WPF Focus/MoveFocus is checked; physical keyboard Tab/Shift+Tab/F1, screen readers, actual high-contrast mode, Windows text scaling, per-monitor DPI transitions and real Acrylic remain unverified. High-contrast resources follow Windows system colors in code, but that is not interactive evidence.

## Required isolated release checks

Use a disposable Windows VM with snapshots, internet, interactive desktop, WinGet, PowerShell 7 and Microsoft.WinGet.Client. Run native fixture cleanup with `tests/uninstall.ps1 -DisposableEnvironment` only there. It creates its own GUID-named disposable fixtures; it is not a publisher-installer test. The switch declares isolation and does not create a VM.

Then test authorized disposable EXE, MSI and Store apps through actual install, upgrade and removal. Include machine/user scopes, multiple versions, ordinary/blocking/gating pins, local holds, offline downloads, missing WinGet, source agreement refusal, dependency failure, stop-after-current, installer/UAC cancellation and real restart-required outcomes. Verify resulting state independently and inspect cleanup candidates, registry exports and Recycle Bin restore. Do not use personal applications as fixtures.

Run desktop keyboard/accessibility and compositor checks at actual 100/150/200% scaling, high contrast, transparency disabled and reduced motion; capture real before/after desktop screenshots. Confirm Windows 10 and Windows 11 behavior separately. Verify current Client module and CLI variants against the documented conservative pin fallback.

The Python/Zig alternate builder was updated for embedded payloads but was not built here. Installer subprocess behavior, restart semantics, source correlation, elevation and native recycle/restore remain the principal unresolved risks.
