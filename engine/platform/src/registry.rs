//! Minimal registry access: open by hive and view, enumerate, read values as 3.6 read them.

use std::ptr::{null, null_mut};

#[link(name = "advapi32")]
extern "system" {
    fn RegOpenKeyExW(key: isize, sub_key: *const u16, options: u32, access: u32, result: *mut isize) -> i32;
    fn RegCreateKeyExW(
        key: isize,
        sub_key: *const u16,
        reserved: u32,
        class: *const u16,
        options: u32,
        access: u32,
        security: *const u8,
        result: *mut isize,
        disposition: *mut u32,
    ) -> i32;
    fn RegCloseKey(key: isize) -> i32;
    fn RegQueryInfoKeyW(
        key: isize,
        class: *mut u16,
        class_length: *mut u32,
        reserved: *mut u32,
        sub_keys: *mut u32,
        max_sub_key_length: *mut u32,
        max_class_length: *mut u32,
        values: *mut u32,
        max_value_name_length: *mut u32,
        max_value_length: *mut u32,
        security_descriptor: *mut u32,
        last_write: *mut u64,
    ) -> i32;
    fn RegEnumKeyExW(key: isize, index: u32, name: *mut u16, name_length: *mut u32, reserved: *mut u32, class: *mut u16, class_length: *mut u32, last_write: *mut u64) -> i32;
    fn RegEnumValueW(key: isize, index: u32, name: *mut u16, name_length: *mut u32, reserved: *mut u32, kind: *mut u32, data: *mut u8, data_length: *mut u32) -> i32;
    fn RegQueryValueExW(key: isize, name: *const u16, reserved: *mut u32, kind: *mut u32, data: *mut u8, data_length: *mut u32) -> i32;
    fn RegSetValueExW(key: isize, name: *const u16, reserved: u32, kind: u32, data: *const u8, data_length: u32) -> i32;
    fn RegDeleteTreeW(key: isize, sub_key: *const u16) -> i32;
    fn RegDeleteKeyExW(key: isize, sub_key: *const u16, access: u32, reserved: u32) -> i32;
    fn RegDeleteValueW(key: isize, name: *const u16) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn ExpandEnvironmentStringsW(source: *const u16, destination: *mut u16, size: u32) -> u32;
}

const KEY_READ: u32 = 0x0002_0019;
const KEY_WRITE: u32 = 0x0002_0006;
const KEY_WOW64_64KEY: u32 = 0x0100;
const KEY_WOW64_32KEY: u32 = 0x0200;
const ERROR_SUCCESS: i32 = 0;
const ERROR_FILE_NOT_FOUND: i32 = 2;
const ERROR_MORE_DATA: i32 = 234;
const REG_SZ: u32 = 1;
const REG_EXPAND_SZ: u32 = 2;
const REG_BINARY: u32 = 3;
const REG_DWORD: u32 = 4;
const REG_MULTI_SZ: u32 = 7;
const REG_QWORD: u32 = 11;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hive {
    CurrentUser,
    LocalMachine,
}

impl Hive {
    fn handle(self) -> isize {
        match self {
            Hive::CurrentUser => 0x8000_0001u32 as i32 as isize,
            Hive::LocalMachine => 0x8000_0002u32 as i32 as isize,
        }
    }
}

