//! Preferences and language choice, as `src/settings.ps1` of 3.6 reads and resolves them.
//! No I/O: the platform crate reads and writes the file.

use serde_json::Value;

/// The largest settings file 3.6 reads; a larger one is ignored.
pub const MAX_FILE_BYTES: u64 = 8192;

const THEMES: [&str; 3] = ["System", "Light", "Dark"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    /// `System`, `Light` or `Dark`.
    pub theme: String,
    pub windows_accent: bool,
    /// `System` or a language code of `locales.json`.
    pub language: String,
    pub auto_update: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self { theme: "System".to_string(), windows_accent: true, language: "System".to_string(), auto_update: true }
    }
}

fn canonical<'a>(known: &[&'a str], value: &str) -> Option<&'a str> {
    known.iter().copied().find(|name| name.eq_ignore_ascii_case(value))
}

impl Settings {
    /// What the test modes of 3.6 run with: English, dark, no update check, nothing read or saved.
    pub fn for_tests() -> Self {
        Self { theme: "Dark".to_string(), language: "en".to_string(), auto_update: false, ..Self::default() }
    }

    /// Reads saved preferences. Each property is taken only when it holds a valid value;
    /// anything else, including text that is not a JSON object, keeps the default.
    /// Names and values match without regard to case, as they do in PowerShell.
    pub fn parse(text: &str, languages: &[&str]) -> Self {
        let mut settings = Self::default();
        let Ok(Value::Object(saved)) = serde_json::from_str::<Value>(text.trim_start_matches('\u{feff}')) else {
            return settings;
        };
        for (name, value) in &saved {
            match (name.to_ascii_lowercase().as_str(), value) {
                ("theme", Value::String(theme)) => {
                    if let Some(theme) = canonical(&THEMES, theme) {
                        settings.theme = theme.to_string();
                    }
                }
                ("language", Value::String(language)) => {
                    if language.eq_ignore_ascii_case("System") {
                        settings.language = "System".to_string();
                    } else if let Some(language) = canonical(languages, language) {
                        settings.language = language.to_string();
                    }
                }
                ("windowsaccent", Value::Bool(enabled)) => settings.windows_accent = *enabled,
                ("autoupdate", Value::Bool(enabled)) => settings.auto_update = *enabled,
                _ => {}
            }
        }
        settings
    }

    /// The file content: the same four properties 3.6 writes, which 3.6 can read back.
    pub fn to_json(&self) -> String {
        let mut saved = serde_json::Map::new();
        saved.insert("Theme".to_string(), Value::String(self.theme.clone()));
        saved.insert("WindowsAccent".to_string(), Value::Bool(self.windows_accent));
        saved.insert("Language".to_string(), Value::String(self.language.clone()));
        saved.insert("AutoUpdate".to_string(), Value::Bool(self.auto_update));
        serde_json::to_string_pretty(&Value::Object(saved)).unwrap_or_default()
    }
}

/// The language the interface uses: the explicit choice, or the nearest match for the Windows
/// display language (`Resolve-AppLanguage`). `ui_culture` is a name such as `pt-BR`.
///
/// 3.6 returns the matched code in lower case and relies on PowerShell ignoring case from
/// there on; this returns the code as `locales.json` spells it, which names the same language.
pub fn resolve_language(choice: &str, ui_culture: &str, languages: &[&str]) -> String {
    if !choice.eq_ignore_ascii_case("System") {
        return choice.to_string();
    }
    let mut code = ui_culture.to_ascii_lowercase();
    if code.starts_with("pt") {
        return "pt-PT".to_string();
    }
    if code.starts_with("zh") {
        return "zh-Hans".to_string();
    }
    if code == "no" || code.starts_with("no-") {
        return "nb".to_string();
    }
    if code == "cnr" || code.starts_with("cnr-") {
        return "sr-Latn-ME".to_string();
    }
    while !code.is_empty() {
        if let Some(language) = canonical(languages, &code) {
            return language.to_string();
        }
        match code.rfind('-') {
            Some(dash) => code.truncate(dash),
            None => break,
        }
    }
    "en".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const LANGUAGES: [&str; 12] = ["en", "zh-Hans", "pt-PT", "nb", "nn", "sr", "sr-Latn", "sr-Latn-ME", "ru", "ja", "ar", "de"];

    #[test]
    fn the_system_language_resolves_as_in_3_6() {
        // The cases of tests/reliability.ps1.
        for (culture, expected) in
            [("pt-BR", "pt-PT"), ("ru-RU", "ru"), ("ja-JP", "ja"), ("nn-NO", "nn"), ("sr-Latn-RS", "sr-Latn"), ("sr-Latn-ME", "sr-Latn-ME"), ("zh-TW", "zh-Hans"), ("af-ZA", "en")]
        {
            assert_eq!(resolve_language("System", culture, &LANGUAGES), expected, "{culture}");
        }
        assert_eq!(resolve_language("ja", "pt-BR", &LANGUAGES), "ja");
        // The special cases, and an empty culture name.
        assert_eq!(resolve_language("System", "no", &LANGUAGES), "nb");
        assert_eq!(resolve_language("System", "no-NO", &LANGUAGES), "nb");
        assert_eq!(resolve_language("System", "cnr-Latn-ME", &LANGUAGES), "sr-Latn-ME");
        assert_eq!(resolve_language("System", "nor", &LANGUAGES), "en");
        assert_eq!(resolve_language("System", "", &LANGUAGES), "en");
        assert_eq!(resolve_language("system", "de-AT", &LANGUAGES), "de");
    }

    #[test]
    fn saved_preferences_are_taken_one_valid_property_at_a_time() {
        let saved = Settings::parse(r#"{"Theme":"Light","WindowsAccent":false,"Language":"pt-PT","AutoUpdate":false}"#, &LANGUAGES);
        assert_eq!(saved, Settings { theme: "Light".to_string(), windows_accent: false, language: "pt-PT".to_string(), auto_update: false });
        // Invalid values keep their defaults; valid ones beside them still apply.
        let partial = Settings::parse(r#"{"Theme":"Neon","WindowsAccent":"no","Language":"xx","AutoUpdate":false,"Extra":1}"#, &LANGUAGES);
        assert_eq!(partial, Settings { auto_update: false, ..Settings::default() });
        // Case is ignored, as PowerShell ignores it, and the stored spelling is the canonical one.
        let relaxed = Settings::parse(r#"{"theme":"dark","language":"SR-latn"}"#, &LANGUAGES);
        assert_eq!((relaxed.theme.as_str(), relaxed.language.as_str()), ("Dark", "sr-Latn"));
        for unreadable in ["", "malformed", "[1,2]", "null", "{\"Theme\":"] {
            assert_eq!(Settings::parse(unreadable, &LANGUAGES), Settings::default(), "{unreadable}");
        }
        assert_eq!(Settings::parse("\u{feff}{\"Theme\":\"Dark\"}", &LANGUAGES).theme, "Dark");
    }

    #[test]
    fn what_is_written_reads_back_unchanged() {
        let settings = Settings { theme: "Dark".to_string(), windows_accent: false, language: "ar".to_string(), auto_update: false };
        assert_eq!(Settings::parse(&settings.to_json(), &LANGUAGES), settings);
        assert!((settings.to_json().len() as u64) < MAX_FILE_BYTES);
        assert_eq!(Settings::for_tests(), Settings { theme: "Dark".to_string(), windows_accent: true, language: "en".to_string(), auto_update: false });
    }
}
