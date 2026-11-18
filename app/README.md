# 1nstall 4.0 application

One .NET Framework executable, `1nstall.exe`: the compiled WPF interface of 3.6, hosted by plain C# with no PowerShell, over the Rust engine in `engine/`. The engine travels inside the executable as a resource and is loaded from an immutable cache.

This is work in progress. `Shell.cs` lists what is ported and what is not; the 3.6 application at the repository root is untouched and still builds with `build-windows.ps1`.

| File | Purpose |
| --- | --- |
| `Program.cs` | Entry point, test modes, start-up error path, assembly identity. |
| `Engine.cs` | Extracts and loads `oneinstall_engine.dll`; the C# side of the engine boundary. |
| `Shell.cs` | The main window, wired to the engine. |
| `1nstall.csproj` | Compiles `interface.xaml`, the 3.6 interface helpers in `src/` and the files above into one assembly. |
| `build.ps1` | Builds the engine, then the executable, into `dist\v4`. |
| `tests/update-bridge.ps1` | Proves the 3.6 updater accepts and applies the 4.0 executable. |

## Build

Needs Rust 1.86 or later. The C# side uses the compiler and MSBuild that ship with Windows.

```powershell
.\app\build.ps1
```

## Test modes

| Argument | Effect |
| --- | --- |
| `--self-test` | Exercises the engine through the boundary the interface uses, writes `self-test.log` beside the executable, shows no window. Exit code 0 means every check passed. |
| `--startup-test` | Shows the main window, writes the 3.6 timing marks to `startup-test.log`, and exits. |
| `--apply-update …` | The update step of 3.6 (`src/update-helper.cs`), unchanged. |

Test modes keep their cache in `runtime-cache` beside the executable. A normal start uses `%LOCALAPPDATA%\1nstall\Runtime`, as 3.6 does.

## The engine boundary

`oneinstall_engine.dll` exports C functions that return NUL-terminated UTF-16 JSON; every returned pointer goes back to `oi_free`. The functions are documented in `engine/ffi/src/lib.rs`.

## Updating from 3.6

The 3.6 updater accepts a release only if `1nstall.exe` is a .NET assembly named `1nstall` whose version equals the release tag. This executable is one, so 3.6 updates to 4.0 with no intermediate release. `tests/update-bridge.ps1` checks the identity anywhere, and on a disposable machine runs the released 3.6 executable's own apply step against the 4.0 build.