fn view_flag(view32: bool) -> u32 {
    if view32 {
        KEY_WOW64_32KEY
    } else {
        KEY_WOW64_64KEY
    }
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

fn text(units: &[u16]) -> String {
    let end = units.iter().position(|unit| *unit == 0).unwrap_or(units.len());
    String::from_utf16_lossy(&units[..end])
}

fn failure(operation: &str, status: i32) -> String {
    format!("{operation} failed with Windows error {status}.")
}

/// An open registry key, closed when dropped.
pub struct Key {
    handle: isize,
}

impl Drop for Key {
    fn drop(&mut self) {
        // SAFETY: the handle was opened by this type and is closed exactly once.
        unsafe { RegCloseKey(self.handle) };
    }
}

impl Key {
    /// Opens a key for reading. `Ok(None)` when it does not exist.
    pub fn open(hive: Hive, view32: bool, path: &str) -> Result<Option<Key>, String> {
        Self::open_from(hive.handle(), path, KEY_READ | view_flag(view32))
    }

    fn open_from(parent: isize, path: &str, access: u32) -> Result<Option<Key>, String> {
        let path = wide(path);
        let mut handle = 0isize;
        // SAFETY: the path is NUL-terminated and `handle` receives the opened key.
        match unsafe { RegOpenKeyExW(parent, path.as_ptr(), 0, access, &mut handle) } {
            ERROR_SUCCESS => Ok(Some(Key { handle })),
            ERROR_FILE_NOT_FOUND => Ok(None),
            status => Err(failure("Opening a registry key", status)),
        }
    }

    /// Opens a subkey for reading in the same view as this key.
    pub fn open_child(&self, name: &str) -> Result<Option<Key>, String> {
        Self::open_from(self.handle, name, KEY_READ)
    }

    fn info(&self) -> Result<(u32, u32, u32, u32), String> {
        let (mut sub_keys, mut max_sub_key, mut values, mut max_value_name, mut max_value) = (0u32, 0u32, 0u32, 0u32, 0u32);
        // SAFETY: every out pointer is either valid or null.
        let status = unsafe {
            RegQueryInfoKeyW(
                self.handle,
                null_mut(),
                null_mut(),
                null_mut(),
                &mut sub_keys,
                &mut max_sub_key,
                null_mut(),
                &mut values,
                &mut max_value_name,
                &mut max_value,
                null_mut(),
                null_mut(),
            )
        };
        if status != ERROR_SUCCESS {
            return Err(failure("Reading registry key information", status));
        }
        Ok((sub_keys, max_sub_key, values, max_value_name))
    }

    pub fn sub_key_names(&self) -> Result<Vec<String>, String> {
        let (count, max_length, _, _) = self.info()?;
        let mut names = Vec::with_capacity(count as usize);
        let mut buffer = vec![0u16; max_length as usize + 2];
        let mut index = 0u32;
        loop {
            let mut length = buffer.len() as u32;
            // SAFETY: the buffer and its length describe valid writable memory.
            match unsafe { RegEnumKeyExW(self.handle, index, buffer.as_mut_ptr(), &mut length, null_mut(), null_mut(), null_mut(), null_mut()) } {
                ERROR_SUCCESS => names.push(String::from_utf16_lossy(&buffer[..length as usize])),
                ERROR_MORE_DATA => {
                    buffer.resize(buffer.len() * 2, 0);
                    continue;
                }
                259 => break, // ERROR_NO_MORE_ITEMS
                status => return Err(failure("Listing registry keys", status)),
            }
            index += 1;
        }
        Ok(names)
    }

    pub fn value_names(&self) -> Result<Vec<String>, String> {
        let (_, _, count, max_length) = self.info()?;
        let mut names = Vec::with_capacity(count as usize);
        let mut buffer = vec![0u16; max_length as usize + 2];
        let mut index = 0u32;
        loop {
            let mut length = buffer.len() as u32;
            // SAFETY: the buffer and its length describe valid writable memory; data is not requested.
            match unsafe { RegEnumValueW(self.handle, index, buffer.as_mut_ptr(), &mut length, null_mut(), null_mut(), null_mut(), null_mut()) } {
                ERROR_SUCCESS => names.push(String::from_utf16_lossy(&buffer[..length as usize])),
                ERROR_MORE_DATA => {
                    buffer.resize(buffer.len() * 2, 0);
                    continue;
                }
                259 => break,
                status => return Err(failure("Listing registry values", status)),
            }
            index += 1;
        }
        Ok(names)
    }

    fn raw_value(&self, name: &str) -> Result<Option<(u32, Vec<u8>)>, String> {
        let name = wide(name);
        let mut kind = 0u32;
        let mut length = 0u32;
        // SAFETY: a null data pointer asks only for the type and size.
        match unsafe { RegQueryValueExW(self.handle, name.as_ptr(), null_mut(), &mut kind, null_mut(), &mut length) } {
            ERROR_SUCCESS => {}
            ERROR_FILE_NOT_FOUND => return Ok(None),
            status => return Err(failure("Reading a registry value", status)),
        }
        loop {
            let mut data = vec![0u8; length as usize + 2];
            let mut actual = data.len() as u32;
            // SAFETY: the data buffer and its length describe valid writable memory.
            match unsafe { RegQueryValueExW(self.handle, name.as_ptr(), null_mut(), &mut kind, data.as_mut_ptr(), &mut actual) } {
                ERROR_SUCCESS => {
                    data.truncate(actual as usize);
                    return Ok(Some((kind, data)));
                }
                ERROR_MORE_DATA => length = actual,
                ERROR_FILE_NOT_FOUND => return Ok(None),
                status => return Err(failure("Reading a registry value", status)),
            }
        }
    }

    pub fn has_value(&self, name: &str) -> Result<bool, String> {
        Ok(self.raw_value(name)?.is_some())
    }

    /// A value as text, the way 3.6 read it: strings as they are (with `%NAME%` expanded for
    /// expandable strings), numbers in decimal, and the given default when the value is missing.
    pub fn text(&self, name: &str, default: &str) -> Result<String, String> {
        let Some((kind, data)) = self.raw_value(name)? else { return Ok(default.to_string()) };
        let units = || -> Vec<u16> { data.chunks_exact(2).map(|pair| u16::from_le_bytes([pair[0], pair[1]])).collect() };
        Ok(match kind {
            REG_SZ => text(&units()),
            REG_EXPAND_SZ => expand(&text(&units())),
            REG_DWORD if data.len() >= 4 => i32::from_le_bytes([data[0], data[1], data[2], data[3]]).to_string(),
            REG_QWORD if data.len() >= 8 => i64::from_le_bytes([data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]]).to_string(),
            REG_MULTI_SZ => "System.String[]".to_string(),
            REG_BINARY => "System.Byte[]".to_string(),
            _ => String::new(),
        })
    }
}

