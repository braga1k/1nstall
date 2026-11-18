//! Prototype 1 of 3: the install library screen in Slint, over the Rust engine.
#![windows_subsystem = "windows"]

use std::cell::{Cell, RefCell};
use std::collections::HashSet;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

use prototype_model::{clock_ms, report, Library, Options};
use slint::winit_030::WinitWindowAccessor;
use slint::{ComponentHandle, Model, ModelRc, SharedString, VecModel};

slint::include_modules!();

const COLUMNS: usize = 3;

struct State {
    library: Arc<Library>,
    visible: Vec<usize>,
    selected: Vec<String>,
    installed: HashSet<String>,
    rows: Vec<Rc<VecModel<CardData>>>,
}

impl State {
    fn card(&self, index: usize) -> CardData {
        let card = &self.library.cards[index];
        CardData {
            key: card.key.as_str().into(),
            name: card.name.as_str().into(),
            category: card.category.as_str().into(),
            method: card.method.as_str().into(),
            checked: self.selected.contains(&card.key),
            installed: self.installed.contains(&card.key),
        }
    }

    /// Replaces the card rows: after a search, or when the installed apps arrive.
    fn rebuild(&mut self, ui: &AppWindow) {
        self.rows = self
            .visible
            .chunks(COLUMNS)
            .map(|chunk| {
                let mut cards: Vec<CardData> = chunk.iter().map(|&index| self.card(index)).collect();
                cards.resize(COLUMNS, CardData::default());
                Rc::new(VecModel::from(cards))
            })
            .collect();
        let rows: Vec<CardRow> = self.rows.iter().map(|row| CardRow { cards: ModelRc::from(row.clone()) }).collect();
        ui.set_rows(ModelRc::new(VecModel::from(rows)));
        ui.set_empty(self.visible.is_empty());
    }

    /// Redraws one card in place, so a toggle does not move the list.
    fn refresh_card(&self, key: &str) {
        if let Some(position) = self.visible.iter().position(|&index| self.library.cards[index].key == key) {
            self.rows[position / COLUMNS].set_row_data(position % COLUMNS, self.card(self.visible[position]));
        }
    }

    fn refresh_queue(&self, ui: &AppWindow) {
        ui.set_selected_label(self.library.selected_label(self.selected.len()).into());
        match self.library.plan(&self.selected) {
            Ok(rows) => {
                let items: Vec<QueueItem> =
                    rows.iter().map(|row| QueueItem { key: row.key.as_str().into(), name: row.name.as_str().into(), method: row.method.as_str().into() }).collect();
                ui.set_queue(ModelRc::new(VecModel::from(items)));
                let status = if self.selected.is_empty() { "Your next setup starts here. Select apps from the library." } else { "Selection updated. Review before installing." };
                ui.set_status(self.library.tr(status).into());
            }
            Err(message) => ui.set_status(message.into()),
        }
    }
}

