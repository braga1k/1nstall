//! What every UI prototype shows, computed by the engine. The three prototypes differ only in
//! how they draw this; the catalog, the languages, the install plan and the clock are shared.

use std::collections::BTreeMap;

use oneinstall_core::packages::installed_state;
use oneinstall_core::queue::{plan, CatalogApp};
use oneinstall_platform::packages::Packages;
use oneinstall_platform::WindowsHost;
use serde_json::{json, Value};

// Embedded, as 3.6 embeds them, so each prototype's size includes its data.
const CATALOG: &str = include_str!("../../../../catalog.json");
const LOCALES: &str = include_str!("../../../../locales.json");

/// The interface texts of the install library screen, in the English form 3.6 uses as keys.
pub const LABELS: &[&str] = &[
    "Install",
    "Uninstall",
    "History & diagnostics",
    "Settings",
    "Buy me a beer",
    "LIBRARY",
    "All apps",
    "Installed",
    "Refresh",
    "Search apps · Ctrl+F",
    "All profiles",
    "Clear selection",
    "Selection",
    "Save selection...",
    "Details",
    "Open logs",
    "Activity & details",
    "Queue progress · apps processed",
    "Selection updated. Review before installing.",
    "Your next setup starts here. Select apps from the library.",
    "No apps found. Try another search or All apps.",
];

pub struct Card {
    pub key: String,
    pub name: String,
    pub category: String,
    pub method: String,
    pub automatic: bool,
    search: String,
}

pub struct Group {
    pub name: String,
    pub categories: Vec<String>,
}

pub struct PlanRow {
    pub key: String,
    pub name: String,
    pub method: String,
}

pub struct Library {
    pub lang: String,
    pub rtl: bool,
    pub strings: BTreeMap<String, String>,
    pub groups: Vec<Group>,
    pub cards: Vec<Card>,
    catalog: Vec<CatalogApp>,
}

fn text(row: &Value, name: &str) -> String {
    row[name].as_str().unwrap_or("").to_string()
}

fn list(row: &Value, name: &str) -> Vec<String> {
    row[name].as_array().map(|items| items.iter().filter_map(Value::as_str).map(str::to_string).collect()).unwrap_or_default()
}

/// Digits first, then letters, then the rest, as the 3.6 card list sorts.
fn sort_group(name: &str) -> u8 {
    match name.chars().next() {
        Some(first) if first.is_numeric() => 0,
        Some(first) if first.is_alphabetic() => 1,
        _ => 2,
    }
}

impl Library {
    pub fn load(lang: &str) -> Self {
        let locales: Value = serde_json::from_str(LOCALES.trim_start_matches('\u{feff}')).expect("locales.json");
        let (lang, locale) = match locales.get(lang) {
            Some(locale) => (lang, locale),
            None => ("en", &locales["en"]),
        };
        let strings: BTreeMap<String, String> =
            locale["Strings"].as_object().map(|map| map.iter().map(|(key, value)| (key.clone(), value.as_str().unwrap_or(key).to_string())).collect()).unwrap_or_default();
        let translate = |key: &str| strings.get(key).cloned().unwrap_or_else(|| key.to_string());

        let rows: Value = serde_json::from_str(CATALOG.trim_start_matches('\u{feff}')).expect("catalog.json");
        let rows = rows.as_array().expect("catalog array");
        let mut groups: Vec<Group> = Vec::new();
        let mut cards = Vec::with_capacity(rows.len());
        let mut catalog = Vec::with_capacity(rows.len());
        for row in rows {
            let ids = list(row, "Ids");
            let automatic = !ids.is_empty();
            let category = text(row, "Category");
            let group = text(row, "CategoryGroup");
            match groups.iter_mut().find(|known| known.name == group) {
                Some(known) if !known.categories.contains(&category) => known.categories.push(category.clone()),
                Some(_) => {}
                None => groups.push(Group { name: group, categories: vec![category.clone()] }),
            }
            let name = text(row, "Name");
            let search = format!("{name} {category} {} {}", list(row, "AlsoIn").join(" "), text(row, "Description")).to_lowercase();
            cards.push(Card {
                key: text(row, "Key"),
                name,
                category: translate(&category),
                method: translate(if automatic { "WinGet · automatic" } else { "Website · guided" }),
                automatic,
                search,
            });
            catalog.push(CatalogApp { key: text(row, "Key"), name: text(row, "Name"), ids, url: text(row, "Url"), requires: list(row, "Requires") });
        }
        cards.sort_by_cached_key(|card| (sort_group(&card.name), card.name.to_lowercase()));
        // The order of the 3.6 navigation.
        const ORDER: [&str; 4] = ["Everyday", "Create", "Files & Storage", "PC & Tools"];
        groups.sort_by_key(|group| ORDER.iter().position(|name| *name == group.name).unwrap_or(ORDER.len()));
        for group in &mut groups {
            group.categories.sort();
            group.name = translate(&group.name);
        }
        Self { lang: lang.to_string(), rtl: locale["Rtl"].as_bool().unwrap_or(false), strings, groups, cards, catalog }
    }

    pub fn tr(&self, key: &str) -> String {
        self.strings.get(key).cloned().unwrap_or_else(|| key.to_string())
    }

    /// Indexes of the cards matching every word of the query.
    pub fn filter(&self, query: &str) -> Vec<usize> {
        let query = query.to_lowercase();
        let words: Vec<&str> = query.split_whitespace().collect();
        (0..self.cards.len()).filter(|&index| words.iter().all(|word| self.cards[index].search.contains(word))).collect()
    }

