//! Runs every case of `oracle/corpus/pure.json` through the Rust rules and compares the
//! result with what 3.6 produced (`oracle/golden/v3.6.0/pure.jsonl`).
//!
//! A case may differ from 3.6 only in one of three declared ways:
//! - `null input`: 3.6 was given a null that the Rust signature cannot express;
//! - `json syntax`: both reject text that is not JSON, with different wording;
//! - a divergence listed, with its reason, in `engine/oracle-divergences.json`.
#![cfg(windows)]

use std::path::PathBuf;

use oneinstall_core::{packages, uninstall, EngineError, ErrorKind, Host, InstalledApp, PackageInventory, PackageRecord, SpecialFolder};
use oneinstall_platform::WindowsHost;
use serde_json::{json, Value};

enum Outcome {
    Out(Value),
    Fail(EngineError),
    NullInput,
}

fn repository() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}

fn read(relative: &str) -> String {
    let path = repository().join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()))
}

/// Expands the corpus generators (`repeat`, `join`, `concat`) into the text they stand for.
fn expand(value: &Value) -> Value {
    let Some(kind) = value.get("$gen").and_then(Value::as_str) else { return value.clone() };
    let text = |name: &str| value.get(name).and_then(Value::as_str).unwrap_or("").to_string();
    let count = value.get("count").and_then(Value::as_u64).unwrap_or(0) as usize;
    Value::String(match kind {
        "repeat" => text("unit").repeat(count) + &text("suffix"),
        "join" => (0..count).map(|index| format!("{}{}{}", text("prefix"), index, text("suffix"))).collect::<Vec<_>>().join(&text("sep")),
        "concat" => value["parts"].as_array().expect("parts").iter().map(|part| expand(part).as_str().expect("text part").to_string()).collect(),
        other => panic!("unknown generator {other}"),
    })
}

fn optional(value: &Value) -> Option<&str> {
    value.as_str()
}

fn flag(spec: &Value, name: &str) -> bool {
    spec.get(name).and_then(Value::as_bool).unwrap_or(false)
}

fn field(spec: &Value, name: &str) -> Option<String> {
    spec.get(name).and_then(Value::as_str).map(str::to_string)
}

fn app(spec: &Value) -> InstalledApp {
    InstalledApp {
        id: field(spec, "Id"),
        name: field(spec, "Name"),
        publisher: field(spec, "Publisher"),
        version: field(spec, "Version"),
        kind: field(spec, "Kind"),
        location: field(spec, "Location"),
        command: field(spec, "Command"),
        registry_path: field(spec, "RegistryPath"),
        package_family: field(spec, "PackageFamily"),
        machine: flag(spec, "Machine"),
        view32: flag(spec, "View32"),
        msi: flag(spec, "Msi"),
        removal_verified: flag(spec, "RemovalVerified"),
        ownership_verified: flag(spec, "OwnershipVerified"),
        identity_verified: flag(spec, "IdentityVerified"),
        ..InstalledApp::default()
    }
}

fn apps(list: &Value) -> Vec<InstalledApp> {
    list.as_array().map(|items| items.iter().map(app).collect()).unwrap_or_default()
}

fn inventory(spec: &Value) -> PackageInventory {
    PackageInventory {
        complete: flag(spec, "Complete"),
        partial: flag(spec, "Partial"),
        message: None,
        packages: spec["Packages"]
            .as_array()
            .expect("Packages")
            .iter()
            .map(|package| PackageRecord {
                id: field(package, "Id"),
                name: field(package, "Name"),
                source: field(package, "Source"),
                installed_version: field(package, "InstalledVersion"),
            })
            .collect(),
    }
}

fn code(value: &Value) -> i32 {
    match value {
        Value::String(text) => u32::from_str_radix(text.trim_start_matches("0x"), 16).expect("hex code") as i32,
        other => other.as_i64().expect("integer code") as i32,
    }
}

/// Writes the System32 directory as `{SYSTEM32}`, as the golden file does.
fn portable(host: &WindowsHost, path: &str) -> String {
    let system = host.special_folder(SpecialFolder::System);
    match path.to_ascii_lowercase().find(&system.to_ascii_lowercase()) {
        Some(index) if !system.is_empty() => format!("{}{{SYSTEM32}}{}", &path[..index], &path[index + system.len()..]),
        _ => path.to_string(),
    }
}

fn result<T>(value: Result<T, EngineError>, show: impl FnOnce(T) -> Value) -> Outcome {
    match value {
        Ok(value) => Outcome::Out(show(value)),
        Err(error) => Outcome::Fail(error),
    }
}

