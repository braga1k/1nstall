//! Safety invariants of the rules, checked on generated inputs with an in-memory host.
//! Each property names the 3.6 invariant it protects (see docs: U-.., I-..).

use oneinstall_core::packages::{arguments, installed_state, outcome, parse_export, parse_setup, quote, valid_id, valid_source};
use oneinstall_core::queue::{plan, run_queue, CatalogApp, InstallReport, Installer, QueueEvent};
use oneinstall_core::uninstall::{format_bytes, get_command, inside, names, reserved_registry_name, safe_directory, safe_registry, safe_registry_value, token, TRACE_KEYS};
use oneinstall_core::{Host, InstalledApp, PackageInventory, PackageRecord, SpecialFolder};
use proptest::prelude::*;

/// A machine where every absolute path exists as both file and directory unless told otherwise.
struct FakeHost {
    files_exist: bool,
}

impl Host for FakeHost {
    fn lower_invariant(&self, text: &str) -> String {
        // One character to one character, like the invariant Windows table.
        let single = |c: char| {
            let mut lower = c.to_lowercase();
            match (lower.next(), lower.next()) {
                (Some(only), None) => only,
                _ => c,
            }
        };
        text.chars().map(single).collect()
    }
    fn expand_environment(&self, text: &str) -> String {
        text.to_string()
    }
    fn file_exists(&self, _path: &str) -> bool {
        self.files_exist
    }
    fn directory_exists(&self, _path: &str) -> bool {
        true
    }
    fn is_reparse_point(&self, _path: &str) -> Option<bool> {
        Some(false)
    }
    fn full_path(&self, path: &str) -> Option<String> {
        let absolute = path.len() >= 3 && path.as_bytes()[1] == b':' && path.as_bytes()[2] == b'\\';
        (absolute && !path.contains(['"', '<', '>', '|']) && !path.contains("..") && !path[2..].contains(':')).then(|| path.to_string())
    }
    fn program_name(&self, command_line: &str) -> Option<String> {
        command_line.strip_prefix('"').and_then(|rest| rest.split('"').next()).map(str::to_string)
    }
    fn special_folder(&self, folder: SpecialFolder) -> String {
        match folder {
            SpecialFolder::Windows => r"C:\Windows",
            SpecialFolder::System => r"C:\Windows\System32",
            SpecialFolder::UserProfile => r"C:\Users\me",
            SpecialFolder::ProgramFiles => r"C:\Program Files",
            SpecialFolder::ProgramFilesX86 => r"C:\Program Files (x86)",
            SpecialFolder::CommonApplicationData => r"C:\ProgramData",
            SpecialFolder::LocalApplicationData => r"C:\Users\me\AppData\Local",
            SpecialFolder::ApplicationData => r"C:\Users\me\AppData\Roaming",
            SpecialFolder::MyDocuments => r"C:\Users\me\Documents",
            SpecialFolder::Desktop => r"C:\Users\me\Desktop",
            SpecialFolder::MyPictures => r"C:\Users\me\Pictures",
            SpecialFolder::MyMusic => r"C:\Users\me\Music",
            SpecialFolder::MyVideos => r"C:\Users\me\Videos",
        }
        .to_string()
    }
    fn known_folder(&self, _guid: &str) -> Option<String> {
        None
    }
    fn decimal_separator(&self) -> String {
        ".".to_string()
    }
}

const HOST: FakeHost = FakeHost { files_exist: true };

fn owner(name: &str, location: Option<&str>) -> InstalledApp {
    InstalledApp {
        name: Some(name.to_string()),
        location: location.map(str::to_string),
        removal_verified: true,
        ownership_verified: location.is_some(),
        identity_verified: true,
        ..InstalledApp::default()
    }
}

/// Splits one quoted Windows argument back into its value, by the rules programs use.
fn unquote(argument: &str) -> String {
    let inner: Vec<char> = argument.chars().collect();
    let (mut out, mut index, mut slashes) = (String::new(), 1usize, 0usize);
    while index < inner.len() - 1 {
        match inner[index] {
            '\\' => slashes += 1,
            '"' => {
                out.extend(std::iter::repeat_n('\\', slashes / 2));
                slashes = 0;
                out.push('"');
            }
            other => {
                out.extend(std::iter::repeat_n('\\', slashes));
                slashes = 0;
                out.push(other);
            }
        }
        index += 1;
    }
    out.extend(std::iter::repeat_n('\\', slashes / 2));
    out
}

