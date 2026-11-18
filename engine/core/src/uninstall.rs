//! Uninstall-command parsing, product-name normalisation and the ownership rules that decide
//! which leftovers may be offered for cleanup.

use crate::error::EngineError;
use crate::host::{Host, SpecialFolder};
use crate::model::{Command, InstalledApp};
use crate::text::{ends_with_ignore_case, eq_ignore_case, file_name, file_stem, has_invalid_path_chars, is_rooted, quote_windows_argument, starts_with_ignore_case, utf16_len};

/// Registry keys whose values record executables that were run. Only single values in
/// these keys are ever candidates, never the keys themselves.
pub const TRACE_KEYS: [&str; 7] = [
    r"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
    r"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
    r"Software\Microsoft\Windows\CurrentVersion\Search\JumplistData",
    r"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
    r"Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppBadgeUpdated",
    r"Software\Microsoft\Windows\CurrentVersion\Explorer\FeatureUsage\AppSwitched",
    r"Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}\Count",
];

pub fn quote_argument(value: &str) -> String {
    quote_windows_argument(value)
}

/// Comparison form of a name: letters and digits only, lower-cased with the invariant table.
/// All ownership matching is equality of tokens, never substring search.
pub fn token(host: &dyn Host, name: Option<&str>) -> String {
    let stripped = pattern!(r"[^\p{L}\p{N}]").replace_all(name.unwrap_or(""), "");
    // 3.6 worked on UTF-16 units, where characters outside the BMP are never letters.
    let kept: String = stripped.chars().filter(|c| (*c as u32) <= 0xFFFF).collect();
    host.lower_invariant(&kept)
}

/// True when a name is specific enough to identify a product: at least three characters
/// and not a generic folder or installer word.
pub fn product(host: &dyn Host, name: Option<&str>) -> bool {
    let token = token(host, name);
    utf16_len(&token) >= 3
        && !pattern!(r"^(application|applications|app|apps|bin|current|x64|x86|software|microsoft|windows|programs|commonfiles|packages|data|cache|temp|1nstall|launcher|update|uninstall|installer|install|setup|client|public|user|users)$").is_match(&token)
}

/// Absolute form of a recorded location, or `None` if it is not a usable path.
pub fn full(host: &dyn Host, path: &str) -> Option<String> {
    let expanded = host.expand_environment(path.trim().trim_matches('"'));
    host.full_path(&expanded).map(|full| full.trim_end_matches('\\').to_string())
}

/// Names under which an app's leftovers may be recognised: its display name without
/// version and architecture, and the leaf of its install location when that leaf can be
/// tied to the product rather than to its vendor.
pub fn names(host: &dyn Host, app: &InstalledApp) -> Vec<String> {
    let display = app.name.as_deref().unwrap_or("");
    let display = pattern!(r"(?i)\s*\((?:(?:x64|x86|64[ -]?bit|32[ -]?bit|arm64)[\s,/-]*)+\)\s*\n?\z").replace_all(display, "");
    let display = pattern!(r"(?i)\s+(?:v?\d+(?:\.\d+)*.*|\(?(?:x64|x86|64-bit|32-bit)\)?)\n?\z").replace_all(&display, "");
    let name = display.trim().to_string();
    let mut names: Vec<String> = Vec::new();
    if product(host, Some(&name)) && !name.chars().any(|c| matches!(c, '\\' | '/' | ':' | '*' | '?' | '"' | '<' | '>' | '|')) {
        names.push(name.clone());
    }
    if let Some(location) = app.location.as_deref().filter(|location| !location.is_empty()) {
        if let Some(full) = full(host, location) {
            let leaf = file_name(&full).to_string();
            if product(host, Some(&leaf)) {
                let name_token = token(host, Some(&name));
                let leaf_token = token(host, Some(&leaf));
                // Never infer ownership of a vendor root from a partial product name.
                let tied = app.identity_verified || app.ownership_verified || (utf16_len(&leaf_token) >= 6 && name_token.contains(&leaf_token));
                if name_token == leaf_token || (tied && !token(host, app.publisher.as_deref()).contains(&leaf_token)) {
                    names.push(leaf);
                }
            }
        }
    }
    let mut distinct: Vec<String> = Vec::new();
    for name in names {
        if !distinct.iter().any(|kept| eq_ignore_case(kept, &name)) {
            distinct.push(name);
        }
    }
    distinct
}

