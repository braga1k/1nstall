# Settings — 1nstall 3.3

Settings was introduced in 3.3.0, building on the existing Install and Uninstall workflows.

Open **Settings** at the bottom of the navigation pane. Preferences are saved per Windows user in `%LOCALAPPDATA%\1nstall\settings.json`.

- **Theme:** System, Light or Dark, applied immediately. Both appearances retain gradient materials, reflective edges, ambient light and pointer reflections. Windows high contrast takes precedence.
- **Accent colour:** use the Windows accent, or switch it off for a completely monochrome interface in either theme. Black, white and grey retain the same gradients, depth and interactions. This changes only 1nstall.
- **Language:** System or English, Mandarin Chinese (Simplified), Hindi, Spanish, Modern Standard Arabic, French, Bengali, Portuguese (Portugal), Indonesian and Urdu. Portuguese has only `pt-PT`; Portuguese system variants resolve to it. Arabic and Urdu use right-to-left layout. Switching languages preserves selections. The initial list uses total speakers (first and additional languages), based on the [2026 ranking](https://en.wikipedia.org/wiki/List_of_languages_by_total_number_of_speakers). App names, publisher descriptions, original licence notices and raw diagnostic output retain their source language. Native-speaker review of the translations remains pending.
- **Automatic updates:** enabled by default, with a manual check and a restart action when an update is ready. This updates 1nstall itself. It does not update installed apps.

The compiled .NET executable checks the latest stable GitHub release in the background on launch. It downloads only a newer stable version, verifies its SHA-256 against the release digest or checksum file, and checks the executable's assembly identity and version. After the app closes, a separate worker waits for it to exit and atomically replaces the executable. The previous executable is retained as `1nstall.exe.previous`. Downloaded versions and update workers are under `%LOCALAPPDATA%\1nstall\Updates`. A failed swap preserves the original executable and records `update-error.log`; the next launch reports the problem. A writable executable folder is required. Script and legacy Zig builds expose the preferences but require manual application updates.

## Layout corrections

- Matching 18-DIP gaps between library cards and the two side panels; these are 18 physical pixels at 100% display scaling.
- Activity and Removal activity end at the same edge as their app cards.
- Uninstall cards share Install's pointer-following light, with the existing transparency and reduced-motion safeguards.
- Settings cards and buttons also follow the pointer, including the Settings navigation button. The light appearance uses layered pearl-grey materials instead of flat white fills. Hover effects and borders follow the current palette even after the pointer has moved.

## Local validation

- Catalog validation: 325 apps, 24 categories, 20 profiles and 911 benchmark rows.
- 54 headless regression checks, packaged self-test, smoke test and manager UI suite pass.
- Manager coverage includes margins at multiple widths, both activity edges, hover safeguards, all ten locale choices, right-to-left direction, preserved selection, keyboard focus, light-theme contrast and atomic preference persistence.
- Update tests reject a corrupt payload, preserve the original executable and retain a previous-version copy on success. The real official v3.2.0 asset was downloaded and verified; the packaged update worker replaced only disposable copies, including paths containing spaces. No installed application was changed.
- Three startup samples during Settings development, before the final appearance refinements: 2.578, 2.501 and 2.518 seconds (median 2.518 s). This is a local process-to-render measurement, not a cold-boot or universal performance guarantee.

The executable is unsigned. Physical DPI transitions, screen-reader sessions, other Windows versions and restart/elevation scenarios retain the validation limits documented in [VALIDATION.md](VALIDATION.md). No new external runtime dependency was added.
