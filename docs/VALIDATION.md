# Validation — 1nstall 3.6.0

Release preparation authorized by Vitor on 2026-10-12. Local checks use fictional apps and temporary data; no personal application is installed or removed. Commands and release verification are in [DEVELOPING.md](DEVELOPING.md).

## Current checks

- Catalog: 325 apps, 24 categories, 20 profiles, 200 shortlist mappings and 911 benchmark rows. The preserved taxonomy and provenance are in `catalog/`.
- Languages: 51 choices with 239 matching strings and valid placeholders. UI checks cover right-to-left layouts and selection preservation.
- Reliability: 56 headless regressions for package identity, import validation, paths, cleanup boundaries and history.
- Motion: all three presets, track bounds, repeated reversals, native UIA state, press/cancel, live reduced-motion changes, completion callbacks and recycled templates. The mathematical checks also run headlessly in CI.
- Packaged self/smoke/manager suites: selection/model synchronization, queues, profiles, settings, diagnostics, updater integrity and rendered layout.
- Scrolling: minimum and wider layouts, mixed row heights, filtering, resize, both selection queues, categories, menus, settings and dialogs.
- Appearance: opening/main-window background continuity, accent and monochrome themes, with transparent and opaque fallback renders.
- Cleanup/Uninstall queue fixtures: separate consent, disk/registry totals, partial results, stable rows, progress, refresh, retry, faults and minimum-window layout.

Current public captures are the four English images in `images/`; Uninstall examples are fictional. Logs and additional captures are generated under ignored `test-logs/` and `dist/`, and CI logs accompany the release. Older evidence remains in its release tag instead of being mixed with current documentation.

## Established live evidence

The 3.5 preparation tested actual 7-Zip and Notepad++ EXE removals in Windows Sandbox, retained AppData, registry backup/restore, recycling/restore, delayed publisher-child completion and re-registration protection. Those checks validate those scenarios at that time, not all uninstallers or a new live removal test for 3.6. Scope and recovery are documented in [UNINSTALL.md](UNINSTALL.md).

## Remaining coverage

Native-speaker proofreading, screen readers, physical keyboard/pointer feel, high-contrast hardware sessions and real per-monitor DPI transitions need broader coverage. Raster/layout checks are not accessibility certification. Busy-dispatcher/GPU smoothness is not guaranteed by the native keyframe tests.

Broader EXE/MSI/Store installs and removals, elevation, actual reboot outcomes, services/detached publisher processes, Windows 10 and different WinGet Client versions still require isolated end-to-end checks. Bounded leftover discovery cannot prove that every residue was found.

Windows previously denied activation of a background startup fixture, so its foreground assertions were explicitly skipped. Internal ownership/handoff checks do not establish the Explorer double-click scenario. Earlier local timing samples are not a guarantee for this release or every machine.

The local build retains MSB3644 where the .NET Framework 4.8 targeting pack is absent and installed GAC assemblies are used. The executable is unsigned. The CI build, source/archive hashes and public downloads are verified through the release workflow; BUILD-INFO.json and checksums record their provenance.
