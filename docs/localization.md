# Interface languages

1nstall offers 51 offline language choices: national official languages of European countries, Japanese and the original ten-language set. Portuguese is exclusively **pt-PT**. Serbian offers Cyrillic and Latin; Norwegian offers Bokmål and Nynorsk. Catalan is included as Andorra's official language. Coverage includes transcontinental countries: Russian, Turkish, Kazakh, Azerbaijani, Armenian and Georgian. Additional regional languages are outside the current scope.

Each choice contains 211 interface strings embedded in `locales.json`. Changing languages does not contact a translation service. The System choice tries the full locale, then its parent language; Portuguese variants resolve to pt-PT and Chinese variants to Simplified Chinese. Arabic and Urdu use right-to-left layout.

New translations are an automated first pass with terminology and placeholder corrections. Nynorsk and Rumantsch Grischun are drafts. Serbian Latin is transliterated from Cyrillic; Montenegrin uses shared Ijekavian terminology with adaptations. **Native-speaker review remains pending**, especially for less widely spoken languages. Inclusion in the selector does not imply certified linguistic review.

Brand names, original catalog descriptions, licences, installer output and raw logs retain their source language. Segoe UI is the common font, with Windows font fallback for other writing systems.

Run `python tests/locales.py` to check keys, placeholders and coverage. The WPF manager suite switches through every locale and checks profile controls at the minimum window width. Translation changes must preserve the distinction between installing, removing apps and separately consenting to leftover cleanup.

All screenshots published on GitHub must show the English interface, independently of personal Windows or app language preferences.