fn main() -> Result<(), slint::PlatformError> {
    let options = Options::from_args();
    let arguments: Vec<String> = std::env::args().collect();
    if let Some(renderer) = arguments.iter().position(|argument| argument == "--renderer").and_then(|index| arguments.get(index + 1)) {
        slint::BackendSelector::new().renderer_name(renderer.clone()).select()?;
    }

    let library = Arc::new(Library::load(&options.lang));
    let ui = AppWindow::new()?;
    let tr = |key: &str| -> SharedString { library.tr(key).into() };
    ui.set_t(Strings {
        install: tr("Install"),
        uninstall: tr("Uninstall"),
        history: tr("History & diagnostics"),
        settings: tr("Settings"),
        beer: tr("Buy me a beer"),
        library: tr("LIBRARY"),
        all_apps: tr("All apps"),
        installed: tr("Installed"),
        refresh: tr("Refresh"),
        search: tr("Search apps · Ctrl+F"),
        all_profiles: tr("All profiles"),
        clear: tr("Clear selection"),
        selection: tr("Selection"),
        save: tr("Save selection..."),
        details: tr("Details"),
        review: tr("Review & install"),
        logs: tr("Open logs"),
        activity: tr("Activity & details"),
        progress: tr("Queue progress · apps processed"),
        hint: tr("Your next setup starts here. Select apps from the library."),
        empty: tr("No apps found. Try another search or All apps."),
    });
    ui.set_library_label(library.library_label().into());
    ui.set_groups(ModelRc::new(VecModel::from(library.groups.iter().map(|group| SharedString::from(group.name.as_str())).collect::<Vec<_>>())));

    let selected: Vec<String> = options.select.iter().filter(|key| library.cards.iter().any(|card| &card.key == *key)).cloned().collect();
    let state = Rc::new(RefCell::new(State { library: library.clone(), visible: library.filter(""), selected, installed: HashSet::new(), rows: Vec::new() }));
    state.borrow_mut().rebuild(&ui);
    state.borrow().refresh_queue(&ui);

    ui.on_toggle({
        let (state, weak) = (state.clone(), ui.as_weak());
        move |key| {
            let Some(ui) = weak.upgrade() else { return };
            let mut state = state.borrow_mut();
            match state.selected.iter().position(|selected| selected == key.as_str()) {
                Some(position) => drop(state.selected.remove(position)),
                None => state.selected.push(key.to_string()),
            }
            state.refresh_card(key.as_str());
            state.refresh_queue(&ui);
        }
    });
    ui.on_search_edited({
        let (state, weak) = (state.clone(), ui.as_weak());
        move |query| {
            let Some(ui) = weak.upgrade() else { return };
            let mut state = state.borrow_mut();
            state.visible = state.library.filter(query.as_str());
            state.rebuild(&ui);
        }
    });
    ui.on_clear_selection({
        let (state, weak) = (state.clone(), ui.as_weak());
        move || {
            let Some(ui) = weak.upgrade() else { return };
            let mut state = state.borrow_mut();
            state.selected.clear();
            state.rebuild(&ui);
            state.refresh_queue(&ui);
        }
    });
    ui.on_installed_loaded({
        let (state, weak) = (state.clone(), ui.as_weak());
        move |keys| {
            let Some(ui) = weak.upgrade() else { return };
            let mut state = state.borrow_mut();
            state.installed = keys.split('\n').filter(|key| !key.is_empty()).map(str::to_string).collect();
            state.rebuild(&ui);
        }
    });
    ui.on_drag_window({
        let weak = ui.as_weak();
        move || {
            if let Some(ui) = weak.upgrade() {
                ui.window().with_winit_window(|window| {
                    let _ = window.drag_window();
                });
            }
        }
    });
    ui.on_minimize({
        let weak = ui.as_weak();
        move || {
            if let Some(ui) = weak.upgrade() {
                ui.window().set_minimized(true);
            }
        }
    });
    ui.on_maximize({
        let weak = ui.as_weak();
        move || {
            if let Some(ui) = weak.upgrade() {
                let window = ui.window();
                window.set_maximized(!window.is_maximized());
            }
        }
    });
    ui.on_close(|| {
        let _ = slint::quit_event_loop();
    });

    if options.startup_test {
        // First frame drawn, then the event loop idle: the same two marks 3.6 reports.
        let rendered = Rc::new(Cell::new(None::<u64>));
        let marks = rendered.clone();
        let notifier = ui.window().set_rendering_notifier(move |state, _| {
            if matches!(state, slint::RenderingState::AfterRendering) && marks.get().is_none() {
                let render_ms = clock_ms();
                marks.set(Some(render_ms));
                slint::Timer::single_shot(Duration::ZERO, move || {
                    report(render_ms, clock_ms());
                    let _ = slint::quit_event_loop();
                });
            }
        });
        if notifier.is_err() {
            // The software renderer has no frame callback. Two idle turns of the event loop
            // after the window is shown is the nearest mark; it is reported as approximate.
            slint::Timer::single_shot(Duration::ZERO, move || {
                let render_ms = clock_ms();
                slint::Timer::single_shot(Duration::from_millis(1), move || {
                    report(render_ms, clock_ms());
                    let _ = slint::quit_event_loop();
                });
            });
        }
    } else {
        // The slow WinGet inventory runs off the UI thread and arrives later.
        let weak = ui.as_weak();
        std::thread::spawn(move || {
            let keys = library.installed_keys().join("\n");
            let _ = weak.upgrade_in_event_loop(move |ui| ui.invoke_installed_loaded(keys.into()));
        });
    }
    ui.run()
}
