# WinGet integration decisions

> 3.2.0 scope: the Update Center was removed from the app. Upgrade/pin details below document retained backend logic and the earlier review, not an available 3.2.0 user workflow. Installed awareness and automatic catalog installation remain available.

Checked against current Microsoft documentation and public source on 2026-10-02. This is a supported-interface design review, not evidence of live package operations in this sandbox.

## Installed inventory

The preferred interface is [Microsoft.WinGet.Client Get-WinGetPackage](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Get-WinGetPackage.md), imported at minimum module version 1.7 using PowerShell 7 in its standard Program Files location. Package `Id`, `Source`, `InstalledVersion`, `AvailableVersions`, `IsUpdateAvailable` and `CompareToVersion` are read as structured objects. Only an exact ID/source match is used. WinGet's aggregate result does not expose an installation scope; the UI says so. Duplicate records are Unknown rather than arbitrarily choosing one. Guided or uncorrelated packages remain Unknown.

If structured discovery is unavailable, the official [export command](https://learn.microsoft.com/en-us/windows/package-manager/winget/export) supplies JSON with known source package identifiers and optional versions. Export may omit unmatched applications: positive exact matches can be Installed, while absence remains Unknown. Export is not a complete machine inventory and is never used to confirm updates. A complete structured absence can be Not installed.

Neither prerequisites nor source agreement acceptance are installed/performed silently during discovery. Missing prerequisites, source problems and timeouts are reported. Browsing is independent of the background task.

## Update discovery and execution

Only structured inventory with known installed and available versions, positive update availability and a `Lesser` comparison yields a candidate. No localized `winget upgrade` table is parsed. Unknown/latest versions, duplicate identities and unsupported sources stay ineligible.

The reviewed command uses the official [upgrade options](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade): one `--id`, `--exact`, source and explicitly reviewed `--version`. No `--all`, `--force`, `--include-pinned` or `--allow-reboot` is emitted. Before every execution/retry, fresh inventory, local holds and pins must still match the reviewed versions. Successful exit is followed by exact version verification; otherwise the outcome is Unknown. There remains a small race if another process changes state between the check and WinGet starting; 1nstall does not claim an atomic system-wide lock.

The [Microsoft pin documentation](https://learn.microsoft.com/en-us/windows/package-manager/winget/pinning) explains that an ordinary pin can still allow an individually requested upgrade. Therefore relying on the CLI's individual command alone would not respect the user's pin. 1nstall checks every pin itself and skips every pin type before invoking a command.

The Client API used here has no documented structured pin enumeration. The fallback checks CLI version 1.7 or newer and calls `pin list --disable-interactivity`. It accepts only the exact English empty message `No pins exist.` or a complete table with known invariant `Pinning`, `Blocking`, `Gating` rows each correlating to one exact installed package ID. Localized headers can differ; unfamiliar empty text, truncated rows, ambiguous matches, product-code-only pins and any unrecognized output withhold all updates. This conservative limit is intentional and visible, not an assertion that every locale is supported. Current public [PinFlow.cpp](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerCLICore/Workflows/PinFlow.cpp) confirms the table/empty-result structure. Future CLI changes may require adapting the parser.

1nstall holds are local exclusions by exact package ID across supported sources, persist until released and do not create/remove WinGet pins. Corrupt exclusions fail closed. Update selection is never preselected on ordinary discovery and never runs unattended by default. Retry only preselects newly eligible failed identities for review.

## Outcomes and limits

Exit/HRESULT handling uses Microsoft's [AppInstallerErrors.h](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h), Windows cancellation and MSI restart codes. Success, Failed, Cancelled, Restart required, Manual action required and Unknown remain distinct. Discovery has a timeout; active installers are not killed by Stop. Verification failure cannot erase a restart or cancellation result.

Source/name similarity cannot authorize package actions or filesystem cleanup. Automatic CLI installs use `--no-upgrade` so an install plan cannot silently become an update. Installed-state verification, pin parser compatibility, true user/machine/multiple-version behavior and publisher installer outcomes still require the isolated checks listed in [VALIDATION](VALIDATION.md).