/// Registry key names that are never entered and never accepted as a product key.
pub fn reserved_registry_name(name: &str) -> bool {
    pattern!(r"(?i)^(Microsoft|Windows|Classes|Policies|RegisteredApplications|Clients|Wow6432Node)\n?\z").is_match(name)
}

pub fn rot13(input: &str) -> String {
    input
        .chars()
        .map(|c| match c {
            'a'..='z' => (((c as u8 - b'a' + 13) % 26) + b'a') as char,
            'A'..='Z' => (((c as u8 - b'A' + 13) % 26) + b'A') as char,
            _ => c,
        })
        .collect()
}

/// True when `path` is `root` or lies below it. The separator is part of the test, so
/// `C:\Apps\AppSibling` is not inside `C:\Apps\App`.
pub fn inside(path: &str, root: &str) -> bool {
    eq_ignore_case(path, root) || starts_with_ignore_case(path, &format!("{root}\\"))
}

fn scaled(bytes: i64, unit: i64, decimals: u32, separator: &str) -> String {
    let scale = 10i128.pow(decimals);
    // Round half up; exact because the divisor is a power of two.
    let value = (bytes as i128 * scale * 2 + unit as i128) / (unit as i128 * 2);
    let mut fraction = format!("{:0width$}", value % scale, width = decimals as usize);
    while fraction.ends_with('0') {
        fraction.pop();
    }
    if fraction.is_empty() {
        (value / scale).to_string()
    } else {
        format!("{}{}{}", value / scale, separator, fraction)
    }
}

pub fn format_bytes(host: &dyn Host, bytes: i64) -> String {
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    let separator = host.decimal_separator();
    if bytes < 1_048_576 {
        format!("{} KB", scaled(bytes, 1024, 1, &separator))
    } else if bytes < 1_073_741_824 {
        format!("{} MB", scaled(bytes, 1_048_576, 1, &separator))
    } else {
        format!("{} GB", scaled(bytes, 1_073_741_824, 2, &separator))
    }
}

/// May a registry key under `Software` be offered as a leftover of `owner`?
///
/// The path must be `Software\` plus one to three plain components, its leaf must equal one
/// of the owner's names, no component may be reserved, and no installed app may share that
/// name or have it as publisher.
///
/// Stricter than 3.6, which also accepted a path ending in a line break.
pub fn safe_registry(host: &dyn Host, path: Option<&str>, owner: &InstalledApp, active: &[InstalledApp]) -> bool {
    let Some(path) = path else { return false };
    if path.chars().any(|c| (c as u32) > 0xFFFF) {
        return false;
    }
    if !pattern!(r"(?i)^Software\\[\p{L}\p{N} ._()+-]+(?:\\[\p{L}\p{N} ._()+-]+){0,2}$").is_match(path) {
        return false;
    }
    let pieces: Vec<&str> = path.split('\\').collect();
    let leaf_token = token(host, pieces.last().copied());
    if !names(host, owner).iter().any(|name| token(host, Some(name)) == leaf_token) {
        return false;
    }
    if pieces.iter().skip(1).any(|piece| reserved_registry_name(piece)) {
        return false;
    }
    !active.iter().any(|app| names(host, app).iter().any(|name| token(host, Some(name)) == leaf_token) || token(host, app.publisher.as_deref()) == leaf_token)
}

/// The executable path a trace value refers to: decoded, without display suffixes, with a leading known-folder GUID resolved.
pub fn trace_path(host: &dyn Host, key: &str, value: &str) -> String {
    let mut path = if key.to_lowercase().contains("\\userassist\\") { rot13(value) } else { value.to_string() };
    for suffix in [".FriendlyAppName", ".ApplicationCompany"] {
        if ends_with_ignore_case(&path, suffix) {
            let keep = path.chars().count() - suffix.chars().count();
            path = path.chars().take(keep).collect();
        }
    }
    if path.starts_with('{') {
        if let Some(end) = path.find('}') {
            if let Some(folder) = host.known_folder(&path[..=end]) {
                path = format!("{}{}", folder.trim_end_matches('\\'), &path[end + 1..]);
            }
        }
    }
    path
}

