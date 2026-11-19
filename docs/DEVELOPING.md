# Build, test and release

## Repository map

| Location | Purpose |
| --- | --- |
| `app/` | The 4.0 application: the C# window over the engine, its build script and its UI tests |
| `engine/` | The Rust engine: rules (`core`), Windows access (`platform`), the boundary the window calls (`ffi`), test harness and a read-only CLI |
| `interface.xaml` | The window and its resources, compiled into the executable |
| `src/` | Motion, appearance, window and update helpers compiled into 4.0, the icon and the manifest. `package-helper.cs` and `uninstall-helper.cs` are the rules of 3.6, kept because the oracle runs them to compare; `ui-helper.cs` and `ui.csproj` are kept for the phase 3 prototype in `engine/prototypes/wpf`. The rest of the 3.6 application is at the tag `v3.6.0` |
| `oracle/` | The recorded 3.6 behaviour and the scripts that record it |
| `docs/rewrite/` | How 4.0 was specified, compared with 3.6 and built, phase by phase (in Portuguese) |
| `catalog.json`, `profiles.json`, `locales.json` | Runtime data |
| `assets/` | Original brand vectors; `src/1nstall.ico` is the runtime icon |
| `docs/catalog/` | Catalog taxonomy, review and provenance used by the catalog checks |
| `docs/images/` | Current English screenshots used by the README |
| `tests/` | Catalog and language checks, the motion test, and the two 3.6 removal tests the oracle runs. The tests of the 4.0 window are in `app/tests/` |
| `scripts/`, `.github/workflows/` | Icon generation, packaging and release automation |
| `licenses/` | Required upstream licence and attribution notices |
| `dist/`, `test-logs/` | Ignored build outputs and test evidence |

Historical screenshots, logs and release notes are available through earlier Git tags and GitHub Releases. The legacy Python/Zig/C launcher was removed in 3.6; the Windows build is the supported standalone build.

## Run and build

Use Windows x64, Windows PowerShell 5.1 to run the scripts, .NET Framework 4.8/WPF and Rust 1.86. Python 3.10+ is needed for the catalog and locale checks only. A .NET Framework 4.8 targeting pack avoids MSB3644; Windows' compiler and MSBuild otherwise resolve installed assemblies through the GAC.

```powershell
# Build the standalone executable, with its notices, build metadata and checksums.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-windows.ps1
# Build only the executable, into a folder of your choice.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\build.ps1 -Out C:\some\folder
```

Output: `dist/1nstall.exe`. There is no run-from-source mode in 4.0: rebuild after changing source, data or assets. The build stops if a Rust component linked into the engine is not named, with its version, in `licenses/THIRD-PARTY-NOTICES.txt`. `scripts/build-brand.ps1` regenerates the runtime ICO from `assets/brand-mark.svg`, with preview exports in `dist/brand` by default.

## Checks

```powershell
python tests/catalog.py
python tests/locales.py
# In engine/: format, lint and the rules against the recorded 3.6 behaviour.
cargo fmt --check; cargo clippy --locked --all-targets -- -D warnings; cargo test --locked
powershell.exe -NoProfile -STA -File tests/elastic-motion.ps1 -Headless
```

After building, the executable accepts `--self-test`, `--startup-test` and `--ui-test`. The first two write a log beside the executable. `--ui-test` opens the window with fixed preferences, keeps its data beside the executable, and refuses to remove or clean anything. Checks that need an interactive desktop:

```powershell
powershell.exe -NoProfile -STA -File tests/elastic-motion.ps1
powershell.exe -NoProfile -File app/tests/library-ui.ps1 -Exe dist/1nstall.exe
powershell.exe -NoProfile -File app/tests/settings-ui.ps1 -Exe dist/1nstall.exe
powershell.exe -NoProfile -File app/tests/uninstall-ui.ps1 -Exe dist/1nstall.exe
powershell.exe -NoProfile -File app/tests/history-ui.ps1 -Exe dist/1nstall.exe
# The stand-in WinGet is built by `cargo build -p oneinstall-harness` as oracle-fixture.exe.
powershell.exe -NoProfile -File app/tests/queue-ui.ps1 -Exe dist/1nstall.exe -StandIn path\to\oracle-fixture.exe
```

These tests install and remove nothing; the test modes keep their data beside the executable, so run them from a short path. The scripts that drove the 3.6 application were removed with it; `app/tests/` has what replaced them. Destructive fixture checks run only where `ORACLE_DISPOSABLE=1` declares a disposable machine, as the `oracle` workflow does; the variable declares isolation but does not create it. The [validation guide](VALIDATION.md) distinguishes fixture results from live installer and hardware coverage.

Public screenshots always use English. The four README images were captured with 3.6, whose window 4.0 compiles unchanged. `app/tests/window-ui.ps1 -Pictures <folder>` saves pictures of the 4.0 window in each state.

## Release

Update the assembly version and `Program.Version` in `app/Program.cs`, the engine version in `engine/Cargo.toml`, the manifest, the window title, changelog, release notes, README links and workflow release branch together. Build metadata reads the executable version; packaging reads the metadata instead of keeping another version constant.

Commit before the final build. `scripts/package-release.ps1` requires a clean build from HEAD and fresh output directories. It verifies source-input hashes, creates portable/source ZIPs and computes asset checksums. The source ZIP preserves exact working bytes, including Windows line endings. Timestamped metadata means bit-for-bit reproducibility is not claimed.

Windows CI runs the catalog and locale checks and the engine tests, builds, runs headless elastic-motion checks and the packaged self-test, then packages the assets. Pushing the configured `release/4.0.0` branch creates a draft, verifies every uploaded asset name and SHA-256 digest, then publishes the stable release as latest. Existing published releases are never overwritten.

Release assets include the executable, portable/source ZIPs, BUILD-INFO.json, notices, checksums and test logs. Download the published assets and verify hashes and the executable tests before reporting publication complete.

The executable is unsigned. Optional signing uses an authorized certificate and a timestamp service passed to `build-windows.ps1`; its address must start with `http://`, the only form Windows PowerShell 5.1 accepts. No certificate or general project licence is supplied by this workflow.
