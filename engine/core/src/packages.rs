//! Package identity, the WinGet command line, exit-code mapping, export and setup parsing, redaction.

use std::collections::HashSet;

use serde_json::{Map, Value};

use crate::error::EngineError;
use crate::model::{PackageInventory, PackageRecord, SetupEntry, SetupSelection};
use crate::text::{eq_ignore_case, quote_windows_argument, utf16_len};

/// A WinGet package identifier or catalog key: ASCII letter or digit first, then letters,
/// digits, `.`, `+`, `_` or `-`; at most 200 characters.
///
/// Stricter than 3.6, which also accepted one trailing line break.
pub fn valid_id(id: &str) -> bool {
    if utf16_len(id) > 200 {
        return false;
    }
    let mut characters = id.chars();
    match characters.next() {
        Some(first) if first.is_ascii_alphanumeric() => {}
        _ => return false,
    }
    characters.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '+' | '_' | '-'))
}

pub fn valid_source(source: &str) -> bool {
    source == "winget" || source == "msstore"
}

/// False for missing, blank and placeholder versions (`unknown`, `latest`, `n/a`, `<...>`).
pub fn known_version(version: Option<&str>) -> bool {
    match version {
        Some(version) if !version.trim().is_empty() => !pattern!(r"(?i)^(unknown|latest|n/a|<.*>)\n?\z").is_match(version),
        _ => false,
    }
}

pub fn quote(value: &str) -> Result<String, EngineError> {
    if value.contains('\0') {
        return Err(EngineError::argument("Invalid argument."));
    }
    Ok(quote_windows_argument(value))
}

/// The one install command line the engine ever issues.
pub fn arguments(id: &str, source: &str) -> Result<String, EngineError> {
    if !valid_id(id) || !valid_source(source) {
        return Err(EngineError::argument("Invalid package identity."));
    }
    Ok(format!("install --id {} --exact --source {} --no-upgrade --accept-source-agreements --accept-package-agreements --disable-interactivity", quote(id)?, quote(source)?))
}

/// Classifies an installer or WinGet exit code. Exit success is `Unknown`: installed state
/// must be verified, never assumed.
pub fn outcome(code: i32) -> &'static str {
    let hresult = code as u32;
    if code == 3010 || code == 1641 || matches!(hresult, 0x8A15_0109..=0x8A15_010B) {
        return "Restart required";
    }
    if code == 1602 || code == 1223 || matches!(hresult, 0x8007_04C7 | 0x8A15_0005 | 0x8A15_010C | 0x8A15_0077) {
        return "Cancelled";
    }
    if code == 0 || matches!(hresult, 0x8A15_0061 | 0x8A15_010D) {
        return "Unknown";
    }
    if matches!(hresult, 0x8A15_0076 | 0x8A15_0041 | 0x8A15_0046) {
        return "Manual action required";
    }
    "Failed"
}

pub fn explain(code: i32) -> String {
    let hresult = code as u32;
    match hresult {
        0x8A15_0008 | 0x8A15_0107 => "Download/network failure. Check connectivity and retry after refreshing.".to_string(),
        0x8A15_0068 => "WinGet pin prevents this operation. Review the pin in WinGet; 1nstall will not override it.".to_string(),
        0x8A15_0104 | 0x8A15_0110 => "Dependency failed. Complete its installation before retrying.".to_string(),
        _ => format!("Process returned {code} / 0x{hresult:08X}. Review detailed logs and publisher instructions."),
    }
}

/// Member of a typed object: matched without regard to case, as the 3.6 serializer did.
fn member<'a>(object: &'a Map<String, Value>, name: &str) -> Option<&'a Value> {
    object.iter().filter(|(key, _)| eq_ignore_case(key, name)).map(|(_, value)| value).next_back()
}

fn text_member(value: Option<&Value>) -> Result<Option<String>, EngineError> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(text)) => Ok(Some(text.clone())),
        Some(Value::Number(number)) => Ok(Some(number.to_string())),
        Some(_) => Err(EngineError::json_syntax("A text value was expected.")),
    }
}

