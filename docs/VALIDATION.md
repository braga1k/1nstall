# Validation — 1nstall 4.0.0

How 4.0 was specified from the 3.6 code, compared with it and built is recorded phase by phase in [rewrite/](rewrite/README.md) (in Portuguese), with the evidence for each claim. Commands are in [DEVELOPING.md](DEVELOPING.md). Local checks use fictional apps and data beside the test build; no personal application is installed or removed.

## Current checks

- Catalog: 325 apps, 24 categories, 20 profiles, 200 shortlist mappings and 911 benchmark rows. The preserved taxonomy and provenance are in `catalog/`.
- Languages: 51 choices with 239 matching strings and valid placeholders.
- Engine rules: the Rust unit tests, and the oracle, which replays the behaviour recorded from the 3.6 helpers. Of 1552 recorded cases, 1532 are identical and the other 20 are listed, intentional differences; none is unexplained.
- Removal, on GitHub's disposable Windows Server 2022 and 2025 machines: eight recorded fixture scenarios, and a fixture app removed, scanned and cleaned through the boundary the window uses.
- Real install: Sumatra PDF installed through the engine's queue on Windows Server 2025. The 2022 image has no WinGet.
- Update from 3.6: the released 3.6.0 executable applies a 4.0 build with its own updater, on both images.
- Packaged self-test: 31 checks through the engine boundary, including that an internal engine failure is reported and not fatal.
- Interface, driven from outside through UI Automation on one Windows 11 PC: library (27 checks), Settings and languages (15), install queue with a stand-in WinGet (19), Uninstall, reading only (17), history and diagnostics (23).
- Motion: all three presets, track bounds, repeated reversals, native UIA state, press/cancel, live reduced-motion changes and completion callbacks. The mathematical checks also run headlessly in CI.

The four English images in `images/` were captured with 3.6; the 4.0 window is the same compiled interface. Logs are generated under ignored `test-logs/` and `dist/`, and CI logs accompany the release.

## Remaining coverage

No removal, leftover review or cleanup was driven through the 4.0 window: on the development PC the tests always go back, and CI has no interactive desktop. Those steps are covered through the engine boundary only. Stopping a queue or a removal midway, the file dialogs for saving and loading selections, downloading and applying an update from the Settings page, high contrast, a live change of the Windows theme or accent, and 48 of the 51 languages were not checked in the window.

4.0 was not run on Windows 10, nor on any PC other than the development one and the CI images. The complete WinGet inventory is not built in, so the retry of a failed install cannot be reached. An uninstaller that elevates through UAC and starts a child process was not run against the Rust engine. Removal scenarios cover the current user's registry only: machine-wide registrations, the 32-bit view, MSI and Store removals are not covered by fixtures.

The scenarios established for 3.5 in Windows Sandbox (real 7-Zip and Notepad++ removals, registry backup and restore, recycling and restore) were not repeated with 4.0. Native-speaker proofreading, screen readers, physical keyboard and pointer feel and real per-monitor DPI transitions need broader coverage. Bounded leftover discovery cannot prove that every leftover was found.

The local build retains MSB3644 where the .NET Framework 4.8 targeting pack is absent and installed GAC assemblies are used. The executable is unsigned and builds are not bit-for-bit reproducible. The CI build, source/archive hashes and public downloads are verified through the release workflow; BUILD-INFO.json records the compiler, the Rust toolchain and the hash of every build input.
