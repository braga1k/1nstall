//! Text helpers that reproduce the string semantics 3.6 relied on.

/// Length as 3.6 counted it: UTF-16 code units.
pub fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

fn upper(character: char) -> char {
    let mut mapped = character.to_uppercase();
    match (mapped.next(), mapped.next()) {
        (Some(single), None) => single,
        _ => character,
    }
}

/// Ordinal comparison that ignores case, character by character.
pub fn eq_ignore_case(left: &str, right: &str) -> bool {
    let mut a = left.chars().map(upper);
    let mut b = right.chars().map(upper);
    loop {
        match (a.next(), b.next()) {
            (None, None) => return true,
            (Some(x), Some(y)) if x == y => {}
            _ => return false,
        }
    }
}

pub fn starts_with_ignore_case(text: &str, prefix: &str) -> bool {
    let mut a = text.chars().map(upper);
    for expected in prefix.chars().map(upper) {
        if a.next() != Some(expected) {
            return false;
        }
    }
    true
}

pub fn ends_with_ignore_case(text: &str, suffix: &str) -> bool {
    let mut a = text.chars().rev().map(upper);
    for expected in suffix.chars().rev().map(upper) {
        if a.next() != Some(expected) {
            return false;
        }
    }
    true
}

/// Windows command-line quoting: always quoted, backslashes doubled only before a quote
/// and at the end.
pub fn quote_windows_argument(value: &str) -> String {
    let mut result = String::with_capacity(value.len() + 2);
    result.push('"');
    let mut slashes = 0usize;
    for character in value.chars() {
        if character == '\\' {
            slashes += 1;
            continue;
        }
        let count = if character == '"' { slashes * 2 + 1 } else { slashes };
        result.extend(std::iter::repeat_n('\\', count));
        result.push(character);
        slashes = 0;
    }
    result.extend(std::iter::repeat_n('\\', slashes * 2));
    result.push('"');
    result
}

/// Last path component: everything after the last `\`, `/` or `:`.
pub fn file_name(path: &str) -> &str {
    match path.rfind(['\\', '/', ':']) {
        Some(index) => &path[index + 1..],
        None => path,
    }
}

/// File name without its last extension.
pub fn file_stem(path: &str) -> &str {
    let name = file_name(path);
    match name.rfind('.') {
        Some(index) => &name[..index],
        None => name,
    }
}

/// True when a path names a root or a drive: starts with a separator, or has `:` second.
pub fn is_rooted(path: &str) -> bool {
    let mut characters = path.chars();
    match characters.next() {
        Some('\\') | Some('/') => true,
        Some(_) => characters.next() == Some(':'),
        None => false,
    }
}

/// Characters 3.6's path handling refused anywhere in a path.
pub fn has_invalid_path_chars(path: &str) -> bool {
    path.chars().any(|c| c == '"' || c == '<' || c == '>' || c == '|' || (c as u32) < 32)
}
