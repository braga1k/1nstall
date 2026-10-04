# Remove apps and review leftovers

This describes removal and leftover review in **1nstall 3.5.0**.

Uninstall lists desktop registrations in HKCU/HKLM, in both registry views, and removable current-user Store applications. Hidden system entries, updates, frameworks and non-removable packages are excluded. Sparse desktop shell-integration packages with no app-list entry are also excluded: removing a context-menu extension is not the same as uninstalling its desktop application.

Select applications, then **Review & remove**. Desktop apps run their registered publisher uninstaller; MSI products use their validated product code with `msiexec /x`; Store apps use `Remove-AppxPackage` for the current account. Finish publisher dialogs and any administrator prompts. Unsupported uninstall commands retain a Windows Settings action. Stop after current app never kills an uninstaller.

The selection now behaves as a queue, like Install: each app shows Queued, Preparing, Removing, Verifying and its final outcome. Rows stay visible through removal, leftover review and inventory refresh until explicitly dismissed or a new queue is started. The progress bar counts processed apps, not an invented percentage of the publisher's work. Failed, cancelled and manual outcomes remain available to review/retry.

The registration is checked before launching and after completion. An exit code of zero alone is insufficient. Publisher launchers can exit while a child still removes files or shows a dialog: the worker tracks observed descendants with native process snapshots and waits for their handles to signal completion before verification and the next app. Process creation/exit times prevent following a reused PID. Stop after current app never terminates those processes. Saving history does not mutate live selection; selection is excluded from persisted history.

Tracking covers observed process descendants, not work handed to unrelated Windows services or an unobserved detached process. If registration remains, the result stays manual; finish the publisher steps and use **Check leftovers** to recheck the captured identity. Restart-required results remain blocked until a later Windows boot.

## What is checked

After removal, a background scan checks:

- The recorded installation folder. If `InstallLocation` was missing, the inventory can recover an existing executable location from the display icon or uninstaller.
- Exact product-name folders within Roaming, Local and LocalLow AppData, ProgramData, and both Program Files roots. Short names and combined architecture labels such as `Notepad++ (64-bit x64)` are normalized.
- Exact product-name keys within HKCU/HKLM `Software`, in 32-bit and 64-bit views.
- Individual missing-executable traces in AppCompat, UserAssist, MuiCache, Jump List and app-usage branches. Known-folder GUIDs and UserAssist ROT13 paths are resolved. Only the matching value is removed from these shared Windows keys.

The review distinguishes **Linked path** (recorded installation location or executable trace) from **Name match** (exact product-name candidate). A matching name is a reason to review, not proof that its contents are disposable. App data can contain settings, saves and personal work. Real file counts and logical byte sizes are measured during scanning; the disk total includes only inspected candidates.

## Review and confirmation

Disk and registry totals appear separately. Every row identifies the app, evidence and path; registry paths include hive and view. Details expands the recovery explanation. All candidates start unchecked. **Select linked paths**, **Select all** and **Clear selection** change the selection but never bypass confirmation.

The result remains visible after refreshing the installed-app list. Cleanup reports folders recycled, registry items removed and items not completed. A complete successful cleanup triggers the existing whole-window confirmation glow. Partial or failed cleanup keeps an attention summary and does not trigger that success glow. Motion, light/dark materials, monochrome appearance and reduced-motion behavior use the existing UI system.

## Protection and recovery

Before each selected item is removed, the app refreshes desktop registrations and repeats scope and shared-app checks. Reinstalling an app between review and cleanup blocks removal. Broad vendor roots, Windows, WindowsApps, Store Packages, Common Files, other user profiles and ordinary personal folders are excluded. Name collisions with installed products or publishers and overlapping installation locations also block candidates. Store package data remains managed by Windows.