fn trace_is_safe(host: &dyn Host, key: &str, value: &str, owner: &InstalledApp, active: &[InstalledApp]) -> Option<bool> {
    let recorded = owner.location.as_deref().filter(|location| !location.trim().is_empty());
    let Some(recorded) = recorded else { return Some(false) };
    let location = full(host, recorded)?;
    let path = trace_path(host, key, value);
    if inside(&location, &full(host, &host.special_folder(SpecialFolder::Windows))?) {
        return Some(false);
    }
    for folder in [
        SpecialFolder::UserProfile,
        SpecialFolder::ProgramFiles,
        SpecialFolder::ProgramFilesX86,
        SpecialFolder::CommonApplicationData,
        SpecialFolder::LocalApplicationData,
        SpecialFolder::ApplicationData,
    ] {
        if eq_ignore_case(&location, &full(host, &host.special_folder(folder))?) {
            return Some(false);
        }
    }
    if has_invalid_path_chars(&path) {
        return None;
    }
    if !is_rooted(&path) || path.starts_with("\\\\") || !ends_with_ignore_case(&path, ".exe") {
        return Some(false);
    }
    let path = full(host, &path)?;
    let owner_names = names(host, owner);
    let leaf_token = token(host, Some(file_name(&location)));
    if !owner_names.iter().any(|name| token(host, Some(name)) == leaf_token) || !inside(&path, &location) || host.file_exists(&path) {
        return Some(false);
    }
    let owner_tokens: Vec<String> = owner_names.iter().map(|name| token(host, Some(name))).collect();
    if active.iter().any(|app| names(host, app).iter().any(|name| owner_tokens.contains(&token(host, Some(name))))) {
        return Some(false);
    }
    for app in active {
        if let Some(other) = app.location.as_deref().filter(|location| !location.trim().is_empty()) {
            let other = full(host, other)?;
            if inside(&location, &other) || inside(&other, &location) {
                return Some(false);
            }
        }
    }
    Some(true)
}

/// May one value of a trace key be offered as a leftover of `owner`?
///
/// The value must name an executable that no longer exists, inside the owner's recorded
/// location, and no installed app may share the owner's name or overlap its location.
/// Anything that cannot be evaluated counts as unsafe.
pub fn safe_registry_value(host: &dyn Host, key: &str, value: Option<&str>, owner: &InstalledApp, active: &[InstalledApp]) -> bool {
    let Some(value) = value else { return false };
    if !TRACE_KEYS.iter().any(|known| eq_ignore_case(known, key)) || value.is_empty() || value.chars().any(|c| matches!(c, '"' | '\r' | '\n' | '\0')) {
        return false;
    }
    trace_is_safe(host, key, value, owner, active).unwrap_or(false)
}

/// Canonical form of a GUID written as 32 digits, with dashes, or with braces or parentheses.
fn parse_guid(text: &str) -> Option<String> {
    let text = text.trim();
    let inner = match (text.chars().next(), text.chars().last()) {
        (Some('{'), Some('}')) | (Some('('), Some(')')) if text.len() >= 2 => &text[1..text.len() - 1],
        _ => text,
    };
    let digits: String = if inner.len() == 36 {
        let bytes = inner.as_bytes();
        if [8, 13, 18, 23].iter().any(|&index| bytes[index] != b'-') {
            return None;
        }
        inner.chars().filter(|c| *c != '-').collect()
    } else if inner.len() == 32 && inner.len() == text.len() {
        inner.to_string()
    } else {
        return None;
    };
    if digits.len() != 32 || !digits.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let digits = digits.to_ascii_lowercase();
    Some(format!("{}-{}-{}-{}-{}", &digits[..8], &digits[8..12], &digits[12..16], &digits[16..20], &digits[20..]))
}

/// End of the executable in an unquoted command: the shortest prefix that ends in `.exe`
/// and is followed by whitespace or the end of the text.
fn unquoted_executable_end(command: &str) -> Option<usize> {
    for (index, character) in command.char_indices() {
        if character == '\n' {
            return None;
        }
        let end = index + character.len_utf8();
        if end > 4 && command.is_char_boundary(end - 4) && command[end - 4..end].eq_ignore_ascii_case(".exe") {
            match command[end..].chars().next() {
                None => return Some(end),
                Some(next) if next.is_whitespace() => return Some(end),
                Some(_) => {}
            }
        }
    }
    None
}

