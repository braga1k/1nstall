# 3.2.0 validation — 2026-10-02

This release keeps the application behavior approved after the 3.2 review. The project owner authorized stable publication as-is. Publication status does not extend the test coverage below.

## Current evidence

- Local Windows PowerShell 5.1 / .NET Framework WPF manager and smoke suites pass on the compiled application. Tests use fictional installed apps and never invoke a personal app's uninstaller.
- Card dimensions and visible Details buttons were checked at 830, 948, 1050, 1140, 1240, 1320, 1500 and 1920 DIP, including resizing back to a narrower width.
- Selection was exercised through UI Automation: checkbox/model synchronization, duplicate names, individual removal, filtered-out rows, Clear selection, and 20 selected rows with a stable scrollbar gutter. Compact 830×540 layout keeps actions visible.
- Logo centering, matching Selection titles, search spacing, responsive profiles, Details, history, snapshots, focus traversal, glass reflection, opaque fallback and reduced motion have local regression coverage.
- Raster renders at 100%, 125%, 150% and 200% demonstrate text/layout; these are not physical per-monitor DPI or screen-reader sessions.
- Catalog checks cover 325 apps, 24 categories, 20 profiles and 911 research rows.
- The publication workflow runs catalog checks, headless reliability and the packaged self-test on Windows Server 2022 before packaging. Actual CI logs are release assets, separate from local evidence.

## Environment limitation

The current local sandbox returns an empty SpecialFolder.UserProfile value. The headless/self-test registry boundary check fails there, also on the original review release. The protection and assertion remain unchanged. The publication workflow must pass these checks in its normal Windows environment; no skipped or forced-green check is used.

## Startup

The most recent same-session warm-profile comparison measured a median of 3.235 s for the final local build and 3.202 s for the prior build. Earlier 1.968 s measurements were not reproduced in that session. Measurement is process creation to first render followed by dispatcher idle, with normal asynchronous inventory startup. It uses a test cache beside the executable; production uses LocalAppData/1nstall/Runtime. Neither a cold Windows boot nor first launch without a JIT profile was measured in that comparison. No universal 1–2 second guarantee is made.

## Remaining coverage

Live EXE/MSI/Store installs and removals, machine elevation, actual reboot outcomes, registry restore/recycle round trips, Windows 10, screen readers, physical keyboard navigation, high contrast and real DPI transitions need broader isolated end-to-end validation. Live WinGet Client variants and native desktop composition were not established by these fixture tests. The executable is unsigned.

The UI review also identified active-filter contrast, a long Tab sequence and limited large-text adaptation as follow-up work. Tests demonstrate specific behavior rather than full accessibility certification.

## Evidence files

Current local packaged logs are in validation/3.2/. CI logs and BUILD-INFO.json accompany the release. Current WPF previews are in images/3.2/; uninstall examples are fictional. Existing files under validation/ and images/review/ outside those folders belong to earlier releases and must not be read as current 3.2.0 results.

For destructive fixture checks, use a disposable Windows VM and run tests/uninstall.ps1 -DisposableEnvironment. This switch declares isolation; it does not create a VM. Do not use personal apps as test fixtures.
