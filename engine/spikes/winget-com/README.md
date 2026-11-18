# Spike: WinGet COM API from a plain Rust process

Question: can an unpackaged, non-elevated Rust process use the WinGet COM API (`Microsoft.Management.Deployment`) to read the complete installed inventory, without PowerShell 7 or the `Microsoft.WinGet.Client` module?

Answer, measured on Windows 11 with WinGet 1.29.380: **yes, on one condition**.

| Setup | Result |
| --- | --- |
| `CoCreateInstance` of `PackageManager`, nothing next to the program | Fails on the first interface call: `0x80073D54`, no proxy registration for the interface |
| Same, with `Microsoft.Management.Deployment.winmd` next to the program | Works: local catalog in 0.3 s; composite catalog (installed + winget) in 0.8 to 3.5 s |
| With Microsoft's factory DLL next to the program but no `.winmd` | Fails the same way |
| On a GitHub Actions runner (elevated, no interactive session), through the PowerShell module | Fails: `0x800706BA`, the COM server is unavailable |

So the engine must ship the `.winmd` beside its executable, and must keep a fallback (`winget export`) for contexts where the COM server cannot start.

The composite catalog returned the same number of winget-correlated packages (71) as `winget export` on the same machine.

## Run

```bash
cargo run -p gen
cargo build -p spike
```

Copy `Microsoft.Management.Deployment.winmd` next to `spike.exe` before running it. The program prints counts only.

`Microsoft.Management.Deployment.winmd` comes from the NuGet package `Microsoft.WindowsPackageManager.ComInterop` 1.29.380 (MIT, microsoft/winget-cli). The class identifiers are the ones declared in the App Installer package manifest.