/// Text mixing ordinary characters with the ones that matter to the rules.
fn tricky() -> impl Strategy<Value = String> {
    proptest::collection::vec(
        prop_oneof![
            "[A-Za-z0-9]{1,6}",
            Just("\\".to_string()),
            Just("\"".to_string()),
            Just(" ".to_string()),
            Just("\n".to_string()),
            Just("\r".to_string()),
            Just(".".to_string()),
            Just("-".to_string()),
            Just("+".to_string()),
            Just("_".to_string()),
            Just(";".to_string()),
            Just("&".to_string()),
            Just("--all".to_string()),
            Just("$(".to_string()),
            Just("\u{130}".to_string()),
            Just("\u{1e9e}".to_string()),
            Just("\u{1f44d}".to_string()),
            Just("Microsoft".to_string()),
            Just("Software".to_string()),
            Just("..".to_string()),
            Just(":".to_string()),
            Just("|".to_string()),
        ],
        0..8,
    )
    .prop_map(|parts| parts.concat())
}

fn product_name() -> impl Strategy<Value = String> {
    "[A-Z][a-z]{3,8}( [A-Z][a-z]{3,8})?"
}

// What happened on a real PC with 3.6's rule (the names here are made up): a plug-in is
// installed into the folder every OpenFX plug-in shares, "Common Files\OFX\Plugins". 3.6 took "Plugins" for a name of
// the product, and offered the "Plugins" folders and registry keys of other programs as its
// leftovers.
#[test]
fn an_app_installed_into_a_shared_folder_does_not_claim_that_folder_name() {
    let mut app = owner("Grainfilm Pro OFX v7.1.3.0", Some(r"C:\Program Files\Common Files\OFX\Plugins\"));
    app.publisher = Some("Grainfilm Team".to_string());
    assert_eq!(names(&HOST, &app), ["Grainfilm Pro OFX"]);
    for folder in [
        r"C:\Program Files (x86)\Licence Manager\Plugins",
        r"C:\ProgramData\Other Vendor\Product List\plugins",
        r"C:\Users\me\AppData\Roaming\Suite Vendor\Sync\plugins",
        r"C:\Users\me\AppData\Roaming\downloader\plugins",
    ] {
        assert!(!safe_directory(&HOST, folder, &app, &[]), "{folder} is not a leftover of {:?}", app.name);
    }
    assert!(!safe_registry(&HOST, Some(r"Software\Music Vendor\Shared\Plugins"), &app, &[]));
    // Its own data, under its own name, is still found.
    assert!(safe_directory(&HOST, r"C:\Users\me\AppData\Roaming\Grainfilm Pro OFX", &app, &[]));
}

#[test]
fn a_shared_folder_word_is_never_a_product_name() {
    // Even when the product's own name ends in the word.
    let app = owner("Waves Plugins", Some(r"C:\Program Files\Waves\Plugins"));
    assert_eq!(names(&HOST, &app), ["Waves Plugins"]);
    for word in ["Plugins", "VST3", "Components", "Shared", "Common", "Tools", "Library", "Presets"] {
        let app = owner(word, Some(&format!(r"C:\Program Files\Vendor\{word}")));
        assert!(names(&HOST, &app).is_empty(), "{word} names no product");
    }
}

#[test]
fn a_folder_named_after_the_product_is_still_one_of_its_names() {
    // Cases of the kind the same real session got right, and must keep getting right.
    for (name, location, expected) in [
        ("Editor (User)", r"C:\Users\me\AppData\Local\Programs\editor\", vec!["Editor (User)", "editor"]),
        ("Acme Chameleon", r"C:\Program Files\Acme\Chameleon\", vec!["Acme Chameleon", "Chameleon"]),
        ("haze version 2.0", r"C:\Users\me\AppData\Local\Programs\haze\", vec!["haze version", "haze"]),
        ("Python 3.12.1 (64-bit)", r"C:\Program Files\Python312", vec!["Python", "Python312"]),
        ("VLC media player", r"C:\Program Files\VideoLAN\VLC", vec!["VLC media player", "VLC"]),
    ] {
        assert_eq!(names(&HOST, &owner(name, Some(location))), expected, "{name} at {location}");
    }
    // A folder name with nothing of the product's name is not taken for the product.
    assert_eq!(names(&HOST, &owner("Example Suite", Some(r"C:\Program Files\Exmpl"))), ["Example Suite"]);
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 2000, failure_persistence: None, ..ProptestConfig::default() })]

    // A second name always shares the product's own name, and is never a shared folder word:
    // an install folder alone gives no right to other folders of the same name.
    #[test]
    fn an_install_folder_names_the_product_only_when_it_shares_its_name(name in product_name(), leaf in "[A-Za-z0-9]{3,10}( [A-Za-z0-9]{2,8})?") {
        let app = owner(&name, Some(&format!(r"C:\Program Files\Vendor\{leaf}")));
        let simple = |text: &str| text.chars().filter(|c| c.is_alphanumeric()).collect::<String>().to_lowercase();
        for extra in names(&HOST, &app).iter().skip(1) {
            let (product, folder) = (simple(&name), simple(extra));
            prop_assert!(product.contains(&folder) || folder.contains(&product), "{extra:?} was taken for a name of {name:?}");
        }
    }

    // I-16: an identifier is only ever the plain character set, at most 200 long.
    #[test]
    fn a_valid_id_has_only_plain_characters(text in tricky()) {
        if valid_id(&text) {
            prop_assert!(text.len() <= 200 && !text.is_empty());
            prop_assert!(text.chars().all(|c| c.is_ascii_alphanumeric() || ".+_-".contains(c)));
            prop_assert!(text.chars().next().unwrap().is_ascii_alphanumeric());
        }
    }

    // I-14, I-15, I-20: the install command line never carries a line break or a widening flag.
    #[test]
    fn the_install_command_line_is_never_widened(id in tricky(), source in prop_oneof![Just("winget".to_string()), Just("msstore".to_string()), tricky()]) {
        match arguments(&id, &source) {
            Ok(line) => {
                prop_assert!(valid_id(&id) && valid_source(&source));
                prop_assert!(!line.contains(['\n', '\r', '\0']));
                prop_assert!(line.contains(" --exact ") && line.contains(" --no-upgrade "));
                // Identifiers are quoted and hold no spaces, so splitting on spaces gives the arguments.
                let words: Vec<&str> = line.split(' ').collect();
                prop_assert_eq!(words.len(), 10, "{}", line);
                for forbidden in ["--all", "--force", "--include-pinned", "--allow-reboot", "--silent", "--override", "--scope", "--version", "--interactive"] {
                    prop_assert!(!words.contains(&forbidden), "{line}");
                }
            }
            Err(_) => prop_assert!(!valid_id(&id) || !valid_source(&source)),
        }
    }

    // I-19: quoting is reversible, so no text can break out of its argument.
    #[test]
    fn a_quoted_argument_reads_back_unchanged(text in tricky()) {
        let quoted = quote(&text).unwrap();
        prop_assert!(quoted.starts_with('"') && quoted.ends_with('"'));
        prop_assert_eq!(unquote(&quoted), text);
    }

    // I-28: no exit code is ever classified as success; success needs verification.
    #[test]
    fn no_exit_code_means_success(code in any::<i32>()) {
        prop_assert!(["Restart required", "Cancelled", "Unknown", "Manual action required", "Failed"].contains(&outcome(code)));
    }

    // I-70..I-78: whatever is read from a setup file holds only valid identities.
    #[test]
    fn a_parsed_setup_holds_only_valid_identities(text in prop_oneof![tricky(), setup_like()]) {
        if let Ok(setup) = parse_setup(&text) {
            prop_assert!(setup.version == 1 || setup.version == 2);
            prop_assert!(setup.keys.len() + setup.apps.len() >= 1 && setup.keys.len() + setup.apps.len() <= 500);
            prop_assert!(setup.keys.iter().all(|key| valid_id(key)));
            prop_assert!(setup.apps.iter().all(|app| valid_id(&app.id) && valid_source(&app.source)));
        }
    }

    // I-52: an export only yields valid identities from the two known sources, and is never complete.
    #[test]
    fn a_parsed_export_is_partial_and_valid(id in tricky(), source in prop_oneof![Just("winget".to_string()), Just("msstore".to_string()), tricky()]) {
        let text = serde_json::json!({"Sources": [{"SourceDetails": {"Name": source}, "Packages": [{"PackageIdentifier": id, "Version": "1"}]}]}).to_string();
        if let Ok(inventory) = parse_export(&text) {
            prop_assert!(inventory.partial && !inventory.complete);
            for package in &inventory.packages {
                prop_assert!(valid_id(package.id.as_deref().unwrap()) && valid_source(package.source.as_deref().unwrap()));
            }
        }
    }

    // I-53..I-56: "Installed" needs exactly one exact record per id; "Not installed" needs a complete inventory.
    #[test]
    fn installed_state_never_overclaims(complete in any::<bool>(), partial in any::<bool>(), listed in proptest::collection::vec(("[A-C]\\.[A-C]", prop_oneof![Just("winget"), Just("msstore")]), 0..5), wanted in proptest::collection::vec("[A-C]\\.[A-C]", 0..3)) {
        let inventory = PackageInventory { complete, partial, message: None, packages: listed.iter().map(|(id, source)| PackageRecord { id: Some(id.clone()), name: Some(id.clone()), source: Some(source.to_string()), installed_version: Some("1".to_string()) }).collect() };
        let state = installed_state(&inventory, Some(&wanted), "winget");
        let matches = |id: &String| listed.iter().filter(|(known, source)| known.eq_ignore_ascii_case(id) && *source == "winget").count();
        if state.starts_with("Installed") {
            prop_assert!(!wanted.is_empty() && (complete || partial) && wanted.iter().all(|id| matches(id) == 1));
        }
        if state == "Not installed" {
            prop_assert!(complete && wanted.iter().all(|id| matches(id) == 0));
        }
    }

    // U-51: a token holds only letters and digits of the Basic Multilingual Plane.
    #[test]
    fn a_token_holds_only_letters_and_digits(text in tricky()) {
        let value = token(&HOST, Some(&text));
        prop_assert!(value.chars().all(|c| c.is_alphanumeric() && (c as u32) <= 0xFFFF), "{value:?}");
    }

    // U-65: the separator is part of containment, so a sibling folder is never inside.
    #[test]
    fn a_sibling_is_never_inside(root in "C:\\\\[A-Za-z]{1,8}(\\\\[A-Za-z]{1,8}){0,2}", suffix in "[A-Za-z0-9]{1,6}", child in "[A-Za-z0-9]{1,6}") {
        let sibling = format!("{root}{suffix}");
        let nested = format!("{root}\\{child}");
        prop_assert!(!inside(&sibling, &root));
        prop_assert!(inside(&nested, &root));
        prop_assert!(inside(&root, &root));
    }

    // U-68..U-72: a registry key is only offered under Software, at most three plain components deep,
    // never through a reserved name, named like its owner, and never when an installed app shares the name.
    #[test]
    fn a_registry_candidate_stays_in_bounds(prefix in prop_oneof![Just("Software".to_string()), Just("software".to_string()), tricky()], middle in proptest::collection::vec(prop_oneof!["[A-Za-z]{1,8}", Just("Microsoft".to_string()), Just("Classes".to_string()), Just("Wow6432Node".to_string()), tricky()], 0..4), name in product_name()) {
        let mut parts = vec![prefix];
        parts.extend(middle);
        parts.push(name.clone());
        let path = parts.join("\\");
        let app = owner(&name, None);
        if safe_registry(&HOST, Some(&path), &app, &[]) {
            let pieces: Vec<&str> = path.split('\\').collect();
            prop_assert!(pieces[0].eq_ignore_ascii_case("Software"));
            prop_assert!(pieces.len() >= 2 && pieces.len() <= 4);
            prop_assert!(pieces.iter().skip(1).all(|piece| !reserved_registry_name(piece)));
            prop_assert!(path.chars().all(|c| c.is_alphanumeric() || " ._()+-\\".contains(c)));
            prop_assert!(names(&HOST, &app).iter().any(|known| token(&HOST, Some(known)) == token(&HOST, pieces.last().copied())));
            // The same name on an installed app, or as its publisher, withdraws the candidate.
            prop_assert!(!safe_registry(&HOST, Some(&path), &app, &[owner(&name, None)]));
            let publisher = InstalledApp { name: Some("Unrelated Thing".to_string()), publisher: Some(name.clone()), ..InstalledApp::default() };
            prop_assert!(!safe_registry(&HOST, Some(&path), &app, &[publisher]));
        }
    }

    // U-73..U-77: a trace value is only offered in a known key, for an executable inside the owner's location.
    #[test]
    fn a_trace_candidate_points_inside_the_owner(key in prop_oneof![proptest::sample::select(TRACE_KEYS.to_vec()).prop_map(str::to_string), tricky()], name in product_name(), value in prop_oneof![tricky(), "(C:\\\\Apps\\\\)?[A-Za-z ]{1,12}(\\\\[a-z]{1,8})?\\.(exe|dll)"]) {
        let location = format!("C:\\Apps\\{name}");
        let app = owner(&name, Some(&location));
        let host = FakeHost { files_exist: false };
        if safe_registry_value(&host, &key, Some(&value), &app, &[]) {
            prop_assert!(TRACE_KEYS.iter().any(|known| known.eq_ignore_ascii_case(&key)));
            prop_assert!(!value.contains(['"', '\r', '\n', '\0']));
            prop_assert!(value.to_lowercase().ends_with(".exe"));
            prop_assert!(inside(&value, &location));
            // If the executable still exists, or an installed app overlaps the location, nothing is offered.
            prop_assert!(!safe_registry_value(&HOST, &key, Some(&value), &app, &[]));
            prop_assert!(!safe_registry_value(&host, &key, Some(&value), &app, &[owner("Other Thing", Some("C:\\Apps"))]));
        }
    }

    // U-55..U-63: a folder is never offered inside Windows, personal folders, other profiles or shared roots,
    // is always named like its owner, and never collides with an installed app.
    #[test]
    fn a_folder_candidate_is_never_a_protected_place(root in proptest::sample::select(vec![
        r"C:\Windows", r"C:\Windows\System32", r"C:\Users\me\Documents", r"C:\Users\me\Desktop", r"C:\Users\me\Pictures", r"C:\Users\me\Music", r"C:\Users\me\Videos",
        r"C:\Users\me\Downloads", r"C:\Users\me\OneDrive", r"C:\Users\other", r"C:\Users\Public", r"C:\Program Files\Common Files", r"C:\Program Files (x86)\Common Files",
        r"C:\Program Files\WindowsApps", r"C:\Users\me\AppData\Local\Packages", r"C:\Program Files", r"C:\ProgramData", r"C:\Users\me\AppData\Roaming", r"C:\Users\me\AppData\Local", r"C:\Users\me", r"C:", r"D:\Data",
    ]), middle in proptest::collection::vec("[A-Za-z]{1,8}", 0..3), name in product_name(), leaf_is_name in any::<bool>(), other in "[A-Z][a-z]{3,8}") {
        let leaf = if leaf_is_name { name.clone() } else { other };
        let mut parts = vec![root.to_string()];
        parts.extend(middle);
        parts.push(leaf);
        let path = parts.join("\\");
        let app = owner(&name, None);
        if safe_directory(&HOST, &path, &app, &[]) {
            for protected in [r"C:\Windows", r"C:\Users\me\Documents", r"C:\Users\me\Desktop", r"C:\Users\me\Pictures", r"C:\Users\me\Music", r"C:\Users\me\Videos", r"C:\Users\me\Downloads", r"C:\Users\me\OneDrive", r"C:\Program Files\Common Files", r"C:\Program Files (x86)\Common Files", r"C:\Program Files\WindowsApps", r"C:\Users\me\AppData\Local\Packages", r"C:\Users\other", r"C:\Users\Public"] {
                prop_assert!(!inside(&path, protected), "{path} is inside {protected}");
            }
            for exact in [r"C:\Program Files", r"C:\Program Files (x86)", r"C:\ProgramData", r"C:\Users\me\AppData\Roaming", r"C:\Users\me\AppData\Local", r"C:\Users\me"] {
                prop_assert!(!path.eq_ignore_ascii_case(exact));
            }
            let leaf = path.rsplit('\\').next();
            prop_assert!(names(&HOST, &app).iter().any(|known| token(&HOST, Some(known)) == token(&HOST, leaf)));
            prop_assert!(!safe_directory(&HOST, &path, &app, &[owner(&name, None)]));
            prop_assert!(!safe_directory(&HOST, &path, &app, &[owner("Other Thing", Some(&path))]));
            let plugin = [path.as_str(), "Plugin"].join("\\");
            prop_assert!(!safe_directory(&HOST, &path, &app, &[owner("Other Thing", Some(&plugin))]));
        }
    }

    // U-13..U-16: a removal command is always a local .exe that is not a shell or script host.
    #[test]
    fn a_removal_command_is_a_local_program_and_never_a_shell(quoted in any::<bool>(), folder in prop_oneof![Just(r"C:\Apps".to_string()), Just(r"\\server\share".to_string()), Just("relative".to_string()), Just(r"C:\Program Files\App".to_string())], program in prop_oneof!["[a-z]{1,8}", Just("cmd".to_string()), Just("PowerShell".to_string()), Just("pwsh".to_string()), Just("wscript".to_string()), Just("cscript".to_string()), Just("rundll32".to_string()), Just("reg".to_string()), Just("MSHTA".to_string())], extension in prop_oneof![Just(".exe"), Just(".EXE"), Just(".bat"), Just(".dll"), Just("")], tail in tricky()) {
        let executable = format!("{folder}\\{program}{extension}");
        let command = if quoted { format!("\"{executable}\" {tail}") } else { format!("{executable} {tail}") };
        let app = InstalledApp { command: Some(command), ..InstalledApp::default() };
        if let Ok(start) = get_command(&HOST, &app) {
            let file = start.file_name.to_lowercase();
            prop_assert!(file.ends_with(".exe"), "{file}");
            prop_assert!(!file.starts_with(r"\\") && file.as_bytes().get(1) == Some(&b':'), "{file}");
            let stem = file.rsplit('\\').next().unwrap().trim_end_matches(".exe").to_string();
            prop_assert!(!["cmd", "powershell", "pwsh", "wscript", "cscript", "rundll32", "reg", "mshta"].contains(&stem.as_str()), "{file}");
        }
    }

    // U-11, U-12: a Windows Installer entry always becomes exactly "msiexec /x {code}".
    #[test]
    fn an_msi_removal_is_always_msiexec_x(code in prop_oneof!["[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}".prop_map(|guid| format!("{{{guid}}}")), tricky()], command in tricky()) {
        let app = InstalledApp { msi: true, registry_path: Some(format!("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{code}")), command: Some(command), ..InstalledApp::default() };
        if let Ok(start) = get_command(&HOST, &app) {
            prop_assert_eq!(start.file_name, r"C:\Windows\System32\msiexec.exe");
            prop_assert!(start.arguments.starts_with("/x {") && start.arguments.ends_with('}') && start.arguments.len() == 41, "{}", start.arguments);
            prop_assert!(start.arguments[4..40].chars().all(|c| c.is_ascii_hexdigit() || c == '-'));
        }
    }

    // The size text always starts with the rounded value in the right unit.
    #[test]
    fn a_formatted_size_is_close_to_the_value(bytes in 0i64..=i64::MAX) {
        let text = format_bytes(&HOST, bytes);
        let (number, unit) = text.split_once(' ').unwrap();
        let divisor = match unit { "B" => 1.0, "KB" => 1024.0, "MB" => 1_048_576.0, "GB" => 1_073_741_824.0, other => return Err(TestCaseError::fail(format!("unit {other}"))) };
        let shown: f64 = number.parse().unwrap();
        let exact = bytes as f64 / divisor;
        prop_assert!((shown - exact).abs() <= 0.051 + exact * 1e-12, "{text} for {bytes}");
    }

    // I-03: a plan lists every dependency before its dependent, each app once.
    #[test]
    fn a_plan_is_dependency_ordered(edges in proptest::collection::vec((0usize..8, 0usize..8), 0..14), wanted in proptest::collection::vec(0usize..8, 1..5)) {
        // Edges only point to lower-numbered apps, so the graph has no cycle.
        let catalog: Vec<CatalogApp> = (0..8).map(|index| CatalogApp { key: format!("app{index}"), name: format!("App {index}"), ids: vec![format!("Id.{index}")], url: String::new(), requires: edges.iter().filter(|(from, to)| *from == index && to < from).map(|(_, to)| format!("app{to}")).collect() }).collect();
        let keys: Vec<String> = wanted.iter().map(|index| format!("app{index}")).collect();
        let ordered = plan(&catalog, &keys).unwrap();
        let position = |key: &str| ordered.iter().position(|app| app.key == key);
        for key in &keys { prop_assert!(position(key).is_some()); }
        for (index, app) in ordered.iter().enumerate() {
            prop_assert_eq!(ordered.iter().filter(|other| other.key == app.key).count(), 1);
            for required in &app.requires { prop_assert!(position(required).unwrap() < index); }
        }
    }

    // I-37: an app is only installed when everything it requires ended in Success in this run.
    #[test]
    fn nothing_runs_on_an_unverified_dependency(edges in proptest::collection::vec((0usize..6, 0usize..6), 0..10), results in proptest::collection::vec(proptest::sample::select(vec!["Success", "Success", "Success", "Failed", "Unknown", "Restart required", "Cancelled", "Manual action required"]), 6)) {
        let catalog: Vec<CatalogApp> = (0..6).map(|index| CatalogApp { key: format!("app{index}"), name: format!("App {index}"), ids: vec![format!("Id.{index}")], url: String::new(), requires: edges.iter().filter(|(from, to)| *from == index && to < from).map(|(_, to)| format!("app{to}")).collect() }).collect();
        let keys: Vec<String> = (0..6).map(|index| format!("app{index}")).collect();
        let ordered = plan(&catalog, &keys).unwrap();
        struct Scripted<'a> { results: &'a [&'static str], ran: Vec<String> }
        impl Installer for Scripted<'_> {
            fn install(&mut self, id: &str, _app: &CatalogApp, _verifying: &mut dyn FnMut()) -> Result<InstallReport, String> {
                self.ran.push(id.to_string());
                let index: usize = id.trim_start_matches("Id.").parse().unwrap();
                Ok(InstallReport { outcome: self.results[index].to_string(), detail: String::new() })
            }
            fn record(&mut self, _id: &str, _source: &str, _name: &str, _outcome: &str, _message: &str) {}
        }
        let mut installer = Scripted { results: &results, ran: Vec::new() };
        let mut events: Vec<QueueEvent> = Vec::new();
        run_queue(&ordered, &|| false, &mut installer, &mut |event| events.push(event));
        for app in &catalog {
            let index: usize = app.key.trim_start_matches("app").parse().unwrap();
            if installer.ran.contains(&format!("Id.{index}")) {
                for required in &app.requires {
                    let dependency: usize = required.trim_start_matches("app").parse().unwrap();
                    prop_assert!(installer.ran.contains(&format!("Id.{dependency}")) && results[dependency] == "Success", "{} ran although {required} was {}", app.key, results[dependency]);
                }
            }
        }
    }
}

/// Text shaped like a setup file, with identifiers that are sometimes invalid.
fn setup_like() -> impl Strategy<Value = String> {
    (
        prop_oneof![Just(1), Just(2), Just(3)],
        proptest::collection::vec(prop_oneof!["[A-Za-z][A-Za-z0-9.]{0,10}", tricky()], 0..4),
        prop_oneof![Just("winget".to_string()), tricky()],
    )
        .prop_map(|(version, ids, source)| {
            if version == 1 {
                serde_json::json!({"Version": 1, "Apps": ids}).to_string()
            } else {
                let apps: Vec<serde_json::Value> = ids.iter().map(|id| serde_json::json!({"Id": id, "Source": source, "Name": "n", "Version": "1"})).collect();
                serde_json::json!({"Version": version, "Kind": "1nstall-selection", "Apps": apps}).to_string()
            }
        })
}
