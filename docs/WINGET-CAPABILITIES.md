# WinGet integration

Automatic catalog installation uses WinGet. The application does not offer an Update Center, package pin controls or unattended third-party upgrades. Settings updates 1nstall itself.

## Installed inventory

The preferred interface is [Microsoft.WinGet.Client Get-WinGetPackage](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Get-WinGetPackage.md), imported at minimum module version 1.7 using PowerShell 7 in its standard Program Files location. Id, source, name and installed version are read as structured objects. Only exact ID/source matches are used. Aggregate results do not expose installation scope. Duplicate records, guided and uncorrelated packages remain Unknown.

If structured discovery is unavailable, the official [export command](https://learn.microsoft.com/en-us/windows/package-manager/winget/export) supplies JSON with known package identifiers and optional versions. Export may omit unmatched applications: exact positive matches can be Installed, while absence remains Unknown. A complete structured absence can be Not installed.

Discovery does not silently install prerequisites or accept source agreements. Missing prerequisites, source problems and timeouts are reported. Browsing remains independent of the background task.

## Installation and outcomes

Each automatic install uses an exact package ID and supported source. `--no-upgrade` prevents an install plan from silently becoming an upgrade. Publisher dialogs and elevation can still require user input. Guided entries open the official website for manual installation.

Exit/HRESULT handling distinguishes Success, Failed, Cancelled, Restart required, Manual action required and Unknown. Active installers are not killed by Stop. Installed-state verification cannot erase a restart or cancellation result. Outcome mappings are checked against [AppInstallerErrors.h](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h), Windows cancellation and MSI restart codes.

Source/name similarity cannot authorize package actions or cleanup. True user/machine/multiple-version behavior, live Client variants and publisher outcomes retain the limits in [VALIDATION.md](VALIDATION.md). This describes the integration implemented here; it is not a fresh audit of every WinGet release.
