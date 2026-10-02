# 3.2.0-review release handoff

The deliverable is an unsigned Windows x64 prerelease. The owner authorized publication on 2026-10-02 with isolated Windows testing deferred. No 9/10 score or production readiness is asserted. [VALIDATION](VALIDATION.md) distinguishes actual checks, fictional/simulated tests and unavailable external checks.

## Build and inspect

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-windows.ps1
Get-FileHash .\dist\1nstall.exe -Algorithm SHA256
```

The .NET builder produces `1nstall.exe`, `BUILD-INFO.json`, `SHA256SUMS.txt` and `THIRD-PARTY-NOTICES.txt`. Build metadata records upstream provenance, local reviewed commit, dirty state, UTC build time, Windows/PowerShell/compiler versions and source-input hashes. Git is optional when rebuilding an extracted source ZIP. If its own repository identity is unavailable, commit/dirty fields remain null instead of borrowing a parent repository identity. Source-input hashes are still recorded. Timestamped metadata makes builds attributable; bit-for-bit reproducibility is not claimed. The executable extracts its embedded script into a temporary directory and does not require the source tree, Python or Zig.

The release review ZIP includes the runnable executable, notices, metadata, checksums and packaged test logs. The source review ZIP and patch carry source changes, tests, documentation and rendered evidence. The local baseline is a materialized upstream snapshot; the patch is against that baseline, not a GitHub pull request. Publication and remote CI remain owner actions.

## Signing support

No signing certificate or authorized credential was supplied, so this build is unsigned. When the owner has an authorized code-signing certificate with private key in CurrentUser/My and a trusted HTTPS timestamp service:

```powershell
.\build-windows.ps1 -CertificateThumbprint '<authorized thumbprint>' -TimestampServer 'https://<authorized timestamp service>'
```

The builder checks the private key/code-signing EKU, signs SHA-256, timestamps and requires a Valid signature result. Verify the final signature and regenerate/check hashes after signing. Secret material must not be committed or passed to unauthenticated services. An HSM/remote signing provider needs owner-specific integration; none is presumed here.

## Owner actions before a stable release

1. Review the diff, exact commands, cleanup boundaries and third-party notices; confirm the original-code license. The existing project declares no general original-code license, and this work does not choose one.
2. Push the reviewed source and run the prepared Windows headless CI. Inspect its artifacts rather than treating the unexecuted workflow as a pass.
3. Provide isolated interactive Windows environments and finish EXE/MSI/Store, UAC, reboot, cleanup restore, live Client/CLI/pin/localization and accessibility/scaling checks in VALIDATION. Fix any resulting regressions before release.
4. Decide supported Windows/WinGet/Client versions based on those results. Explain the additional Update Center prerequisites to users.
5. Supply authorized signing setup, verify the signed build, rerun packaged checks and replace unsigned review checksums.
6. Preserve license/NOTICE files and manually approve release notes, release assets and publication. No update or publishing credentials were used here.

Snapshots restore selections, not personal data/settings/credentials or identical versions. External installed identities absent from 1nstall's catalog are previewed as unavailable/manual; import does not turn arbitrary package identifiers into unattended commands. Cleanup intentionally finds fewer candidates when ownership is uncertain. These are visible limits, not hidden success claims.
