//! The settings file and what Windows says about appearance.

use std::path::{Path, PathBuf};

use oneinstall_core::host::{Host, SpecialFolder};
use oneinstall_core::settings::{Settings, MAX_FILE_BYTES};
use windows::UI::ViewManagement::{UIColorType, UISettings};

use crate::registry::{Hive, Key};

/// `%LOCALAPPDATA%\1nstall\settings.json`, where 3.6 keeps the same file.
pub fn settings_path(host: &dyn Host) -> PathBuf {
    Path::new(&host.special_folder(SpecialFolder::LocalApplicationData)).join("1nstall").join("settings.json")
}

/// Reads the saved preferences. A missing, oversized or unreadable file gives the defaults.
pub fn load(path: &Path, languages: &[&str]) -> Settings {
    match std::fs::metadata(path) {
        Ok(file) if file.len() <= MAX_FILE_BYTES => {}
        _ => return Settings::default(),
    }
    match std::fs::read(path) {
        Ok(bytes) => Settings::parse(&String::from_utf8_lossy(&bytes), languages),
        Err(_) => Settings::default(),
    }
}

/// Writes the preferences through a temporary file, so an interrupted save never leaves a
/// truncated one. The temporary file is removed whether or not the save succeeds.
pub fn save(path: &Path, settings: &Settings) -> Result<(), String> {
    let folder = path.parent().ok_or("The settings path has no folder.")?;
    std::fs::create_dir_all(folder).map_err(|error| error.to_string())?;
    let temporary = folder.join(format!("settings.json.{:032x}.tmp", unique()));
    let written = std::fs::write(&temporary, settings.to_json()).and_then(|()| std::fs::rename(&temporary, path));
    if written.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    written.map_err(|error| error.to_string())
}

fn unique() -> u128 {
    let time = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|elapsed| elapsed.as_nanos()).unwrap_or(0);
    time ^ (u128::from(std::process::id()) << 96)
}

/// What Windows reports for the things 3.6 follows live.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemAppearance {
    /// The Windows accent colour, when Windows can be asked.
    pub accent: Option<(u8, u8, u8)>,
    /// Whether transparency effects are on, when Windows can be asked.
    pub advanced_effects: Option<bool>,
    /// Whether apps use the light theme (`AppsUseLightTheme`). False when the value is missing.
    pub light: bool,
}

/// Asks Windows through the same `UISettings` object 3.6 uses, and the same registry value.
/// The calling thread must have COM initialised, as a WPF interface thread has.
pub fn system_appearance() -> SystemAppearance {
    let settings = UISettings::new().ok();
    let accent = settings.as_ref().and_then(|settings| settings.GetColorValue(UIColorType::Accent).ok()).map(|color| (color.R, color.G, color.B));
    let advanced_effects = settings.as_ref().and_then(|settings| settings.AdvancedEffectsEnabled().ok());
    let light = Key::open(Hive::CurrentUser, false, r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        .ok()
        .flatten()
        .and_then(|key| key.text("AppsUseLightTheme", "0").ok())
        .is_some_and(|value| value.trim() != "0");
    SystemAppearance { accent, advanced_effects, light }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LANGUAGES: [&str; 3] = ["en", "pt-PT", "ar"];

    fn scratch(name: &str) -> PathBuf {
        let folder = std::env::temp_dir().join(format!("1nstall-rust-settings-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&folder);
        folder
    }

    #[test]
    fn preferences_survive_a_save_and_leave_no_temporary_file() {
        let folder = scratch("save");
        let path = folder.join("nested").join("settings.json");
        assert_eq!(load(&path, &LANGUAGES), Settings::default());
        let chosen = Settings { theme: "Light".to_string(), windows_accent: false, language: "ar".to_string(), auto_update: false };
        save(&path, &chosen).unwrap();
        assert_eq!(load(&path, &LANGUAGES), chosen);
        // Saving over an existing file replaces it.
        save(&path, &Settings::default()).unwrap();
        assert_eq!(load(&path, &LANGUAGES), Settings::default());
        let files: Vec<String> = std::fs::read_dir(path.parent().unwrap()).unwrap().map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert_eq!(files, ["settings.json"]);
        let _ = std::fs::remove_dir_all(&folder);
    }

    #[test]
    fn an_oversized_or_damaged_file_gives_the_defaults() {
        let folder = scratch("damaged");
        std::fs::create_dir_all(&folder).unwrap();
        let path = folder.join("settings.json");
        std::fs::write(&path, format!("{{\"Theme\":\"Dark\",\"Pad\":\"{}\"}}", "x".repeat(9000))).unwrap();
        assert_eq!(load(&path, &LANGUAGES), Settings::default());
        std::fs::write(&path, "not json").unwrap();
        assert_eq!(load(&path, &LANGUAGES), Settings::default());
        std::fs::write(&path, "{\"Theme\":\"Dark\"}").unwrap();
        assert_eq!(load(&path, &LANGUAGES).theme, "Dark");
        let _ = std::fs::remove_dir_all(&folder);
    }

    #[test]
    fn windows_can_be_asked_about_appearance() {
        // Read-only. Whatever the machine's values are, the call must not fail.
        let appearance = system_appearance();
        assert!(appearance.accent.is_some() || appearance.advanced_effects.is_none());
    }
}
