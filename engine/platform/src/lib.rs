//! Windows implementation of what the engine rules ask of the machine.
#![cfg(windows)]

pub mod inventory;
pub mod json;
pub mod process;
pub mod recycle;
pub mod registry;
pub mod removal;

use std::ffi::c_void;
use std::ptr::{null, null_mut};

use oneinstall_core::text::has_invalid_path_chars;
use oneinstall_core::{Host, SpecialFolder};

#[repr(C)]
struct Guid {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [u8; 8],
}

#[link(name = "kernel32")]
extern "system" {
    fn LCMapStringEx(
        locale: *const u16,
        flags: u32,
        source: *const u16,
        source_length: i32,
        destination: *mut u16,
        destination_length: i32,
        version: *const c_void,
        reserved: *const c_void,
        sort_handle: isize,
    ) -> i32;
    fn ExpandEnvironmentStringsW(source: *const u16, destination: *mut u16, size: u32) -> u32;
    fn GetFileAttributesW(path: *const u16) -> u32;
    fn GetFullPathNameW(path: *const u16, size: u32, buffer: *mut u16, file_part: *mut *mut u16) -> u32;
    fn GetLocaleInfoEx(locale: *const u16, kind: u32, data: *mut u16, size: i32) -> i32;
    fn LocalFree(memory: *mut c_void) -> *mut c_void;
}

#[link(name = "shell32")]
extern "system" {
    fn CommandLineToArgvW(command_line: *const u16, count: *mut i32) -> *mut *mut u16;
    fn SHGetFolderPathW(window: *mut c_void, folder: i32, token: *mut c_void, flags: u32, path: *mut u16) -> i32;
    fn SHGetKnownFolderPath(id: *const Guid, flags: u32, token: *mut c_void, path: *mut *mut u16) -> i32;
}

#[link(name = "ole32")]
extern "system" {
    fn CoTaskMemFree(memory: *mut c_void);
}

const LCMAP_LOWERCASE: u32 = 0x0000_0100;
const LOCALE_SDECIMAL: u32 = 0x0000_000E;
const INVALID_FILE_ATTRIBUTES: u32 = 0xFFFF_FFFF;
const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x0000_0010;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0000_0400;
/// Longest path the 3.6 runtime accepted.
const MAX_PATH: usize = 260;

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

/// File attributes, or `None` when the path does not exist or cannot be read.
pub(crate) fn attributes(path: &str) -> Option<u32> {
    if path.trim().is_empty() || has_invalid_path_chars(path) {
        return None;
    }
    let path = wide(path);
    // SAFETY: the path is NUL-terminated.
    let flags = unsafe { GetFileAttributesW(path.as_ptr()) };
    (flags != INVALID_FILE_ATTRIBUTES).then_some(flags)
}

/// Reads a NUL-terminated UTF-16 string.
///
/// # Safety
/// `pointer` must be null or point to a NUL-terminated UTF-16 string.
unsafe fn from_wide(pointer: *const u16) -> String {
    if pointer.is_null() {
        return String::new();
    }
    let mut length = 0usize;
    while *pointer.add(length) != 0 {
        length += 1;
    }
    String::from_utf16_lossy(std::slice::from_raw_parts(pointer, length))
}

fn parse_guid(text: &str) -> Option<Guid> {
    let digits: String = text.trim().chars().filter(|c| !matches!(c, '{' | '}' | '(' | ')' | '-')).collect();
    if digits.len() != 32 || !digits.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let byte = |index: usize| u8::from_str_radix(&digits[index..index + 2], 16).ok();
    let mut data4 = [0u8; 8];
    for (slot, value) in data4.iter_mut().enumerate() {
        *value = byte(16 + slot * 2)?;
    }
    Some(Guid {
        data1: u32::from_str_radix(&digits[..8], 16).ok()?,
        data2: u16::from_str_radix(&digits[8..12], 16).ok()?,
        data3: u16::from_str_radix(&digits[12..16], 16).ok()?,
        data4,
    })
}

/// The real machine. The decimal separator can be fixed so results do not depend on the
/// user's regional settings.
#[derive(Debug, Clone, Default)]
pub struct WindowsHost {
    decimal_separator: Option<String>,
}

impl WindowsHost {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_decimal_separator(separator: &str) -> Self {
        Self { decimal_separator: Some(separator.to_string()) }
    }
}

impl Host for WindowsHost {
    fn lower_invariant(&self, text: &str) -> String {
        let source: Vec<u16> = text.encode_utf16().collect();
        if source.is_empty() {
            return String::new();
        }
        let invariant = [0u16];
        let mut destination = vec![0u16; source.len()];
        // SAFETY: both buffers hold `source.len()` units and the locale name is NUL-terminated.
        let written = unsafe {
            LCMapStringEx(invariant.as_ptr(), LCMAP_LOWERCASE, source.as_ptr(), source.len() as i32, destination.as_mut_ptr(), destination.len() as i32, null(), null(), 0)
        };
        if written <= 0 {
            return text.to_string();
        }
        String::from_utf16_lossy(&destination[..written as usize])
    }

