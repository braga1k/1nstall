# Settings — 1nstall 3.4

Open **Settings** at the bottom of the navigation pane. Preferences are saved per Windows user in `%LOCALAPPDATA%\1nstall\settings.json`.

- **Theme:** System, Light or Dark, applied immediately. Both appearances retain gradient materials, reflective edges, ambient light and pointer reflections. The opening uses the same appearance. Windows high contrast takes precedence.
- **Accent colour:** use the Windows accent, or switch it off for black, white and grey throughout. Both themes retain their gradients, depth and interactions. This changes only 1nstall.
- **Language:** System or one of 51 offline language choices. Portuguese has only `pt-PT`; Portuguese system variants resolve to it. Arabic and Urdu use right-to-left layout. Switching languages preserves selections. [Coverage and translation status](localization.md).
- **Automatic updates:** enabled by default, with a manual check and a restart action when an update is ready. This updates 1nstall itself. It does not update installed apps.

## Updates

The compiled .NET executable checks the latest stable GitHub release in the background on launch. It downloads only a newer stable version, verifies its SHA-256 against the release digest or checksum file, and checks the executable's assembly identity and version. After the app closes, a separate worker waits for it to exit and atomically replaces the executable. The previous executable is retained as `1nstall.exe.previous`.

Downloaded versions and update workers are under `%LOCALAPPDATA%\1nstall\Updates`. A failed swap preserves the original executable and records `update-error.log`; the next launch reports the problem. A writable executable folder is required. Script and legacy Zig builds require manual application updates.

Existing 3.3 installations can receive 3.4 through this updater. Versions before 3.3 require a manual download once.

## Appearance and motion

Settings cards and buttons share the pointer-following light used in Install and Uninstall. The light appearance uses layered pearl-grey materials. Hover effects and borders follow the current palette even after the pointer has moved. Windows animation, transparency and high-contrast preferences control the available effects.

Segoe UI is used throughout. The minimum window size is 1040 × 540 DIP, with space for card movement and translated profile controls. Install and Uninstall use symmetrical 20-DIP scrollbar gutters; activity bars end at their app-card edge.

Tests cover all 51 locales, preserved selections, atomic preference persistence, appearance changes, monochrome output, scroll endpoints, opening continuity and disposable updater operations. Native-speaker review, physical accessibility and other Windows configurations retain the limits documented in [VALIDATION.md](VALIDATION.md).
