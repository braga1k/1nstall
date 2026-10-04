# Changelog

## 3.4.0 - 2026-10-04

- Add coordinated entrances, hover/press feedback, selection motion and a whole-window glow after verified installation/removal success, respecting Windows motion preferences.
- Show a themed opening while the main app loads, sharing its light/dark/accent/monochrome background and native material. Transfer ownership before closing the opening to improve foreground handoff.
- Expand to 51 offline language choices covering national official European languages, Japanese and existing languages. Portuguese remains pt-PT only; native-speaker review remains pending.
- Restore Segoe UI, reserve space for animated controls, enforce a 1040 × 540-DIP minimum window and adapt profile controls to translated labels.
- Dim confirmed installed apps while retaining interaction; remove app-description hover popups and keep Details/F1.
- Center both library scrollbars in matching gutters and fix empty scroll tails across lists and menus.
- Rebuild the README with current English screenshots and correct historical 3.3 screenshots to English.
- Extend appearance, startup, scrolling and locale checks; target .NET Framework 4.8 explicitly for the WPF APIs in use.

## 3.3.0 - 2026-10-03

- Add Settings with persistent System/Light/Dark themes, optional Windows accent and ten interface languages; Portuguese is pt-PT only, with right-to-left Arabic and Urdu.
- Check for stable 1nstall updates in the background, verify release checksums and executable identity, then apply on exit while retaining the previous executable.
- Match library margins, align activity panels with app cards and share Install's moving hover light with Uninstall.
- Preserve gradient materials, reflections and depth in the light appearance; disabling Windows accent makes either theme fully monochrome. Extend pointer-following light to Settings cards and buttons.
- Preserve selections while changing preferences; extend local geometry, language, theme, persistence and updater validation. See [settings and current limits](docs/SETTINGS.md).

## 3.2.0 - 2026-10-02

- New centered vector logo and violet-and-sage Windows icon.
- Symmetrical glass sidebars, consistent search and filter controls, clearer categories and smoother text.
- Compact cards with stable sizing; descriptions and installed-state details move into the integrated Details window. Numbers sort first and symbol-prefixed names last.
- Both modes use a Selection panel listing chosen apps with individual remove controls. Clear selection in Uninstall now clears the list checkboxes correctly, including after filtering.
- Matching interactive glass effects and a fixed scrollbar gutter keep selection controls aligned.
- Compiled WPF interface and native helpers, in-process PowerShell, parallel preparation and cached startup profiles retain the existing animations.
- Installed awareness, portable setup snapshots, operation history and reviewed diagnostic exports.
- Essentials and the Update Center removed; Buy me a beer added for optional support.

- Publish as the latest stable release with updated documentation, screenshots, source archives, checksums and build metadata.

## 3.2.0-review - 2026-10-02 (prerelease)

- Add Essentials, remembered library views, descriptions/methods/statuses and keyboard-accessible app details.
- Correlate installed apps only through exact WinGet identities; expose partial, ambiguous and guided results as Unknown. Refresh asynchronously after operations and on request.
- Add explicitly reviewed, exact-version updates; respect all WinGet pins and local holds, stop after current and recheck before retry. Unknown update versions stay ineligible.
- Extend existing selection profiles with validated installed-app snapshots and import previews. No commands or executable content are accepted.
- Add timestamped per-app history, actionable outcomes, detailed logs and reviewed redacted diagnostic export.
- Fix recursive dependencies, dependency failure blocking, Windows argument escaping, process output draining and state verification.
- Restrict cleanup to verified removal and fresh ownership evidence; retain separate consent, backups, recycling and shared/protected-location checks.
- Add 66 headless regression checks, rendered WPF workflow evidence, Windows CI, optional authorized signing, checksums and source-input build metadata.
- Publisher-installer/Store/reboot/native desktop tests remain external release gates; no readiness or quality score is claimed.


## 3.1.4 - 2026-10-02

First public release under the **1nstall** name. Includes work developed since First Install 2.8.

- Rebrand the app, launchers, build outputs, documentation and downloads.
- Review all 325 applications into 24 task categories across four expandable groups. Separate video editing from playback and support meaningful secondary categories.
- Add catalog/category audits, a 200-app comparison and 911 coverage rows, distinguishing sourced gaps from unverified research leads.
- Introduce the quiet glass interface, real Desktop Acrylic on supported Windows 11, adaptive background contrast, reduced-motion/opaque fallback and Segoe UI Variable typography.
- Start in All apps with category groups closed. Integrate window controls, remove the separate title band and outer accent rim, and disable native DWM frame painting.
- Expand existing profile selections and add remote work, illustration, photography/RAW, home media, web development and game development. Twenty profiles contain 8-11 apps each and use the original dropdown.
- Inventory registered desktop and current-user Store apps; add source/publisher search, batch review, sequential original uninstallers and stop-after-current behavior.
- Automatically scan after removal, then review disk/registry leftovers separately with explicit consent, registry exports and folder recycling. Add recent-removal history, bounded nested discovery and selected Windows executable-path traces adapted from BCU with Apache notices.
- Add Select all/Clear selection in leftover review and separate disk/registry result counts.
- Fix white installed-list backgrounds during scanning, unchecked checkbox-center hit testing and focused-search placeholder visibility.
- Include updated executable, screenshots, source checks, native compositor/fixture checks and license attribution.

## 2.8 - 2026-09-15

- Add staggered card entrances, click feedback, fluid setup/menu/progress transitions and reduced-motion support.

## 2.7 - 2026-09-15

- Add Affinity and direct selection saving/removal controls while preserving search and dependency consistency.

## 2.6 - 2026-09-15

- Introduce the WPF desktop interface, Windows accent integration, built-in profiles and portable profile save/load.