fn evaluate(host: &WindowsHost, comma_host: &WindowsHost, function: &str, args: &[Value]) -> Outcome {
    macro_rules! text {
        ($index:expr) => {
            match optional(&args[$index]) {
                Some(text) => text,
                None => return Outcome::NullInput,
            }
        };
    }
    match function {
        "Packages.ValidId" => Outcome::Out(json!(packages::valid_id(text!(0)))),
        "Packages.ValidSource" => Outcome::Out(json!(packages::valid_source(text!(0)))),
        "Packages.KnownVersion" => Outcome::Out(json!(packages::known_version(optional(&args[0])))),
        "Packages.Quote" => result(packages::quote(text!(0)), |text| json!(text)),
        "Packages.Arguments" => result(packages::arguments(text!(0), text!(1)), |text| json!(text)),
        "Packages.Outcome" => Outcome::Out(json!(packages::outcome(code(&args[0])))),
        "Packages.Explain" => Outcome::Out(json!(packages::explain(code(&args[0])))),
        "Packages.ParseExport" => result(packages::parse_export(text!(0)), |inventory| {
            json!({
                "Complete": inventory.complete, "Partial": inventory.partial, "Message": inventory.message,
                "Packages": inventory.packages.iter().map(|p| json!({"Id": p.id, "Name": p.name, "Source": p.source, "InstalledVersion": p.installed_version})).collect::<Vec<_>>()
            })
        }),
        "Packages.InstalledState" => {
            let ids: Option<Vec<String>> = match &args[1] {
                Value::Null => None,
                Value::Array(items) => {
                    if items.iter().any(Value::is_null) {
                        return Outcome::NullInput;
                    }
                    Some(items.iter().map(|item| item.as_str().expect("id").to_string()).collect())
                }
                other => panic!("unexpected ids {other}"),
            };
            Outcome::Out(json!(packages::installed_state(&inventory(&args[0]), ids.as_deref(), text!(2))))
        }
        "Packages.ParseSetup" => result(packages::parse_setup(text!(0)), |setup| {
            json!({
                "Version": setup.version, "Keys": setup.keys,
                "Apps": setup.apps.iter().map(|a| json!({"Id": a.id, "Source": a.source, "Name": a.name, "Version": a.version})).collect::<Vec<_>>()
            })
        }),
        "Packages.Redact" => Outcome::Out(json!(packages::redact(optional(&args[0])))),
        "Uninstall.QuoteArgument" => Outcome::Out(json!(uninstall::quote_argument(text!(0)))),
        "Uninstall.Token" => Outcome::Out(json!(uninstall::token(host, optional(&args[0])))),
        "Uninstall.Product" => Outcome::Out(json!(uninstall::product(host, optional(&args[0])))),
        "Uninstall.Names" => Outcome::Out(json!(uninstall::names(host, &app(&args[0])))),
        "Uninstall.ReservedRegistryName" => Outcome::Out(json!(uninstall::reserved_registry_name(text!(0)))),
        "Uninstall.Rot13" => Outcome::Out(json!(uninstall::rot13(text!(0)))),
        "Uninstall.Inside" => Outcome::Out(json!(uninstall::inside(text!(0), text!(1)))),
        "Uninstall.FormatBytes" => Outcome::Out(json!(uninstall::format_bytes(host, args[0].as_i64().expect("bytes")))),
        "Uninstall.FormatBytes@pt-PT" => Outcome::Out(json!(uninstall::format_bytes(comma_host, args[0].as_i64().expect("bytes")))),
        "Uninstall.SafeRegistry" => Outcome::Out(json!(uninstall::safe_registry(host, optional(&args[0]), &app(&args[1]), &apps(&args[2])))),
        "Uninstall.SafeRegistryValue" => Outcome::Out(json!(uninstall::safe_registry_value(host, text!(0), optional(&args[1]), &app(&args[2]), &apps(&args[3])))),
        "Uninstall.GetCommand" => {
            result(uninstall::get_command(host, &app(&args[0])), |command| json!({"FileName": portable(host, &command.file_name), "Arguments": command.arguments}))
        }
        other => panic!("no Rust mapping for {other}"),
    }
}

fn exception_name(kind: ErrorKind) -> &'static str {
    match kind {
        ErrorKind::Argument => "ArgumentException",
        ErrorKind::Io => "IOException",
        ErrorKind::InvalidOperation => "InvalidOperationException",
        ErrorKind::JsonSyntax => "JsonSyntax",
    }
}

fn brief(value: &Value) -> String {
    let text = value.to_string();
    if text.chars().count() > 220 {
        format!("{}...", text.chars().take(220).collect::<String>())
    } else {
        text
    }
}