    /// The install order for a selection, dependencies first, from the engine's planner.
    pub fn plan(&self, keys: &[String]) -> Result<Vec<PlanRow>, String> {
        let ordered = plan(&self.catalog, keys).map_err(|error| error.message)?;
        Ok(ordered
            .iter()
            .map(|app| PlanRow {
                key: app.key.clone(),
                name: app.name.clone(),
                method: self.tr(if app.ids.is_empty() { "Guided · official website" } else { "Automatic · WinGet" }),
            })
            .collect())
    }

    pub fn selected_label(&self, count: usize) -> String {
        if count == 1 {
            self.tr("1 app selected")
        } else {
            self.tr("{0} apps selected").replace("{0}", &count.to_string())
        }
    }

    pub fn library_label(&self) -> String {
        self.tr("{0} · {1} apps").replace("{0}", &self.tr("All apps")).replace("{1}", &self.cards.len().to_string())
    }

    /// Keys of the catalog apps WinGet confirms as installed. Slow: it runs `winget export`.
    pub fn installed_keys(&self) -> Vec<String> {
        let inventory = Packages::new(&WindowsHost::new()).inventory(false);
        self.catalog.iter().filter(|app| installed_state(&inventory, Some(&app.ids), "winget") == "Installed").map(|app| app.key.clone()).collect()
    }

    /// The whole screen as JSON, for the toolkits that are fed text (WebView and WPF).
    pub fn to_json(&self) -> Value {
        json!({
            "Lang": self.lang,
            "Rtl": self.rtl,
            "Strings": LABELS.iter().map(|label| (label.to_string(), Value::String(self.tr(label)))).collect::<serde_json::Map<_, _>>(),
            "LibraryLabel": self.library_label(),
            "Groups": self.groups.iter().map(|group| json!({"Name": group.name, "Categories": group.categories})).collect::<Vec<_>>(),
            "Cards": self.cards.iter().map(|card| json!({"Key": card.key, "Name": card.name, "Category": card.category, "Method": card.method, "Automatic": card.automatic})).collect::<Vec<_>>(),
        })
    }

    pub fn plan_json(&self, keys: &[String]) -> Value {
        match self.plan(keys) {
            Ok(rows) => json!({
                "Count": self.selected_label(keys.len()),
                "Rows": rows.iter().map(|row| json!({"Key": row.key, "Name": row.name, "Method": row.method})).collect::<Vec<_>>(),
                "Error": null
            }),
            Err(message) => json!({"Count": self.selected_label(keys.len()), "Rows": [], "Error": message}),
        }
    }
}

/// The raw catalog, for the 3.6 card builder, which reads it itself.
pub fn catalog_json() -> &'static str {
    CATALOG.trim_start_matches('\u{feff}')
}

pub struct Options {
    /// Draw the first screen, write the timings beside the program and exit: the 3.6 `--startup-test`.
    pub startup_test: bool,
    pub lang: String,
    /// App keys selected from the start (`--select a,b`), so pictures of the three prototypes match.
    pub select: Vec<String>,
}

impl Options {
    pub fn from_args() -> Self {
        let arguments: Vec<String> = std::env::args().skip(1).collect();
        let value = |name: &str| arguments.iter().position(|argument| argument == name).and_then(|index| arguments.get(index + 1)).cloned();
        Self {
            startup_test: arguments.iter().any(|argument| argument == "--startup-test"),
            lang: value("--lang").unwrap_or_else(|| "en".to_string()),
            select: value("--select").map(|keys| keys.split(',').filter(|key| !key.is_empty()).map(str::to_string).collect()).unwrap_or_default(),
        }
    }
}

#[repr(C)]
#[derive(Default)]
struct FileTime {
    low: u32,
    high: u32,
}

impl FileTime {
    fn ticks(&self) -> u64 {
        (u64::from(self.high) << 32) | u64::from(self.low)
    }
}

#[link(name = "kernel32")]
extern "system" {
    fn GetCurrentProcess() -> isize;
    fn GetProcessTimes(process: isize, creation: *mut FileTime, exit: *mut FileTime, kernel: *mut FileTime, user: *mut FileTime) -> i32;
    fn GetSystemTimeAsFileTime(now: *mut FileTime);
}

/// Milliseconds since Windows created this process. Stricter than the 3.6 clock, which starts
/// inside the launcher, after process creation and runtime start-up.
pub fn clock_ms() -> u64 {
    let (mut creation, mut exit, mut kernel, mut user, mut now) = (FileTime::default(), FileTime::default(), FileTime::default(), FileTime::default(), FileTime::default());
    // SAFETY: every pointer refers to a live, writable FILETIME of the layout Windows expects.
    unsafe {
        if GetProcessTimes(GetCurrentProcess(), &mut creation, &mut exit, &mut kernel, &mut user) == 0 {
            return 0;
        }
        GetSystemTimeAsFileTime(&mut now);
    }
    now.ticks().saturating_sub(creation.ticks()) / 10_000
}

/// Writes `startup-test.log` beside the program, in the format the 3.6 measuring script reads.
pub fn report(render_ms: u64, ready_ms: u64) {
    if let Some(folder) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(|parent| parent.to_path_buf())) {
        let _ = std::fs::write(folder.join("startup-test.log"), format!("READY {ready_ms}\nRenderMs {render_ms}\n"));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_library_loads_every_app_and_plans_dependencies_first() {
        let library = Library::load("pt-PT");
        assert_eq!(library.cards.len(), 325);
        assert_eq!(library.tr("Install"), "Instalar");
        assert_eq!(library.filter("7-zip").len(), 1);
        let rows = library.plan(&["peace".to_string()]).unwrap();
        assert_eq!(rows.iter().map(|row| row.key.as_str()).collect::<Vec<_>>(), ["apo", "peace"]);
        assert!(Library::load("ar").rtl);
        assert_eq!(Library::load("xx").lang, "en");
    }
}
