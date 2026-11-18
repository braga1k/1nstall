//! Dependency ordering and the install queue. No I/O: installing and recording go through
//! the [`Installer`] trait.

use crate::error::EngineError;
use crate::text::eq_ignore_case;

/// The part of a catalog entry the queue needs.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CatalogApp {
    pub key: String,
    pub name: String,
    /// WinGet identifiers, installed in order. Empty for a guided app.
    pub ids: Vec<String>,
    /// Official download page of a guided app. Empty for an automatic app.
    pub url: String,
    /// Keys of apps that must be installed, and verified, first.
    pub requires: Vec<String>,
}

fn find<'a>(catalog: &'a [CatalogApp], key: &str) -> Option<&'a CatalogApp> {
    catalog.iter().find(|app| eq_ignore_case(&app.key, key))
}

fn visit<'a>(catalog: &'a [CatalogApp], key: &str, visiting: &mut Vec<String>, ordered: &mut Vec<&'a CatalogApp>) -> Result<(), EngineError> {
    let Some(app) = find(catalog, key) else { return Err(EngineError::invalid_operation(&format!("Unknown application: {key}"))) };
    if visiting.iter().any(|open| eq_ignore_case(open, key)) {
        return Err(EngineError::invalid_operation(&format!("Dependency cycle at: {key}")));
    }
    if ordered.iter().any(|done| eq_ignore_case(&done.key, key)) {
        return Ok(());
    }
    visiting.push(key.to_string());
    for dependency in &app.requires {
        visit(catalog, dependency, visiting, ordered)?;
    }
    visiting.pop();
    ordered.push(app);
    Ok(())
}

/// The apps to install for a selection: every selected app and everything it requires,
/// dependencies first, each once. Unknown keys and dependency cycles are refused.
pub fn plan<'a>(catalog: &'a [CatalogApp], keys: &[String]) -> Result<Vec<&'a CatalogApp>, EngineError> {
    let mut ordered = Vec::new();
    let mut visiting = Vec::new();
    for key in keys {
        visit(catalog, key, &mut visiting, &mut ordered)?;
    }
    Ok(ordered)
}

/// What one install attempt reported.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallReport {
    pub outcome: String,
    pub detail: String,
}

/// The side effects of the queue.
pub trait Installer {
    /// Installs one package of `app`. `verifying` is called when the installer has finished
    /// and the installed state is about to be checked. `Err` is an unexpected failure.
    fn install(&mut self, id: &str, app: &CatalogApp, verifying: &mut dyn FnMut()) -> Result<InstallReport, String>;
    /// Records an outcome the queue decided without running an installer.
    fn record(&mut self, id: &str, source: &str, name: &str, outcome: &str, message: &str);
}

/// What the queue reports while it runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QueueEvent {
    Status {
        key: String,
        text: String,
    },
    /// One app has been processed, whatever its outcome.
    Progress {
        key: String,
    },
    /// A guided app: the official page to open.
    Url {
        key: String,
        url: String,
    },
    Log {
        key: String,
        text: String,
    },
}

fn combine(states: &[String]) -> &'static str {
    let has = |state: &str| states.iter().any(|known| known.eq_ignore_ascii_case(state));
    if has("Failed") {
        "Failed"
    } else if has("Cancelled") {
        "Cancelled"
    } else if has("Restart required") {
        "Restart required"
    } else if has("Manual action required") {
        "Manual action required"
    } else if has("Unknown") {
        "Unknown \u{b7} refresh to verify"
    } else {
        "Success"
    }
}