/// Reads `winget export` output into a partial inventory: listed packages are installed,
/// absent ones are unknown.
pub fn parse_export(json: &str) -> Result<PackageInventory, EngineError> {
    const UNEXPECTED: &str = "Unexpected WinGet export schema.";
    const INCOMPLETE: &str = "Incomplete WinGet export schema.";
    const IDENTITY: &str = "Invalid exported identity.";
    if json.is_empty() {
        return Err(EngineError::io(UNEXPECTED));
    }
    let root: Value = serde_json::from_str(json).map_err(EngineError::json_syntax)?;
    let root = match &root {
        Value::Null => return Err(EngineError::io(UNEXPECTED)),
        Value::Object(object) => object,
        _ => return Err(EngineError::json_syntax("The export is not a JSON object.")),
    };
    let sources = match member(root, "Sources") {
        None | Some(Value::Null) => return Err(EngineError::io(UNEXPECTED)),
        Some(Value::Array(items)) => items,
        Some(_) => return Err(EngineError::json_syntax("Sources is not a list.")),
    };
    let mut result = PackageInventory { partial: true, ..PackageInventory::default() };
    for source in sources {
        let Value::Object(source) = source else { return Err(EngineError::io(INCOMPLETE)) };
        let details = match member(source, "SourceDetails") {
            None | Some(Value::Null) => return Err(EngineError::io(INCOMPLETE)),
            Some(Value::Object(details)) => details,
            Some(_) => return Err(EngineError::json_syntax("SourceDetails is not an object.")),
        };
        // Dictionary keys, unlike typed members, are case-sensitive.
        let Some(name) = details.get("Name") else { return Err(EngineError::io(INCOMPLETE)) };
        let name = text_member(Some(name))?;
        let packages = match member(source, "Packages") {
            None | Some(Value::Null) => return Err(EngineError::io(INCOMPLETE)),
            Some(Value::Array(items)) => items,
            Some(_) => return Err(EngineError::json_syntax("Packages is not a list.")),
        };
        let name = match name {
            Some(name) if valid_source(&name) => name,
            _ => continue,
        };
        for package in packages {
            let Value::Object(package) = package else { return Err(EngineError::io(IDENTITY)) };
            let id = match text_member(member(package, "PackageIdentifier"))? {
                Some(id) if valid_id(&id) => id,
                _ => return Err(EngineError::io(IDENTITY)),
            };
            let version = text_member(member(package, "Version"))?;
            result.packages.push(PackageRecord { id: Some(id.clone()), name: Some(id), source: Some(name.clone()), installed_version: version });
        }
    }
    Ok(result)
}

/// Installed state of a catalog app from an inventory. Matching is by exact identifier
/// (ignoring case) and exact source; display names never count.
pub fn installed_state(inventory: &PackageInventory, ids: Option<&[String]>, source: &str) -> String {
    let ids = match ids {
        Some(ids) if !ids.is_empty() && (inventory.complete || inventory.partial) => ids,
        _ => return "Unknown".to_string(),
    };
    let mut absent = false;
    let mut versions: Vec<String> = Vec::new();
    for id in ids {
        let matches: Vec<&PackageRecord> = inventory
            .packages
            .iter()
            .filter(|package| package.id.as_deref().is_some_and(|candidate| eq_ignore_case(candidate, id)) && package.source.as_deref() == Some(source))
            .collect();
        if matches.len() > 1 {
            return "Unknown \u{b7} multiple registrations".to_string();
        }
        match matches.first() {
            None => absent = true,
            Some(package) => versions.push(match package.installed_version.as_deref() {
                Some(version) if known_version(Some(version)) => version.to_string(),
                _ => "version unknown".to_string(),
            }),
        }
    }
    if absent {
        return if inventory.complete && versions.is_empty() { "Not installed" } else { "Unknown \u{b7} omitted or partially installed" }.to_string();
    }
    format!("Installed \u{b7} {}", versions.join(" / "))
}

fn ordinal_key(text: &str) -> String {
    text.chars().flat_map(char::to_uppercase).collect()
}

