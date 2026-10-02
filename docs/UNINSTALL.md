# Remove apps and review leftovers — 1nstall 3.2.0-review

Uninstall lists registered desktop applications from the current-user and machine uninstall registries, in both 32-bit and 64-bit views. It also lists removable Microsoft Store apps installed for the current user. Windows updates, hidden system entries, Store frameworks, resource packages and non-removable packages are excluded.

Search by name or publisher. Selection survives search and source filters. Review & remove shows the apps and requires fresh confirmation. Desktop apps use the registered publisher uninstaller; Windows Installer products use their validated product code with `msiexec /x`. Store apps use Windows’ [Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage?view=windowsserver2025-ps) for the current account. Apps with missing or unsupported commands remain visible with a Windows Settings action.

Removal runs one app at a time in the background. Complete any publisher dialog or administrator prompt. Stop after current app does not kill a running uninstaller. The app waits for active removal or scanning before closing. An uninstaller returning success is not treated as proof that its registration has disappeared.

## Check leftovers

Leftover scanning starts automatically after the original uninstallers finish. Any candidates open a separate, unchecked review; nothing is cleaned automatically. Check leftovers repeats the scan using local removal history, including after finishing a publisher dialog or restarting Windows. The scan outcome remains visible after installed-app refresh. A restart-required result withholds cleanup until a later Windows boot. Apps still registered are withheld; reinstalling an app or finding another registered product using the same name/location also blocks cleanup.

Candidates are deliberately narrow:

- The installation directory freshly captured from the exact registration before this removal, only after registration disappearance and ownership are verified and its leaf identifies the product.
- No display-name-only AppData/ProgramData folders or whole Software product keys. Name similarity is insufficient evidence of ownership. Historical entries without the new ownership/removal verification flags are withheld.
- Individual executable-path values in known AppCompat, UserAssist, MuiCache, Jump List and app-usage branches. Known-folder GUID paths and UserAssist ROT13 names are resolved. Candidates must point inside the recorded product installation directory, have no executable remaining and pass shared-app checks. The containing Windows key and unrelated values are retained.

Broad vendor directories, drive/profile roots, Windows, WindowsApps, Store Packages, Common Files, other users’ profiles and ordinary personal folders are not cleanup targets. Links/junctions and trees that cannot be inspected completely within the scan bound are withheld. Discovery is bounded to three levels and 20,000 entries per app (registry bound per hive/view). Limits and inaccessible branches are reported. The scan does not search the whole disk/registry for approximate name matches. The absence of candidates does not prove that every leftover has been found.

The review shows each path, its app and the disk/registry distinction. Registry rows include hive and view. All rows start unchecked. Select all checks every candidate; Clear selection unchecks them. Neither action grants consent. Select the paths you understand and confirm separately. Disk and registry counts are shown separately in the scan result; a scan with no detected disk candidate does not offer a disk cleanup item. Product folders may contain saved preferences, projects or other personal app data; keeping a candidate is a valid choice.

## Recovery and activity

Selected folders use the modern Windows Shell recycle-on-delete operation, with undo support. There is no deliberate permanent-delete fallback. If Windows cannot finish the operation, inspect Removal activity, the remaining folder and Recycle Bin. A partially completed operation is reported as not completed.

Before each individual registry value is removed, Windows `reg.exe export` must create a nonempty `.reg` backup. A value candidate exports its containing key for recovery, then deletes only the reviewed value. The backup can therefore include unrelated values from that key. Machine-key deletion may ask for administrator access. Cancelling or failing export/delete is recorded. The backup remains available.

Open backups opens `%LOCALAPPDATA%\1nstall\Backups`. Each cleanup creates an item record, individual registry exports and `RESTORE.txt` with the import command and the correct 32/64-bit registry view. Restore disk folders from Recycle Bin; restore registry exports using those commands, as administrator where indicated. Importing a key merges its backed-up values and does not undo later unrelated changes.

Activity is written to `%LOCALAPPDATA%\1nstall\Logs`. Removal history is in `%LOCALAPPDATA%\1nstall\uninstall-history.json` (up to 100 recent target identities). These files can include application names and personal paths. Review them before sharing.

## Scope and validation

The workflow and bounded discovery approach follow [Bulk Crap Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller). AppCompat/UserAssist scanning and ROT13 decoding are adapted from its Apache-2.0 sources at commit `30da609384c98ba6e35c6530129541ea4ff3970a`, with stricter path boundaries and current shared-app checks. The BCU runtime/binaries are not bundled. Copyright, upstream NOTICE, license and modification notices are in `licenses/` and embedded in the executable, available through Licenses & credits. This is an independent modified product, not an upstream BCU release. It does not implement the full BCU feature set: fuzzy confidence ranking, force uninstall, portable/orphan discovery, arbitrary cleanup commands, broken-registration deletion, services/tasks/startup cleanup, specialized game-store providers or silent-uninstaller automation.

The original release described native fixture checks. This review does not repeat or inherit those as current evidence. Final helper logic and WPF consent checks pass; the revised native fixture test requires `-DisposableEnvironment` and has not run here. It deliberately retains name-only AppData/product keys and tests cleanup only for verified install locations and executable-path values. No personal app or publisher installer was removed.

Publisher dialogs, MSI/Store removal, HKLM UAC, actual pending restarts and recycle/restore require the isolated tests in [VALIDATION](VALIDATION.md). Native compositor capture failed in this environment because the desktop handle was unavailable. Actual high contrast and OS scaling remain unverified.

Windows API references: [uninstall registration](https://learn.microsoft.com/en-us/windows/win32/msi/uninstall-registry-key), [localized package labels](https://learn.microsoft.com/en-us/windows/win32/api/shlwapi/nf-shlwapi-shloadindirectstring), [recycle and undo flags](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifileoperation-setoperationflags).

Version 3.1.4 gives the unchecked square a hit-test surface, so clicking its center selects the app. Installed-search hints hide on focus; entered queries are preserved.