/// The program and arguments to run for an app's removal, or the reason it is refused.
///
/// Windows Installer entries ignore their recorded command and use `msiexec /x {code}`.
/// Other entries must name an existing local `.exe`; shells and script hosts are refused.
pub fn get_command(host: &dyn Host, app: &InstalledApp) -> Result<Command, EngineError> {
    if app.msi {
        let code = app.registry_path.as_deref().map(file_name).and_then(parse_guid);
        let Some(code) = code else { return Err(EngineError::invalid_operation("Invalid Windows Installer product code.")) };
        return Ok(Command { file_name: format!("{}\\msiexec.exe", host.special_folder(SpecialFolder::System)), arguments: format!("/x {{{code}}}") });
    }
    let command = host.expand_environment(app.command.as_deref().unwrap_or("")).trim().to_string();
    let (executable, arguments) = if let Some(rest) = command.strip_prefix('"') {
        let Some(executable) = host.program_name(&command) else { return Err(EngineError::invalid_operation("Invalid uninstaller command.")) };
        let Some(end) = rest.find('"') else { return Err(EngineError::invalid_operation("Unclosed uninstaller path.")) };
        (executable, rest[end + 1..].trim().to_string())
    } else {
        // The whole executable path before the arguments, including legacy unquoted spaces.
        let Some(end) = unquoted_executable_end(&command) else { return Err(EngineError::invalid_operation("No executable uninstaller. Use Windows Settings.")) };
        (command[..end].to_string(), command[end..].trim().to_string())
    };
    if has_invalid_path_chars(&executable) {
        return Err(EngineError::argument("Illegal characters in path."));
    }
    if !is_rooted(&executable) || executable.starts_with("\\\\") || !host.file_exists(&executable) || !ends_with_ignore_case(&executable, ".exe") {
        return Err(EngineError::invalid_operation("Uninstaller is missing. Use Windows Settings."));
    }
    if pattern!(r"(?i)^(cmd|powershell|pwsh|wscript|cscript|rundll32|reg|mshta)\n?\z").is_match(file_stem(&executable)) {
        return Err(EngineError::invalid_operation("This uninstaller needs Windows Settings."));
    }
    Ok(Command { file_name: executable, arguments })
}

/// Drive or root part of an absolute path: `C:\` for `C:\Apps\App`.
fn path_root(path: &str) -> &str {
    let bytes = path.as_bytes();
    if bytes.len() >= 2 && bytes[1] == b':' {
        if bytes.len() >= 3 && (bytes[2] == b'\\' || bytes[2] == b'/') {
            return &path[..3];
        }
        return &path[..2];
    }
    if path.starts_with('\\') || path.starts_with('/') {
        return &path[..1];
    }
    ""
}

/// Parent directory of an absolute path, or `None` at a root.
pub fn parent_directory(path: &str) -> Option<&str> {
    let root = path_root(path);
    let trimmed = path.trim_end_matches('\\');
    if trimmed.len() <= root.trim_end_matches('\\').len() {
        return None;
    }
    let index = trimmed.rfind('\\')?;
    if index < root.len() {
        Some(root)
    } else {
        Some(&trimmed[..index])
    }
}

fn directory_is_safe(host: &dyn Host, path: &str, owner: &InstalledApp, active: &[InstalledApp]) -> Option<bool> {
    let path = full(host, path)?;
    if path.starts_with("\\\\") || utf16_len(&path) < 8 || !host.directory_exists(&path) {
        return Some(false);
    }
    let windows = full(host, &host.special_folder(SpecialFolder::Windows))?;
    if inside(&path, &windows) {
        return Some(false);
    }
    for folder in [SpecialFolder::MyDocuments, SpecialFolder::Desktop, SpecialFolder::MyPictures, SpecialFolder::MyMusic, SpecialFolder::MyVideos] {
        if inside(&path, &full(host, &host.special_folder(folder))?) {
            return Some(false);
        }
    }
    let home = full(host, &host.special_folder(SpecialFolder::UserProfile))?;
    if inside(&path, &format!("{home}\\Downloads")) || inside(&path, &format!("{home}\\OneDrive")) {
        return Some(false);
    }
    let program_files = host.special_folder(SpecialFolder::ProgramFiles);
    let program_files_x86 = host.special_folder(SpecialFolder::ProgramFilesX86);
    let roots = [
        path_root(&path).to_string(),
        home.clone(),
        program_files.clone(),
        program_files_x86.clone(),
        host.special_folder(SpecialFolder::CommonApplicationData),
        host.special_folder(SpecialFolder::LocalApplicationData),
        host.special_folder(SpecialFolder::ApplicationData),
    ];
    for root in roots.iter().filter(|root| !root.is_empty()) {
        if eq_ignore_case(&full(host, root)?, &path) {
            return Some(false);
        }
    }
    let users = format!("{}Users", path_root(&windows));
    if inside(&path, &users) && !inside(&path, &home) {
        return Some(false);
    }
    for sensitive in [
        format!("{program_files}\\Common Files"),
        format!("{program_files_x86}\\Common Files"),
        format!("{program_files}\\WindowsApps"),
        format!("{home}\\AppData\\Local\\Packages"),
    ] {
        if inside(&path, &full(host, &sensitive)?) {
            return Some(false);
        }
    }
    let product = token(host, Some(file_name(&path)));
    if !names(host, owner).iter().any(|name| token(host, Some(name)) == product) {
        return Some(false);
    }
    if active.iter().any(|app| names(host, app).iter().any(|name| token(host, Some(name)) == product) || token(host, app.publisher.as_deref()) == product) {
        return Some(false);
    }
    for other in active {
        if let Some(location) = other.location.as_deref().filter(|location| !location.trim().is_empty()) {
            let location = full(host, location)?;
            if inside(&path, &location) || inside(&location, &path) {
                return Some(false);
            }
        }
    }
    let mut current = Some(path.as_str());
    while let Some(directory) = current {
        if host.is_reparse_point(directory)? {
            return Some(false);
        }
        current = parent_directory(directory);
    }
    Some(true)
}

