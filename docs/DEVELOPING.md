# Build, test and release

## Repository map

| Location | Purpose |
| --- | --- |
| `src/` | Native .NET/WPF launcher, UI, motion, Windows integration and PowerShell UI helpers |
| `interface.xaml`, `vexan_installers.ps1` | Window resources and application entry point |
| `catalog.json`, `profiles.json`, `locales.json` | Runtime data |
| `assets/` | Original brand vectors; `src/1nstall.ico` is the runtime icon |
| `docs/catalog/` | Catalog taxonomy, review and provenance used by the catalog checks |
| `docs/images/` | Current English screenshots used by the README |
| `tests/` | Offline checks, disposable fixtures and native UI checks |
| `scripts/`, `.github/workflows/` | Icon generation, packaging and release automation |
| `licenses/` | Required upstream licence and attribution notices |
| `dist/`, `test-logs/` | Ignored build outputs and test evidence |

Historical screenshots, logs and release notes are available through earlier Git tags and GitHub Releases. The legacy Python/Zig/C launcher was removed in 3.6; the Windows build is the supported standalone build.

## Run and build

Use Windows x64, Windows PowerShell 5.1 and .NET Framework 4.8/WPF. Python 3.10+ is needed for the catalog and locale checks only. A .NET Framework 4.8 targeting pack avoids MSB3644; Windows' compiler and MSBuild otherwise resolve installed assemblies through the GAC.

```powershell
# Run from source, or double-click script_allower.cmd.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\vexan_installers.ps1
# Build the standalone executable.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-windows.ps1
```

Output: `dist/1nstall.exe`. Rebuild after changing embedded source, data or assets. `scripts/build-brand.ps1` regenerates the runtime ICO from `assets/brand-mark.svg`, with preview exports in `dist/brand` by default.

## Checks

```powershell
python tests/catalog.py
python tests/locales.py
powershell.exe -NoProfile -STA -File tests/reliability.ps1
powershell.exe -NoProfile -STA -File tests/elastic-motion.ps1 -Headless
```

After building, the executable accepts `--self-test`, `--smoke-test` and `--manager-test`. Each writes its log beside the executable. Native interactive checks:

```powershell
powershell.exe -NoProfile -STA -File tests/elastic-motion.ps1
powershell.exe -NoProfile -STA -File tests/scrolling.ps1
powershell.exe -NoProfile -STA -File tests/appearance.ps1
powershell.exe -NoProfile -STA -File tests/startup-opening.ps1
powershell.exe -NoProfile -STA -File tests/cleanup-ui.ps1
powershell.exe -NoProfile -STA -File tests/uninstall-queue.ps1
```

UI fixtures use fictional apps. Run destructive fixture checks only in a disposable Windows VM; `tests/uninstall.ps1 -DisposableEnvironment` declares isolation but does not create it. The [validation guide](VALIDATION.md) distinguishes fixture results from live installer and hardware coverage.

Public screenshots always use English. Generate to an ignored directory, inspect them, then copy the four README images into `docs/images/`:

```powershell
powershell.exe -NoProfile -STA -File tests/screenshots.ps1 -PreviewDirectory dist/screenshots
```

## Release

Update the launcher assembly version, manifest, window title, Settings version, changelog, release notes, README links and workflow release branch together. Build metadata reads the executable version; packaging reads the metadata instead of keeping another version constant.

Commit before the final build. `scripts/package-release.ps1` requires a clean build from HEAD and fresh output directories. It verifies source-input hashes, creates portable/source ZIPs and computes asset checksums. The source ZIP preserves exact working bytes, including Windows line endings. Timestamped metadata means bit-for-bit reproducibility is not claimed.

Windows CI runs catalog, locale and reliability checks, builds, runs headless elastic-motion checks and the packaged self-test, then packages the assets. Pushing the configured `release/3.6.0` branch creates a draft, verifies every uploaded asset name and SHA-256 digest, then publishes the stable release as latest. Existing published releases are never overwritten.

Release assets include the executable, portable/source ZIPs, BUILD-INFO.json, notices, checksums and test logs. Download the published assets and verify hashes and the executable tests before reporting publication complete.

The executable is unsigned. Optional signing uses an authorized certificate and HTTPS timestamp service passed to `build-windows.ps1`. No certificate or general project licence is supplied by this workflow.