    fn expand_environment(&self, text: &str) -> String {
        let source = wide(text);
        // SAFETY: a null destination with size 0 asks only for the required size.
        let needed = unsafe { ExpandEnvironmentStringsW(source.as_ptr(), null_mut(), 0) };
        if needed == 0 {
            return text.to_string();
        }
        let mut destination = vec![0u16; needed as usize + 1];
        // SAFETY: the destination holds the reported size.
        let written = unsafe { ExpandEnvironmentStringsW(source.as_ptr(), destination.as_mut_ptr(), destination.len() as u32) };
        if written == 0 || written as usize > destination.len() {
            return text.to_string();
        }
        // SAFETY: the call NUL-terminated the buffer.
        unsafe { from_wide(destination.as_ptr()) }
    }

    fn file_exists(&self, path: &str) -> bool {
        if path.trim().is_empty() || has_invalid_path_chars(path) {
            return false;
        }
        let path = wide(path);
        // SAFETY: the path is NUL-terminated.
        let attributes = unsafe { GetFileAttributesW(path.as_ptr()) };
        attributes != INVALID_FILE_ATTRIBUTES && attributes & FILE_ATTRIBUTE_DIRECTORY == 0
    }

    fn directory_exists(&self, path: &str) -> bool {
        matches!(attributes(path), Some(flags) if flags & FILE_ATTRIBUTE_DIRECTORY != 0)
    }

    fn is_reparse_point(&self, path: &str) -> Option<bool> {
        attributes(path).map(|flags| flags & FILE_ATTRIBUTE_REPARSE_POINT != 0)
    }

    fn full_path(&self, path: &str) -> Option<String> {
        // The same refusals as the 3.6 runtime: blank text, illegal characters, a colon
        // anywhere but after the drive letter, and over-long paths.
        if path.trim().is_empty() || has_invalid_path_chars(path) || path.chars().enumerate().any(|(index, c)| c == ':' && index != 1) || path.encode_utf16().count() >= MAX_PATH {
            return None;
        }
        let source = wide(path);
        // SAFETY: a null buffer with size 0 asks only for the required size.
        let needed = unsafe { GetFullPathNameW(source.as_ptr(), 0, null_mut(), null_mut()) };
        if needed == 0 {
            return None;
        }
        let mut buffer = vec![0u16; needed as usize + 1];
        // SAFETY: the buffer holds the reported size.
        let written = unsafe { GetFullPathNameW(source.as_ptr(), buffer.len() as u32, buffer.as_mut_ptr(), null_mut()) };
        if written == 0 || written as usize >= buffer.len() || written as usize >= MAX_PATH {
            return None;
        }
        Some(String::from_utf16_lossy(&buffer[..written as usize]))
    }

    fn program_name(&self, command_line: &str) -> Option<String> {
        let source = wide(command_line);
        let mut count = 0i32;
        // SAFETY: the command line is NUL-terminated; the result is freed below.
        let arguments = unsafe { CommandLineToArgvW(source.as_ptr(), &mut count) };
        if arguments.is_null() {
            return None;
        }
        // SAFETY: a non-null result holds `count` pointers to NUL-terminated strings.
        let program = if count > 0 { Some(unsafe { from_wide(*arguments) }) } else { None };
        // SAFETY: the block was allocated by CommandLineToArgvW.
        unsafe { LocalFree(arguments as *mut c_void) };
        program
    }

    fn special_folder(&self, folder: SpecialFolder) -> String {
        let identifier = match folder {
            SpecialFolder::Desktop => 0x00,
            SpecialFolder::MyDocuments => 0x05,
            SpecialFolder::MyMusic => 0x0D,
            SpecialFolder::MyVideos => 0x0E,
            SpecialFolder::MyPictures => 0x27,
            SpecialFolder::ApplicationData => 0x1A,
            SpecialFolder::LocalApplicationData => 0x1C,
            SpecialFolder::CommonApplicationData => 0x23,
            SpecialFolder::Windows => 0x24,
            SpecialFolder::System => 0x25,
            SpecialFolder::ProgramFiles => 0x26,
            SpecialFolder::UserProfile => 0x28,
            SpecialFolder::ProgramFilesX86 => 0x2A,
        };
        let mut buffer = [0u16; MAX_PATH];
        // SAFETY: the API writes at most MAX_PATH units including the terminator.
        let status = unsafe { SHGetFolderPathW(null_mut(), identifier, null_mut(), 0, buffer.as_mut_ptr()) };
        if status < 0 {
            return String::new();
        }
        // SAFETY: on success the buffer is NUL-terminated.
        unsafe { from_wide(buffer.as_ptr()) }
    }

    fn known_folder(&self, guid: &str) -> Option<String> {
        let identifier = parse_guid(guid)?;
        let mut path: *mut u16 = null_mut();
        // SAFETY: `path` receives a string that is freed below in every case.
        let status = unsafe { SHGetKnownFolderPath(&identifier, 0, null_mut(), &mut path) };
        // SAFETY: on success `path` is a NUL-terminated string; a null pointer yields "".
        let result = if status == 0 { Some(unsafe { from_wide(path) }) } else { None };
        // SAFETY: the API allocates with the COM task allocator; freeing null is allowed.
        unsafe { CoTaskMemFree(path as *mut c_void) };
        result
    }

    fn decimal_separator(&self) -> String {
        if let Some(separator) = &self.decimal_separator {
            return separator.clone();
        }
        let mut buffer = [0u16; 8];
        // SAFETY: a null locale name means the user default; the buffer size is passed.
        let written = unsafe { GetLocaleInfoEx(null(), LOCALE_SDECIMAL, buffer.as_mut_ptr(), buffer.len() as i32) };
        if written <= 1 {
            return ".".to_string();
        }
        String::from_utf16_lossy(&buffer[..written as usize - 1])
    }
}