/// Installs a plan in order.
///
/// `stop` is read before each app: the running installer is never interrupted, and apps not
/// yet started are recorded as cancelled. An app runs only if every app it requires ended
/// in `Success` during this same run. A guided app is never a success: opening a website
/// does not prove installation. Within an app, packages stop at the first one that is not
/// a success.
pub fn run_queue(plan: &[&CatalogApp], stop: &dyn Fn() -> bool, installer: &mut dyn Installer, emit: &mut dyn FnMut(QueueEvent)) {
    let mut outcomes: Vec<(String, String)> = Vec::new();
    for app in plan {
        let key = app.key.clone();
        if stop() {
            emit(QueueEvent::Status { key: key.clone(), text: "Cancelled \u{b7} not started".to_string() });
            emit(QueueEvent::Progress { key: key.clone() });
            installer.record(&key, "catalog", &app.name, "Cancelled", "Not started: stop after current requested.");
            continue;
        }
        let blocked: Vec<&str> =
            app.requires.iter().filter(|required| !outcomes.iter().any(|(done, state)| eq_ignore_case(done, required) && state == "Success")).map(String::as_str).collect();
        if !blocked.is_empty() {
            let list = blocked.join(", ");
            outcomes.push((key.clone(), "Manual action required".to_string()));
            emit(QueueEvent::Status { key: key.clone(), text: format!("Manual action required \u{b7} dependency not verified: {list}") });
            installer.record(&key, "catalog", &app.name, "Manual action required", &format!("Dependency not verified: {list}"));
            emit(QueueEvent::Progress { key });
            continue;
        }
        emit(QueueEvent::Status { key: key.clone(), text: "Preparing\u{2026}".to_string() });
        if !app.url.is_empty() {
            emit(QueueEvent::Url { key: key.clone(), url: app.url.clone() });
            emit(QueueEvent::Status { key: key.clone(), text: "Manual install pending \u{b7} official website".to_string() });
            outcomes.push((key.clone(), "Manual action required".to_string()));
            installer.record(
                &key,
                "guided",
                &app.name,
                "Manual action required",
                "Complete the official publisher installer, then refresh. Opening a website does not prove installation.",
            );
            emit(QueueEvent::Progress { key });
            continue;
        }
        let mut states: Vec<String> = Vec::new();
        for id in &app.ids {
            emit(QueueEvent::Status { key: key.clone(), text: format!("Installing {id}\u{2026}") });
            let report = installer.install(id, app, &mut || emit(QueueEvent::Status { key: key.clone(), text: "Verifying\u{2026}".to_string() }));
            match report {
                Ok(report) => {
                    let success = report.outcome == "Success";
                    states.push(report.outcome);
                    emit(QueueEvent::Log { key: key.clone(), text: report.detail });
                    if !success {
                        break;
                    }
                }
                Err(message) => {
                    states.push("Failed".to_string());
                    emit(QueueEvent::Log { key: key.clone(), text: message });
                }
            }
        }
        let state = combine(&states);
        outcomes.push((key.clone(), state.to_string()));
        emit(QueueEvent::Status { key: key.clone(), text: state.to_string() });
        emit(QueueEvent::Progress { key });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn app(key: &str, requires: &[&str]) -> CatalogApp {
        CatalogApp {
            key: key.to_string(),
            name: key.to_string(),
            ids: vec![format!("Fixture.{key}")],
            url: String::new(),
            requires: requires.iter().map(|r| r.to_string()).collect(),
        }
    }

    struct Fake {
        outcomes: Vec<(&'static str, &'static str)>,
        installed: Vec<String>,
        recorded: Vec<(String, String, String)>,
        stop_after: Option<usize>,
        stop: std::rc::Rc<std::cell::Cell<bool>>,
    }

    impl Installer for Fake {
        fn install(&mut self, id: &str, _app: &CatalogApp, verifying: &mut dyn FnMut()) -> Result<InstallReport, String> {
            self.installed.push(id.to_string());
            if self.stop_after == Some(self.installed.len()) {
                self.stop.set(true);
            }
            verifying();
            let outcome = self.outcomes.iter().find(|(known, _)| *known == id).map(|(_, outcome)| *outcome).unwrap_or("Success");
            Ok(InstallReport { outcome: outcome.to_string(), detail: format!("{id}: {outcome}") })
        }
        fn record(&mut self, id: &str, source: &str, _name: &str, outcome: &str, _message: &str) {
            self.recorded.push((id.to_string(), source.to_string(), outcome.to_string()));
        }
    }

    fn fake(outcomes: Vec<(&'static str, &'static str)>, stop_after: Option<usize>) -> Fake {
        Fake { outcomes, installed: Vec::new(), recorded: Vec::new(), stop_after, stop: Default::default() }
    }

    fn statuses(events: &[QueueEvent], key: &str) -> Vec<String> {
        events
            .iter()
            .filter_map(|event| match event {
                QueueEvent::Status { key: owner, text } if owner == key => Some(text.clone()),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn dependencies_come_first_and_once() {
        let catalog = [app("A", &["B"]), app("B", &["C"]), app("C", &[])];
        let ordered = plan(&catalog, &["A".to_string(), "C".to_string()]).unwrap();
        assert_eq!(ordered.iter().map(|app| app.key.as_str()).collect::<Vec<_>>(), ["C", "B", "A"]);
    }

    #[test]
    fn cycles_and_unknown_keys_are_refused() {
        let cyclic = [app("A", &["B"]), app("B", &["A"])];
        assert_eq!(plan(&cyclic, &["A".to_string()]).unwrap_err().message, "Dependency cycle at: A");
        let dangling = [app("A", &["Missing"])];
        assert_eq!(plan(&dangling, &["A".to_string()]).unwrap_err().message, "Unknown application: Missing");
    }

    #[test]
    fn keys_resolve_without_regard_to_case() {
        let catalog = [app("peace", &["apo"]), app("apo", &[])];
        let ordered = plan(&catalog, &["PEACE".to_string()]).unwrap();
        assert_eq!(ordered.iter().map(|app| app.key.as_str()).collect::<Vec<_>>(), ["apo", "peace"]);
    }

    #[test]
    fn a_dependent_does_not_run_after_its_dependency_fails() {
        let catalog = [app("A", &["B"]), app("B", &[])];
        let ordered = plan(&catalog, &["A".to_string()]).unwrap();
        let mut installer = fake(vec![("Fixture.B", "Failed")], None);
        let mut events = Vec::new();
        run_queue(&ordered, &|| false, &mut installer, &mut |event| events.push(event));
        assert_eq!(installer.installed, ["Fixture.B"]);
        assert_eq!(statuses(&events, "A"), ["Manual action required \u{b7} dependency not verified: B"]);
        assert_eq!(installer.recorded, [("A".to_string(), "catalog".to_string(), "Manual action required".to_string())]);
    }

    #[test]
    fn a_restart_required_dependency_also_blocks() {
        let catalog = [app("A", &["B"]), app("B", &[])];
        let ordered = plan(&catalog, &["A".to_string()]).unwrap();
        let mut installer = fake(vec![("Fixture.B", "Restart required")], None);
        run_queue(&ordered, &|| false, &mut installer, &mut |_| {});
        assert_eq!(installer.installed, ["Fixture.B"]);
    }

    #[test]
    fn stop_records_the_apps_not_started_and_never_interrupts_the_current_one() {
        let catalog = [app("A", &[]), app("B", &[]), app("C", &[])];
        let ordered = plan(&catalog, &["A".to_string(), "B".to_string(), "C".to_string()]).unwrap();
        let mut installer = fake(vec![], Some(1));
        let stop = installer.stop.clone();
        let mut events = Vec::new();
        run_queue(&ordered, &|| stop.get(), &mut installer, &mut |event| events.push(event));
        assert_eq!(installer.installed, ["Fixture.A"]);
        assert_eq!(statuses(&events, "A").last().map(String::as_str), Some("Success"));
        assert_eq!(statuses(&events, "B"), ["Cancelled \u{b7} not started"]);
        assert_eq!(installer.recorded.iter().map(|row| row.2.as_str()).collect::<Vec<_>>(), ["Cancelled", "Cancelled"]);
    }

    #[test]
    fn a_guided_app_is_never_a_success() {
        let guided = CatalogApp { key: "G".to_string(), name: "Guided".to_string(), ids: Vec::new(), url: "https://example.com/get".to_string(), requires: Vec::new() };
        let catalog = [guided, app("A", &["G"])];
        let ordered = plan(&catalog, &["A".to_string()]).unwrap();
        let mut installer = fake(vec![], None);
        let mut events = Vec::new();
        run_queue(&ordered, &|| false, &mut installer, &mut |event| events.push(event));
        assert!(installer.installed.is_empty());
        assert!(events.contains(&QueueEvent::Url { key: "G".to_string(), url: "https://example.com/get".to_string() }));
        assert_eq!(installer.recorded[0], ("G".to_string(), "guided".to_string(), "Manual action required".to_string()));
    }

    #[test]
    fn packages_of_one_app_stop_at_the_first_that_is_not_a_success() {
        let multi = CatalogApp {
            key: "M".to_string(),
            name: "Multi".to_string(),
            ids: vec!["One".to_string(), "Two".to_string(), "Three".to_string()],
            url: String::new(),
            requires: Vec::new(),
        };
        let catalog = [multi];
        let ordered = plan(&catalog, &["M".to_string()]).unwrap();
        let mut installer = fake(vec![("Two", "Unknown")], None);
        let mut events = Vec::new();
        run_queue(&ordered, &|| false, &mut installer, &mut |event| events.push(event));
        assert_eq!(installer.installed, ["One", "Two"]);
        assert_eq!(statuses(&events, "M").last().map(String::as_str), Some("Unknown \u{b7} refresh to verify"));
    }
}
