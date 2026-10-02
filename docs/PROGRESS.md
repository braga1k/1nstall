# Review progress

Source baseline: braga1k/1nstall commit c97f780a05726bbaaea11d0636170a9126bd0cf5, retrieved byte-for-byte through GitHub connector (shell network unavailable). Local Git baseline is a materialized source snapshot, not an upstream clone. No AGENTS.md is present in the upstream tree or requested workspace root.

## Milestones
1. Baseline and reliability: recursive dependencies, exact commands, verified outcomes, conservative cleanup.
2. Discovery and installed library: welcoming view, details, background structured inventory.
3. Reviewed updates, portable snapshots, history and redacted diagnostic review.
4. Regression checks, Windows CI, release build/checksums and evidence.

## Baseline evidence (2026-10-02)
- Windows 10.0.26100, x64; Windows PowerShell 5.1.26100.9444, CLR 4.0.30319.42000.
- Python 3.13 unavailable. Python 3.14.3 catalog check PASS: 325 apps, 24 categories, 20 profiles, 911 research rows.
- Existing SelfTest and WPF SmokeTest PASS. Rendered previews saved as before*.png.
- Existing .NET Windows builder PASS; source-built baseline executable produced.
- Demonstrated code gaps: shallow dependency planner, dependent installers proceed after dependency failure, no installed-state verification of zero-exit install, incorrect already-installed HRESULT, registry argument quoting around trailing backslashes, removal lacks structured per-app outcomes.
- Shell writes to workspace root/Documents rejected. Work continues in writable temporary directory. Shell network proxy cannot connect; connected GitHub service available.
- Desktop helper sees only Parsec window; shell-launched WPF app is not visible to that helper. Interactive keyboard/desktop capture unavailable in current session. Rendered WPF evidence is explicitly separate.
- No disposable VM or publisher installers provisioned. Real-app install/update/remove and cleanup tests must run only in an isolated Windows environment; no everyday app has been modified.

## Completed
- Recursive dependency planner, safe exact commands, background inventory, state verification and structured per-app outcomes.
- Essentials, remembered library views, card details/statuses, narrow layout and contrast resources.
- Reviewed Update Center with fail-closed pin checks/local holds, stop-after-current and fresh retry checks.
- Backward-compatible validated snapshots, import preview, history and redacted diagnostic review.
- Conservative fresh ownership cleanup; consent, backups, recycling and protected/shared checks preserved.
- Catalog PASS; 66 headless regressions PASS; existing WPF smoke PASS; manager WPF fixture suite PASS. Before/after rendered evidence captured.
- Windows headless CI, authorized-signing support, release notes, capability documentation and validation matrix.

## Release preparation
Final source review complete. Executable rebuilt from committed clean source; standalone self-test, WPF smoke-test and manager-test all PASS in a separate folder without source files. Checksums, metadata, review source ZIP and patch prepared. The owner subsequently authorized public prerelease publication; isolated Windows testing remains deferred.

## Deferred isolated Windows work (user-directed) and external setup
- User deferred isolated Windows testing until later; no disposable VM: publisher EXE/MSI/Store, actual upgrades/removals, UAC, reboot and native fixture cleanup remain unexecuted.
- Desktop not accessible to helper: native input, compositor, actual high contrast and OS 100/150/200% scaling remain unverified. Rendered WPF evidence is not a replacement.
- PowerShell 7/live usable WinGet unavailable: supported live inventory/update/pin behavior needs isolated validation.
- No authorized signing credentials: unsigned review build; owner supplies setup.
- Remote CI not run until owner pushes; Python/Zig alternate builder not built.
- Original-code license remains the owner's decision.

See VALIDATION.md for evidence and RELEASE-REVIEW.md for concrete owner actions.