Discovery is bounded to three levels, with a 20,000-entry limit per filesystem root and registry hive/view for each removed app. Candidate directory inspection is also capped at 20,000 entries. Linked/reparse-point trees and incomplete inspections are withheld. Inaccessible branches and limits are reported separately from an empty scan. This is not a whole-disk or whole-registry fuzzy search; an empty result does not prove that every residue is absent.

Folders go through Windows Shell recycle-on-delete with undo support and no deliberate permanent-delete fallback. Reported bytes are **data moved to the Recycle Bin**, not newly available disk capacity. If a recycle operation only partly completes, it is reported as not completed.

Registry removal requires a nonempty `reg.exe export` backup first. Whole product-key candidates export and remove that key. Value candidates export the containing key for recovery but remove only the reviewed value, preserving neighboring values. Machine-key removal can request elevation. Failed or cancelled operations retain their backup and report the outcome.

**Open backups** opens `%LOCALAPPDATA%\1nstall\Backups`. Each cleanup has `items.json`, `results.json`, individual `.reg` files and `RESTORE.txt` with the correct import command and registry view. Restore folders through Recycle Bin. Registry imports merge the exported values and can overwrite newer values with the same names; review the backup before importing it.

Logs and the last 100 removal identities are stored under `%LOCALAPPDATA%\1nstall`. They can contain app names and personal paths; review before sharing.

## Evidence and scope

Windows Sandbox testing on 2026-10-04 covered:

- GUID-owned fixtures: named nested AppData/product keys, missing InstallLocation, size accounting, re-registration after review, delayed publisher completion, exact trace boundaries, neighboring-value preservation, registry export/import and a Recycle Bin restore round trip.
- Official 7-Zip 26.03 x64: installed and opened, removed through its real publisher dialog; five real registry residues removed with five backups; repeat scan empty.
- Follow-up queue test with the final EXE and 7-Zip: selection stayed checked while its child dialog remained open; completion was verified only after closing that dialog. The Success row remained after leftover review and a refreshed empty inventory. This run found two product registry keys and deliberately kept them; it tests queue retention, not another cleanup run.
- Official Notepad++ 8.9.8.1 x64: installed and opened, then removed while explicitly retaining test settings in its publisher dialog. The actual Roaming profile contained 11 files / 845,590 bytes. That folder was recycled, two registry items were removed with backups, and a repeat scan was empty. Its sparse context-menu package was checked against the real manifest and excluded from the app list.

These tests modified only the Sandbox. They are not validation of every publisher, MSI/Store removal, Windows 10, all elevation paths or real reboot outcomes. The native fixture command is `tests/uninstall.ps1 -DisposableEnvironment`; the switch asserts isolation and does not create a VM. The WPF-only `tests/cleanup-ui.ps1` checks 51 languages, a 560 × 520 review, consent, selection, scroll endpoints, four appearances and partial/success summaries. Translation quality still needs native-speaker review.

`tests/uninstall-process.ps1 -DisposableEnvironment` exercises a native launcher/child/grandchild, registration removed before file work finishes, sequential execution, live selection versus saved history, stop-after-current and cancelled child verification. `tests/uninstall-queue.ps1` checks stable WPF rows, phase/progress updates, inventory refresh, manual/reverified results, retry, clearing, task faults and the compact window. Optional renders cover light/dark, accent/monochrome and the glass caption-button focus appearance; a real Sandbox screenshot additionally records pointer hover. Empty and registry-only leftover totals are covered without a PowerShell empty-sum exception.

The bounded discovery approach follows [BCU's drive scanner](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/Finders/Drive/CommonDriveJunkScanner.cs) and [product-key scanner](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/Finders/Registry/SoftwareRegKeyScanner.cs). Existing AppCompat/UserAssist/ROT13 adaptations retain their Apache-2.0 attribution and notices in `licenses/`. No BCU binaries are bundled. This does not implement the full BCU feature set: fuzzy confidence scores, force removal, orphan/portable discovery, services/tasks/startup cleanup and specialized providers remain outside this implementation.
