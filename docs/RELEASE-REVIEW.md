# 3.3.0 release build

The project owner authorized the stable 3.3.0 release on 2026-10-03 with the current behavior. See VALIDATION.md for actual checks and remaining coverage.

The Windows workflow builds the committed source, runs catalog, reliability and packaged self-tests, then creates a draft release from release/3.3.0. It verifies every uploaded asset name and SHA-256 digest against the build before publishing v3.3.0 as latest. Existing published releases are never overwritten.

BUILD-INFO.json records the source commit, dirty state, source-input hashes, toolchain and executable hash. The source archive contains the exact build-input bytes, including Windows line endings. Timestamped metadata means bit-for-bit reproducibility is not claimed. Rebuild source with build-windows.ps1; a source ZIP without Git records null commit/dirty fields instead of borrowing an unrelated parent repository identity.

The executable is unsigned. Optional signing requires an authorized code-signing certificate and HTTPS timestamp service passed to build-windows.ps1. No certificate or new project license has been invented for this release. Third-party notices are embedded and distributed.

The portable package includes the executable, notes, notices, metadata and CI logs. Generated executables are distributed through Releases instead of stale copies under bin/ in the source tree.
