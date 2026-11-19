# Validation — 1nstall 4.0.0

How 4.0 was specified from the 3.6 code, compared with it and built is recorded phase by phase in [rewrite/](rewrite/README.md) (in Portuguese), with the evidence for each claim. Commands are in [DEVELOPING.md](DEVELOPING.md). Local checks use fictional apps and data beside the test build; no personal application is installed or removed.

## Current checks

- Catalog: 325 apps, 24 categories, 20 profiles, 200 shortlist mappings and 911 benchmark rows. The preserved taxonomy and provenance are in `catalog/`.
- Languages: 51 choices with 239 matching strings and valid placeholders.
- Engine rules: 77 Rust tests, and the oracle, which replays the behaviour recorded from the 3.6 helpers. Of 1552 recorded cases, 1527 are identical and the other 25 are listed, intentional differences; none is unexplained. The tests also read thirty thousand damaged copies of the files the engine keeps, and compare the WinGet command lines of an install with 3.6 run live.
- Removal, on GitHub's disposable Windows Server 2022 and 2025 machines: eight recorded fixture scenarios; fixture apps removed, scanned and cleaned through the boundary the window uses, one for the current user and one machine-wide in the 32-bit registry view with an uninstaller that hands the work to a child process; and a queue of two stopped midway.
- Real install: Sumatra PDF installed through the engine's queue on Windows Server 2025. The 2022 image has no WinGet.
- Update from 3.6: the released 3.6.0 executable applies a 4.0 build with its own updater, on both images.
- Packaged self-test: 31 checks through the engine boundary, including that an internal engine failure is reported and not fatal.
- Interface, driven from outside through UI Automation on one Windows 11 PC and on both CI images: library (27 checks), Settings and languages (15), install queue with a stand-in WinGet, including stopping midway and closing the window while it runs (36), Uninstall, reading only (17), history and diagnostics (23), the Windows file dialogs (26), and the window itself: smallest size, a name on every control, all 51 languages against `locales.json`, both themes and, on CI, the keyboard (28).
- The normal mode, on the CI images only: the window follows the Windows app theme and survives high contrast, settings are saved and read back, a fixture app is removed and its leftovers reviewed and cleaned, a removal is stopped midway (34 checks); an update is found, downloaded and applied from Settings by a build numbered 3.5.0 (9); and on Windows Server 2025 four real apps are installed with WinGet and removed with their own uninstallers (an executable, an NSIS, an MSI and an Inno Setup one), and a Microsoft Store app is removed (15).
- Release: the source archive alone builds the application, and the build signs with a test certificate (11 checks).
- Motion: all three presets, track bounds, repeated reversals, native UIA state, press/cancel, live reduced-motion changes and completion callbacks. The mathematical checks also run headlessly in CI.

The four English images in `images/` were captured with 3.6; the 4.0 window is the same compiled interface. Logs are generated under ignored `test-logs/` and `dist/`, and CI logs accompany the release.

## Remaining coverage

4.0 was not run on Windows 10, nor on any PC other than the development one and the CI images. The retry of a failed install is followed from its button to the selection with a complete inventory made by the test; the development PC has no PowerShell 7, so the real complete inventory was only asked for on CI. The CI machines run elevated, so the UAC prompt itself was only seen in manual use. A real restart request, a real WinGet failure and real package dependencies were not exercised.

No screen reader was used: the tests check that every control has a name and every card a description. DPI scaling other than 100 %, several monitors, touch, a live change of the Windows accent colour, the full Tab order, the animations as seen by a person, and the buttons that open other programs (logs, backups, websites) were not checked. Native-speaker proofreading remains open. Bounded leftover discovery cannot prove that every leftover was found.

The local build retains MSB3644 where the .NET Framework 4.8 targeting pack is absent and installed GAC assemblies are used. The executable is unsigned and builds are not bit-for-bit reproducible. The CI build, source/archive hashes and public downloads are verified through the release workflow; BUILD-INFO.json records the compiler, the Rust toolchain and the hash of every build input.
