# 3.3.0 validation — 2026-10-03

The project owner approved publishing Settings and the refined light/dark/monochrome appearances on 2026-10-03. Publication does not extend the test coverage below.

## Current evidence

- Local Windows PowerShell 5.1 / .NET Framework WPF manager and smoke suites pass on the compiled application. Tests use fictional installed apps and never invoke a personal app's uninstaller.
- Card dimensions and visible Details buttons were checked at 830, 948, 1050, 1140, 1240, 1320, 1500 and 1920 DIP, including resizing back to a narrower width.
- Selection was exercised through UI Automation: checkbox/model synchronization, duplicate names, individual removal, filtered-out rows, Clear selection, and 20 selected rows with a stable scrollbar gutter. Compact 830×540 layout keeps actions visible.
- Logo centering, matching Selection titles, search spacing, responsive profiles, Details, history, snapshots, focus traversal, glass reflection, opaque fallback and reduced motion have local regression coverage.
- Raster renders at 100%, 125%, 150% and 200% demonstrate text/layout; these are not physical per-monitor DPI or screen-reader sessions.
- Catalog checks cover 325 apps, 24 categories, 20 profiles and 911 research rows.
- The publication workflow runs catalog checks, headless reliability and the packaged self-test on Windows Server 2022 before packaging. Actual CI logs are release assets, separate from local evidence.

## Settings and appearance validation

- All ten locale choices and Arabic/Urdu right-to-left layouts preserve selections. Preferences are checked across atomic saves.
- Light and dark retain gradient materials; foreground contrast is checked against the light material stops. Theme/accent changes also update already-moved hover reflections.
- Settings cards and buttons share pointer-following light; reduced motion and opaque fallback are covered.
- Ten local monochrome renders of Install, Uninstall and Settings had no RGB channel differences: no residual colour. Render checks are distinct from physical monitor/DPI testing.
- A real official release download passed SHA-256 and assembly checks. The packaged update worker replaced only disposable files, including paths with spaces; invalid hashes were rejected and previous executables retained.
- Catalog checks and all 54 headless reliability regressions passed locally in this session. The earlier 3.2 sandbox profile-path limitation did not recur.

## Startup

During Settings development, three samples measured 2.578, 2.501 and 2.518 seconds (median 2.518 s), before the final appearance refinements. These are not a fresh timing of the release executable. The prior 3.2 release measured roughly 3.2 seconds in another session; the samples do not establish a guaranteed speedup. Measurement is process creation to first render followed by dispatcher idle, with normal asynchronous inventory startup. It uses a test cache beside the executable; production uses LocalAppData/1nstall/Runtime. Neither a cold Windows boot nor first launch without a JIT profile was measured in that comparison. No universal 1–2 second guarantee is made.

## Remaining coverage

Live EXE/MSI/Store installs and removals, machine elevation, actual reboot outcomes, registry restore/recycle round trips, Windows 10, screen readers, physical keyboard navigation, high contrast and real DPI transitions need broader isolated end-to-end validation. Live WinGet Client variants and native desktop composition were not established by these fixture tests. The executable is unsigned.

The UI review also identified active-filter contrast, a long Tab sequence and limited large-text adaptation as follow-up work. Tests demonstrate specific behavior rather than full accessibility certification.

## Evidence files

Windows CI logs and BUILD-INFO.json accompany this release. Current appearance renders are in images/3.3/. Existing logs in validation/3.2/ and images/3.2/ document the previous release, not current 3.3.0 test results. Uninstall examples use fictional apps.

For destructive fixture checks, use a disposable Windows VM and run tests/uninstall.ps1 -DisposableEnvironment. This switch declares isolation; it does not create a VM. Do not use personal apps as test fixtures.
