# UI prototypes

Phase 3 of the rewrite: the install library screen of 1nstall in three UI toolkits, all over the same Rust engine, built to choose one by measurement. The results and the recommendation are in [`docs/rewrite/fase-3/README.md`](../../docs/rewrite/fase-3/README.md).

These are prototypes of one screen. Nothing here installs or removes anything.

| Folder | What it is |
| --- | --- |
| `model/` | What every prototype shows: catalog, translations, install plan, installed apps, and the start-up clock. Uses `oneinstall-core` and `oneinstall-platform`. |
| `slint/` | The screen in Slint. `--renderer femtovg` or `--renderer software` picks how it draws. |
| `tauri/` | The screen as a web page in WebView2, through Tauri. |
| `ffi/` | The engine as a DLL with a C interface, for the WPF prototype. |
| `wpf/` | The 3.6 WPF interface hosted by plain C#, without PowerShell, calling the engine DLL. |
| `measure/` | The scripts that produced the numbers. |

## Build

The workspace is separate from `engine/`, so the engine's lock file and CI carry no UI dependencies. Versions are pinned by `Cargo.lock` to what Rust 1.86 can build: Slint 1.13.1 and Tauri 2.11.6.

```powershell
cargo build --release --locked
```

The WPF prototype needs only the .NET Framework compiler and MSBuild that ship with Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File wpf\build.ps1 -Out C:\short\path\wpf -EngineDll target\release\oneinstall_ffi.dll
```

## Options

Every prototype accepts the same options.

| Option | Effect |
| --- | --- |
| `--startup-test` | Draw the first screen, write `startup-test.log` beside the program, and exit. |
| `--lang <code>` | Interface language, for example `pt-PT`, `ar` or `ja`. The WPF prototype ignores it. |
| `--select <keys>` | Comma-separated app keys selected from the start, for example `extra_7zip,peace`. |

The Tauri prototype keeps its browser profile in `webview-data` beside the program.

## Measure

Put each prototype in a folder of its own with a short path, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File measure\measure.ps1 -Exe C:\short\path\oneinstall-slint.exe -Out slint.json -Arguments "--renderer software"
```

| Script | What it reports |
| --- | --- |
| `measure.ps1` | Time to ready and peak memory of the whole process tree, over 3 fresh and 10 warm runs. Also accepts the 3.6 executable. |
| `idle.ps1` | Memory of the process tree at rest, 8 seconds after start. |
| `inspect.ps1` | The UI Automation tree, a toggle of one card through it, and optionally a picture of the window. |

The clock starts when Windows creates the process. The 3.6 clock starts later, inside its launcher, so compare the two through the wall-clock column.