fn expand(source: &str) -> String {
    let wide_source = wide(source);
    // SAFETY: a null destination with size 0 asks only for the required size.
    let needed = unsafe { ExpandEnvironmentStringsW(wide_source.as_ptr(), null_mut(), 0) };
    if needed == 0 {
        return source.to_string();
    }
    let mut destination = vec![0u16; needed as usize + 1];
    // SAFETY: the destination holds the reported size.
    let written = unsafe { ExpandEnvironmentStringsW(wide_source.as_ptr(), destination.as_mut_ptr(), destination.len() as u32) };
    if written == 0 || written as usize > destination.len() {
        return source.to_string();
    }
    text(&destination)
}

/// Does a key exist in the given hive and view?
pub fn key_exists(hive: Hive, view32: bool, path: &str) -> Result<bool, String> {
    Ok(Key::open(hive, view32, path)?.is_some())
}

/// Writes used only to build and remove fixtures in tests and disposable-machine scenarios.
pub mod fixtures {
    use super::*;

    fn create(hive: Hive, view32: bool, path: &str) -> Result<Key, String> {
        let path = wide(path);
        let mut handle = 0isize;
        // SAFETY: the path is NUL-terminated and `handle` receives the key.
        let status = unsafe { RegCreateKeyExW(hive.handle(), path.as_ptr(), 0, null(), 0, KEY_READ | KEY_WRITE | view_flag(view32), null(), &mut handle, null_mut()) };
        if status != ERROR_SUCCESS {
            return Err(failure("Creating a registry key", status));
        }
        Ok(Key { handle })
    }

    pub fn set_text(hive: Hive, view32: bool, path: &str, name: &str, value: &str) -> Result<(), String> {
        let key = create(hive, view32, path)?;
        let (name, data) = (wide(name), wide(value));
        // SAFETY: the data pointer and byte length describe the NUL-terminated string.
        let status = unsafe { RegSetValueExW(key.handle, name.as_ptr(), 0, REG_SZ, data.as_ptr() as *const u8, (data.len() * 2) as u32) };
        if status != ERROR_SUCCESS {
            return Err(failure("Writing a registry value", status));
        }
        Ok(())
    }

    pub fn set_number(hive: Hive, view32: bool, path: &str, name: &str, value: u32) -> Result<(), String> {
        let key = create(hive, view32, path)?;
        let name = wide(name);
        let data = value.to_le_bytes();
        // SAFETY: the data pointer and length describe four bytes.
        let status = unsafe { RegSetValueExW(key.handle, name.as_ptr(), 0, REG_DWORD, data.as_ptr(), 4) };
        if status != ERROR_SUCCESS {
            return Err(failure("Writing a registry value", status));
        }
        Ok(())
    }

    pub fn create_key(hive: Hive, view32: bool, path: &str) -> Result<(), String> {
        create(hive, view32, path).map(|_| ())
    }

    /// Deletes a key and everything below it. Missing keys are not an error.
    pub fn delete_tree(hive: Hive, view32: bool, path: &str) -> Result<(), String> {
        let Some((parent, leaf)) = path.rsplit_once('\\') else { return Err("A key path with a parent is required.".to_string()) };
        let Some(parent_key) = Key::open_from(hive.handle(), parent, KEY_READ | KEY_WRITE | view_flag(view32))? else { return Ok(()) };
        let leaf_wide = wide(leaf);
        // SAFETY: both pointers are NUL-terminated strings.
        let status = unsafe { RegDeleteTreeW(parent_key.handle, leaf_wide.as_ptr()) };
        if status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND {
            return Err(failure("Deleting a registry tree", status));
        }
        // SAFETY: as above. The key itself may already be gone.
        unsafe { RegDeleteKeyExW(parent_key.handle, leaf_wide.as_ptr(), view_flag(view32), 0) };
        Ok(())
    }

    pub fn delete_value(hive: Hive, view32: bool, path: &str, name: &str) -> Result<(), String> {
        let Some(key) = Key::open_from(hive.handle(), path, KEY_READ | KEY_WRITE | view_flag(view32))? else { return Ok(()) };
        let name = wide(name);
        // SAFETY: the name is NUL-terminated.
        let status = unsafe { RegDeleteValueW(key.handle, name.as_ptr()) };
        if status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND {
            return Err(failure("Deleting a registry value", status));
        }
        Ok(())
    }
}