#[test]
fn rust_rules_match_the_recorded_behaviour_of_3_6() {
    let corpus: Value = serde_json::from_str(&read("oracle/corpus/pure.json")).expect("corpus");
    let golden_text = read("oracle/golden/v3.6.0/pure.jsonl");
    let golden: Vec<Value> = golden_text.lines().filter(|line| !line.is_empty()).map(|line| serde_json::from_str(line).expect("golden line")).collect();
    let listed: Value = serde_json::from_str(&read("engine/oracle-divergences.json")).expect("divergences");
    let listed = listed["divergences"].as_array().expect("divergences list");
    let mut used = vec![false; listed.len()];

    let host = WindowsHost::with_decimal_separator(".");
    let comma_host = WindowsHost::with_decimal_separator(",");
    let (mut exact, mut null_inputs, mut json_syntax, mut divergent) = (0usize, 0usize, 0usize, 0usize);
    let mut problems: Vec<String> = Vec::new();
    let mut line = 0usize;

    for function in corpus["functions"].as_array().expect("functions") {
        let name = function["fn"].as_str().expect("fn");
        let mut cases: Vec<Value> = function.get("cases").and_then(Value::as_array).cloned().unwrap_or_default();
        for range in function.get("ranges").and_then(Value::as_array).cloned().unwrap_or_default() {
            let bound = |index: usize| u32::from_str_radix(range[index].as_str().expect("bound").trim_start_matches("0x"), 16).expect("hex bound");
            cases.extend((bound(0)..=bound(1)).map(|value| json!([format!("0x{value:08X}")])));
        }
        for case in cases {
            let recorded = golden.get(line).unwrap_or_else(|| panic!("golden file has no line {}", line + 1));
            line += 1;
            assert_eq!(recorded["fn"], json!(name), "golden line {line} is for another function");
            assert_eq!(recorded["args"], case, "golden line {line} has other arguments");
            let expected = match (recorded.get("out"), recorded.get("err")) {
                (Some(out), _) => json!({ "out": out }),
                (None, Some(error)) => json!({ "err": error }),
                (None, None) => panic!("golden line {line} has no result"),
            };
            let inputs: Vec<Value> = case.as_array().expect("case").iter().map(expand).collect();
            let outcome = evaluate(&host, &comma_host, name, &inputs);
            let actual = match &outcome {
                Outcome::NullInput => {
                    null_inputs += 1;
                    continue;
                }
                Outcome::Out(value) => json!({ "out": value }),
                Outcome::Fail(error) => json!({ "err": { "type": exception_name(error.kind), "message": error.message } }),
            };
            if let Some(index) = listed.iter().position(|entry| entry["fn"] == json!(name) && entry["args"] == case) {
                used[index] = true;
                if actual != listed[index]["rust"] {
                    problems.push(format!("line {line} {name} {}: listed divergence expects {}, Rust gave {}", brief(&case), brief(&listed[index]["rust"]), brief(&actual)));
                } else if actual == expected {
                    problems.push(format!("line {line} {name} {}: listed as a divergence but equals 3.6", brief(&case)));
                } else {
                    divergent += 1;
                }
                continue;
            }
            if let Outcome::Fail(error) = &outcome {
                if error.kind == ErrorKind::JsonSyntax {
                    let recorded_type = expected["err"]["type"].as_str().unwrap_or("");
                    if matches!(recorded_type, "ArgumentException" | "InvalidOperationException") && matches!(name, "Packages.ParseExport" | "Packages.ParseSetup") {
                        json_syntax += 1;
                    } else {
                        problems.push(format!("line {line} {name} {}: Rust rejected as non-JSON, 3.6 gave {}", brief(&case), brief(&expected)));
                    }
                    continue;
                }
            }
            if actual == expected {
                exact += 1;
            } else {
                problems.push(format!("line {line} {name} {}\n      3.6:  {}\n      Rust: {}", brief(&case), brief(&expected), brief(&actual)));
            }
        }
    }
    assert_eq!(line, golden.len(), "corpus and golden file have different lengths");
    for (index, entry) in listed.iter().enumerate() {
        if !used[index] {
            problems.push(format!("listed divergence never met: {} {}", entry["fn"], brief(&entry["args"])));
        }
    }
    println!("oracle pure: {line} cases; identical {exact}; null input {null_inputs}; json syntax {json_syntax}; listed divergences {divergent}; unexplained {}", problems.len());
    if !problems.is_empty() {
        for problem in problems.iter().take(60) {
            println!("  {problem}");
        }
        panic!("{} cases differ from 3.6 without a declared reason", problems.len());
    }
}
