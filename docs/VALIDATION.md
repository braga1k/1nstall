# 3.5.0 validation — 2026-10-04

The owner authorized this release on 2026-10-04. Local packaged self-test, smoke and manager suites pass, together with catalog checks, 56 reliability checks and 51 locale packs containing 239 strings each.

Native Windows Sandbox checks cover actual 7-Zip and Notepad++ EXE removals, product registry keys, retained AppData, delayed publisher-child completion, registry backup/restore, recycling/restore, and re-registration protection. The final queue/glass development executable retained the checked selection through the real 7-Zip child dialog and kept its Success row through leftover review and empty-inventory refresh. Detailed cases and limits are in [UNINSTALL.md](UNINSTALL.md).

The cleanup WPF suite checks 51 locales, 560 × 520 action bounds, linked-path selection with separate consent, scroll endpoints, four appearances, disk-only/registry-only cases and complete versus partial results. The queue WPF suite covers stable rows, phase/progress updates, inventory refresh, manual/reverified results, retry, clearing, task faults and the minimum window. Native process fixtures cover launcher/child/grandchild lifetime, cancellation, sequential execution and live selection versus persisted history. These tests do not install or remove personal host applications.

Current English renders are in `images/3.5/`, including a fictional Uninstall queue. Native translation proofreading, broader MSI/Store/elevation/restart coverage and the Explorer foreground check remain pending. The previous baseline and its measurement limits follow below.

# Published 3.4.0 validation — 2026-10-04

The owner authorized publication of the current implementation on 2026-10-04. Publication does not extend the coverage below. UI checks use fictional applications and do not install or remove personal software.

## Local Windows checks

- Packaged self-test, smoke test and manager UI suite pass under Windows PowerShell 5.1 / .NET Framework WPF.
- Catalog checks cover 325 apps, 24 categories, 20 profiles, 200 shortlist mappings and 911 benchmark rows. All 56 headless reliability regressions pass.
- Locale checks cover 51 choices with 211 strings each, matching keys and interpolation placeholders. The manager suite switches through every locale, checks right-to-left Arabic/Urdu, preserves selections and fits profile controls at the 1040-DIP minimum width. Translation quality still requires native-speaker review.
- Selection checks cover checkbox/model synchronization, duplicate names, individual removal, filtered-out rows, Clear selection and selection queues. Details, profiles, snapshots, history, keyboard focus, persistent preferences and updater integrity retain regression coverage.
- Motion checks cover entrances, hover/press feedback, selection feedback, cancellation/cleanup, reduced-motion fallback and verified-success confirmation. Failure, cancellation and uncertain outcomes do not trigger the success glow.

## Appearance and scrolling

`tests/appearance.ps1` compares rendered opening and main-window backgrounds across eight light/dark, accent and effects combinations. Their WPF canvas pixels match. Eight monochrome opening/app images have no RGB-channel differences. The saved accent is checked against the main app's Windows accent reader. These are WPF render checks, not comparisons of the physical DWM compositor.

`tests/scrolling.ps1` covers 1040 × 540, 1240 × 840 and 1440 × 900 layouts, mixed installed-row heights, filtering to one result, resizing, both selection queues, category expansion/collapse, Settings, language/profile menus, history and dialogs. Scroll ranges end at content with intentional small padding, and filtering clamps offsets. Install and Uninstall share centered 20-DIP scrollbar gutters.

Earlier raster checks at 100%, 125%, 150% and 200% cover layout rendering; they are not physical per-monitor DPI or screen-reader sessions.

## Startup and foreground handoff

`tests/startup-opening.ps1` checks independent painting, early disposal, cancellation/shutdown, native ownership before closing, and handoff to modeless and modal main windows. The opening does not create a separate taskbar entry or use permanent Topmost state. Its animation does not impose a minimum wait before the app becomes ready.

Windows denied activation of the background PowerShell fixture, so real foreground assertions were explicitly **skipped**. Internal owner/handoff checks do not prove the Explorer double-click scenario. The earlier implementation was reported to lose focus; 3.4 changes ownership before closing the opening. That actual Explorer scenario still needs manual confirmation.

The final development build measured first-frame samples of 1217, 1138 and 1120 ms (median 1.138 s), with readiness at 2383, 2386 and 2411 ms (median 2.386 s). These local samples precede the version bump and are not a benchmark of the CI binary, a cold Windows boot or a universal timing guarantee. `tests/startup.ps1` records both checkpoints for further measurements.

## Release checks and evidence

Windows CI runs catalog and locale checks, headless reliability, the build and packaged self-test from the release commit. Packaging requires a clean source build, verifies every archived build-input hash and generates asset checksums. Publication verifies uploaded names and SHA-256 digests before making the release stable. CI logs and BUILD-INFO.json accompany the release.

The 3.4 English UI renders are in `images/3.4/`. Uninstall examples are fictional. Earlier evidence under `images/3.2/`, `images/3.3/` and `validation/3.2/` belongs to those releases. Historical 3.3 screenshots were recaptured in English using that release's own source and assemblies.

Public GitHub screenshots always use English. Run `tests/screenshots.ps1 -PreviewDirectory <folder>` and review the images. For an older release, pass its source with `-SourceDirectory` and use matching compiled assemblies. Language-specific captures remain local test evidence.

## Remaining coverage

Live EXE/MSI/Store installs and removals, elevation, actual reboot outcomes, registry restore/recycle round trips, Windows 10, screen readers, physical keyboard navigation, high contrast and real DPI transitions need broader isolated end-to-end validation. Live WinGet Client variants and native desktop composition are not established by fixture tests. The executable is unsigned.

The UI review also identified active-filter contrast, a long Tab sequence and limited large-text adaptation as follow-up work. Tests demonstrate specific behavior, not full accessibility certification. Updater tests verify real release download integrity, rejection of corrupt payloads and replacement of disposable copies with previous-version retention; they do not update a personal installation during testing.

For destructive fixture checks, use a disposable Windows VM and run `tests/uninstall.ps1 -DisposableEnvironment`. This switch declares isolation; it does not create a VM. Do not use personal apps as test fixtures.