/// May a folder be offered as a leftover of `owner`?
///
/// It must exist, be local, lie outside Windows, personal folders, other profiles and
/// shared roots, be named exactly like the owner, not collide with any installed app by
/// name, publisher or location, and have no reparse point in its chain of parents.
/// Anything that cannot be evaluated counts as unsafe.
pub fn safe_directory(host: &dyn Host, path: &str, owner: &InstalledApp, active: &[InstalledApp]) -> bool {
    directory_is_safe(host, path, owner, active).unwrap_or(false)
}

/// The only roots in which leftovers are looked for. Never the whole disk.
pub fn data_roots(host: &dyn Host) -> Vec<String> {
    let candidates = [
        host.special_folder(SpecialFolder::ApplicationData),
        host.special_folder(SpecialFolder::LocalApplicationData),
        format!("{}\\AppData\\LocalLow", host.special_folder(SpecialFolder::UserProfile)),
        host.special_folder(SpecialFolder::CommonApplicationData),
        host.special_folder(SpecialFolder::ProgramFiles),
        host.special_folder(SpecialFolder::ProgramFilesX86),
    ];
    let mut roots: Vec<String> = Vec::new();
    for candidate in candidates {
        if !candidate.trim().is_empty() && !roots.iter().any(|kept| eq_ignore_case(kept, &candidate)) {
            roots.push(candidate);
        }
    }
    roots
}

/// Is a folder still within what discovery could have offered: the owner's verified
/// location, or at most three levels below a data root?
pub fn discovery_folder(host: &dyn Host, path: &str, owner: &InstalledApp) -> bool {
    let Some(path) = full(host, path) else { return false };
    if owner.ownership_verified {
        if let Some(location) = owner.location.as_deref().filter(|location| !location.trim().is_empty()) {
            if full(host, location).is_some_and(|location| eq_ignore_case(&path, &location)) {
                return true;
            }
        }
    }
    data_roots(host).iter().any(|root| match full(host, root) {
        Some(root) => inside(&path, &root) && path.chars().skip(root.chars().count()).collect::<String>().split('\\').filter(|part| !part.is_empty()).count() <= 3,
        None => false,
    })
}

/// A removal that asked for a restart blocks leftover work until Windows has restarted:
/// the boot time recorded with the request still matches the current one within two minutes.
pub fn waiting_for_restart(app: &InstalledApp, boot_time_ticks: i64) -> bool {
    const TICKS_PER_MINUTE: i64 = 600_000_000;
    app.restart_requested_at > 0 && (app.restart_requested_at - boot_time_ticks).abs() < TICKS_PER_MINUTE * 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_restart_gate_holds_only_for_the_boot_it_was_requested_in() {
        let boot = 638_000_000_000_000_000i64;
        let mut app = InstalledApp::default();
        assert!(!waiting_for_restart(&app, boot));
        app.restart_requested_at = boot;
        assert!(waiting_for_restart(&app, boot));
        assert!(waiting_for_restart(&app, boot + 1_199_999_999));
        assert!(!waiting_for_restart(&app, boot + 1_200_000_000));
        app.restart_requested_at = boot - 864_000_000_000;
        assert!(!waiting_for_restart(&app, boot));
    }

    #[test]
    fn parent_directories_stop_at_the_root() {
        assert_eq!(parent_directory(r"C:\Apps\App\bin"), Some(r"C:\Apps\App"));
        assert_eq!(parent_directory(r"C:\Apps"), Some(r"C:\"));
        assert_eq!(parent_directory(r"C:\"), None);
        assert_eq!(parent_directory("C:"), None);
    }
}