/// Reads a saved selection. Unknown fields are refused, so a setup file can never carry
/// commands or executable content.
pub fn parse_setup(text: &str) -> Result<SetupSelection, EngineError> {
    const SCHEMA: &str = "Invalid setup schema.";
    const FIELDS: &str = "Invalid app fields. Executable content is not allowed.";
    const IDENTITY: &str = "Invalid or duplicate package identity.";
    if text.len() > 65536 {
        return Err(EngineError::io("Setup file exceeds 64 KiB."));
    }
    if text.is_empty() {
        return Err(EngineError::io(SCHEMA));
    }
    let root: Value = serde_json::from_str(text).map_err(EngineError::json_syntax)?;
    let Value::Object(root) = &root else { return Err(EngineError::io(SCHEMA)) };
    let version = match root.get("Version") {
        Some(Value::Number(number)) => match number.as_i64().filter(|_| !number.is_f64()).and_then(|value| i32::try_from(value).ok()) {
            Some(version) => version,
            None => return Err(EngineError::io(SCHEMA)),
        },
        _ => return Err(EngineError::io(SCHEMA)),
    };
    if !root.contains_key("Apps") {
        return Err(EngineError::io(SCHEMA));
    }
    if version != 1 && version != 2 {
        return Err(EngineError::io("Unsupported setup version."));
    }
    if root.keys().any(|key| key != "Version" && key != "Apps" && !(version == 2 && key == "Kind")) {
        return Err(EngineError::io("Unsupported setup fields. Commands and executable content are not allowed."));
    }
    if version == 2 && root.get("Kind").and_then(Value::as_str) != Some("1nstall-selection") {
        return Err(EngineError::io("Invalid setup kind."));
    }
    let items = match root.get("Apps") {
        Some(Value::Array(items)) if !items.is_empty() && items.len() <= 500 => items,
        _ => return Err(EngineError::io("Setup must contain 1\u{2013}500 app selections.")),
    };
    let mut result = SetupSelection { version, ..SetupSelection::default() };
    let mut seen: HashSet<String> = HashSet::new();
    for item in items {
        if version == 1 {
            match item.as_str() {
                Some(key) if valid_id(key) && seen.insert(ordinal_key(key)) => result.keys.push(key.to_string()),
                _ => return Err(EngineError::io("Invalid or duplicate catalog key.")),
            }
            continue;
        }
        let Value::Object(fields) = item else { return Err(EngineError::io(FIELDS)) };
        if fields.keys().any(|key| !matches!(key.as_str(), "Id" | "Source" | "Name" | "Version")) {
            return Err(EngineError::io(FIELDS));
        }
        let field = |name: &str| fields.get(name).and_then(Value::as_str).map(str::to_string);
        let (Some(id), Some(source), Some(name), Some(version)) = (field("Id"), field("Source"), field("Name"), field("Version")) else {
            return Err(EngineError::io(FIELDS));
        };
        let has_control = name.chars().chain(version.chars()).any(|c| (c as u32) <= 0x1f);
        if !valid_id(&id) || !valid_source(&source) || utf16_len(&name) > 200 || utf16_len(&version) > 100 || has_control || !seen.insert(ordinal_key(&format!("{source}:{id}"))) {
            return Err(EngineError::io(IDENTITY));
        }
        result.apps.push(SetupEntry { id, source, name, version });
    }
    Ok(result)
}

/// Removes paths, credentials, query strings and e-mail addresses from diagnostic text.
pub fn redact(text: Option<&str>) -> String {
    let text = text.unwrap_or("");
    let text = pattern!(r#"(?i)(?:[A-Z]:\\|\\\\)[^\r\n"<>]+"#).replace_all(text, "<path>");
    let text = pattern!(r#"(?:/Users/|/home/)[^\s"<>]+"#).replace_all(&text, "<path>");
    let text = pattern!(r"(?i)\b(token|password|passwd|secret|authorization|api[_-]?key|credential)\s*[:=]\s*[^\r\n,;]+").replace_all(&text, "${1}=<redacted>");
    let text = pattern!(r"(?i)\bBearer\s+\S+").replace_all(&text, "Bearer <redacted>");
    let text = pattern!(r"(?i)(https?://)[^\s/@]+:[^\s/@]+@").replace_all(&text, "${1}<credentials>@");
    let text = pattern!(r"(?i)(https?://[^\s?]+)\?[^\s]+").replace_all(&text, "${1}?<redacted>");
    let text = pattern!(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b").replace_all(&text, "<email>");
    text.into_owned()
}
