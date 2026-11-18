//! Starting programs the way Explorer would, and waiting for an uninstaller and its descendants.

use std::ffi::c_void;
use std::io::Read;
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::ptr::null;
use std::time::{Duration, Instant};

#[repr(C)]
struct ShellExecuteInfo {
    size: u32,
    mask: u32,
    window: isize,
    verb: *const u16,
    file: *const u16,
    parameters: *const u16,
    directory: *const u16,
    show: i32,
    instance: isize,
    id_list: *mut c_void,
    class: *const u16,
    class_key: isize,
    hot_key: u32,
    icon_or_monitor: isize,
    process: isize,
}

#[link(name = "shell32")]
extern "system" {
    fn ShellExecuteExW(info: *mut ShellExecuteInfo) -> i32;
}

#[link(name = "kernel32")]
extern "system" {
    fn GetLastError() -> u32;
    fn GetSystemTimeAsFileTime(time: *mut u64);
    fn GetTickCount64() -> u64;
    fn GetCurrentProcess() -> isize;
    fn GetCurrentProcessId() -> u32;
    fn GetProcessId(process: isize) -> u32;
    fn GetProcessTimes(process: isize, creation: *mut u64, exit: *mut u64, kernel: *mut u64, user: *mut u64) -> i32;
    fn WaitForSingleObject(handle: isize, milliseconds: u32) -> u32;
    fn GetExitCodeProcess(process: isize, code: *mut u32) -> i32;
    fn CloseHandle(handle: isize) -> i32;
    fn FormatMessageW(flags: u32, source: *const c_void, message: u32, language: u32, buffer: *mut u16, size: u32, arguments: *const c_void) -> u32;
}

#[link(name = "ntdll")]
extern "system" {
    fn NtQuerySystemInformation(class: i32, buffer: *mut u8, length: u32, returned: *mut u32) -> i32;
}

const SEE_MASK_NOCLOSEPROCESS: u32 = 0x0000_0040;
const SEE_MASK_FLAG_DDEWAIT: u32 = 0x0000_0100;
const SEE_MASK_FLAG_NO_UI: u32 = 0x0000_0400;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const INFINITE: u32 = 0xFFFF_FFFF;
const WAIT_OBJECT_0: u32 = 0;
const STATUS_INFO_LENGTH_MISMATCH: i32 = 0xC000_0004u32 as i32;
/// Ticks (100 ns) between 0001-01-01, the origin 3.6 used for times, and 1601-01-01, the origin of Windows file times.
const TICKS_BEFORE_1601: i64 = 504_911_232_000_000_000;
const TRACK_FAILURE: &str = "Cannot track the publisher uninstaller; verify removal manually.";

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Current time as a Windows file time (100 ns units since 1601, UTC).
pub fn now_filetime() -> i64 {
    let mut time = 0u64;
    // SAFETY: the pointer refers to a writable 64-bit value, which has the layout of FILETIME.
    unsafe { GetSystemTimeAsFileTime(&mut time) };
    time as i64
}

/// When Windows started, in the tick scale 3.6 stored (100 ns units since 0001-01-01, UTC).
pub fn boot_time_ticks() -> i64 {
    // SAFETY: no arguments.
    let uptime = unsafe { GetTickCount64() } as i64;
    now_filetime() + TICKS_BEFORE_1601 - uptime * 10_000
}

/// Text Windows gives for an error code.
pub fn system_message(code: u32) -> String {
    let mut buffer = [0u16; 512];
    // SAFETY: the buffer and its size are valid; FORMAT_MESSAGE_FROM_SYSTEM | IGNORE_INSERTS needs no source or arguments.
    let length = unsafe { FormatMessageW(0x0000_1000 | 0x0000_0200, null(), code, 0, buffer.as_mut_ptr(), buffer.len() as u32, null()) };
    String::from_utf16_lossy(&buffer[..length as usize]).trim().to_string()
}

/// A program started through the shell. Its handle is closed when dropped.
pub struct Launched {
    handle: isize,
    id: u32,
}

impl Drop for Launched {
    fn drop(&mut self) {
        // SAFETY: the handle came from ShellExecuteExW and is closed exactly once.
        unsafe { CloseHandle(self.handle) };
    }
}

impl Launched {
    pub fn id(&self) -> u32 {
        self.id
    }

    pub fn has_exited(&self) -> bool {
        // SAFETY: the handle is valid for the lifetime of `self`.
        unsafe { WaitForSingleObject(self.handle, 0) == WAIT_OBJECT_0 }
    }

    pub fn wait(&self) {
        // SAFETY: as above.
        unsafe { WaitForSingleObject(self.handle, INFINITE) };
    }

    pub fn exit_code(&self) -> i32 {
        let mut code = 0u32;
        // SAFETY: as above; `code` is writable.
        unsafe { GetExitCodeProcess(self.handle, &mut code) };
        code as i32
    }
}

/// Why a launch did not happen: the Windows error code and its text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchError {
    pub code: u32,
    pub message: String,
}

/// Starts a program through the shell, optionally elevated ("runas") and optionally hidden.
/// Elevation shows the UAC prompt; refusing it gives error 1223.
pub fn launch(file: &str, arguments: &str, elevate: bool, hidden: bool) -> Result<Launched, LaunchError> {
    let (file, arguments, verb) = (wide(file), wide(arguments), wide("runas"));
    let mut info = ShellExecuteInfo {
        size: std::mem::size_of::<ShellExecuteInfo>() as u32,
        mask: SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_DDEWAIT | SEE_MASK_FLAG_NO_UI,
        window: 0,
        verb: if elevate { verb.as_ptr() } else { null() },
        file: file.as_ptr(),
        parameters: arguments.as_ptr(),
        directory: null(),
        show: if hidden { 0 } else { 1 },
        instance: 0,
        id_list: std::ptr::null_mut(),
        class: null(),
        class_key: 0,
        hot_key: 0,
        icon_or_monitor: 0,
        process: 0,
    };
    // SAFETY: the structure is fully initialised and its strings outlive the call.
    if unsafe { ShellExecuteExW(&mut info) } == 0 {
        // SAFETY: no arguments.
        let code = unsafe { GetLastError() };
        return Err(LaunchError { code, message: system_message(code) });
    }
    if info.process == 0 {
        return Err(LaunchError { code: 0, message: "Publisher process unavailable; verify removal manually.".to_string() });
    }
    // SAFETY: the handle was just returned by the shell.
    let id = unsafe { GetProcessId(info.process) };
    Ok(Launched { handle: info.process, id })
}

/// One running process: its id, its parent's id and when it was created (file time).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessStamp {
    pub id: u32,
    pub parent: u32,
    pub created: i64,
}

/// Every process with its parent and creation time, read without opening any process.
/// An uninstaller elevated through UAC, and its children, cannot be opened from a standard session.
pub fn process_stamps() -> Result<Vec<ProcessStamp>, String> {
    let id_offset = if std::mem::size_of::<usize>() == 8 { 0x50 } else { 0x44 };
    let pointer = std::mem::size_of::<usize>();
    let mut length = 0x10_0000usize;
    for _ in 0..6 {
        let mut buffer = vec![0u8; length];
        let mut returned = 0u32;
        // SAFETY: the buffer and its length describe writable memory. Class 5 is SystemProcessInformation.
        let status = unsafe { NtQuerySystemInformation(5, buffer.as_mut_ptr(), buffer.len() as u32, &mut returned) };
        if status == STATUS_INFO_LENGTH_MISMATCH {
            length = (length * 2).max(returned as usize + 0x2_0000);
            continue;
        }
        if status < 0 {
            return Err(TRACK_FAILURE.to_string());
        }
        let read_u32 = |offset: usize| u32::from_le_bytes(buffer[offset..offset + 4].try_into().expect("four bytes"));
        let read_i64 = |offset: usize| i64::from_le_bytes(buffer[offset..offset + 8].try_into().expect("eight bytes"));
        let read_pointer = |offset: usize| if pointer == 8 { read_i64(offset) as u64 } else { read_u32(offset) as u64 };
        let mut rows = Vec::new();
        let mut offset = 0usize;
        loop {
            if offset + id_offset + 2 * pointer > buffer.len() {
                return Err(TRACK_FAILURE.to_string());
            }
            let next = read_u32(offset) as usize;
            let created = read_i64(offset + 0x20);
            if created < 0 {
                return Err(TRACK_FAILURE.to_string());
            }
            rows.push(ProcessStamp { id: read_pointer(offset + id_offset) as u32, parent: read_pointer(offset + id_offset + pointer) as u32, created });
            if next == 0 {
                break;
            }
            offset += next;
        }
        // Guard against a different structure layout: this process must appear with its own creation time.
        let (mut creation, mut exit, mut kernel, mut user) = (0u64, 0u64, 0u64, 0u64);
        // SAFETY: the pseudo-handle is always valid and the four out values are writable.
        let known = unsafe { GetProcessTimes(GetCurrentProcess(), &mut creation, &mut exit, &mut kernel, &mut user) } != 0;
        // SAFETY: no arguments.
        let own_id = unsafe { GetCurrentProcessId() };
        if !known || !rows.iter().any(|row| row.id == own_id && row.created == creation as i64) {
            return Err(TRACK_FAILURE.to_string());
        }
        return Ok(rows);
    }
    Err(TRACK_FAILURE.to_string())
}

struct Tracked {
    created: i64,
    gone: Option<i64>,
}

/// Waits until the uninstaller and every descendant born during this launch has ended.
///
/// Publisher launchers (including NSIS) can exit before their actual uninstaller. A tracked
/// process is identified by id plus creation time, so a reused id is never mistaken for it.
/// Publisher processes are observed only; nothing here ends them.
pub fn wait_for_uninstaller(root: &Launched, launched_at: i64) -> Result<(), String> {
    let mut tracked: std::collections::HashMap<u32, Tracked> = std::collections::HashMap::new();
    tracked.insert(root.id(), Tracked { created: launched_at, gone: None });
    loop {
        let stamps = process_stamps()?;
        let alive: std::collections::HashMap<u32, i64> = stamps.iter().map(|stamp| (stamp.id, stamp.created)).collect();
        for (id, process) in tracked.iter_mut().filter(|(_, process)| process.gone.is_none()) {
            let present = if *id == root.id() { !root.has_exited() } else { alive.get(id) == Some(&process.created) };
            if !present {
                process.gone = Some(now_filetime());
            }
        }
        loop {
            let mut added = false;
            for stamp in &stamps {
                if stamp.id == 0 || stamp.id == root.id() {
                    continue;
                }
                let Some(parent) = tracked.get(&stamp.parent) else { continue };
                if tracked.get(&stamp.id).is_some_and(|known| known.created == stamp.created) {
                    continue;
                }
                // Older than the process it names as parent, or born after that parent was gone: a reused id.
                if stamp.created < parent.created || parent.gone.is_some_and(|gone| stamp.created > gone) {
                    continue;
                }
                tracked.insert(stamp.id, Tracked { created: stamp.created, gone: None });
                added = true;
            }
            if !added {
                break;
            }
        }
        if tracked.values().all(|process| process.gone.is_some()) {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

/// Output of a program run without a window.
#[derive(Debug, Clone)]
pub struct Captured {
    pub exit_code: i32,
    pub output: String,
    pub error: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunError {
    /// The program could not be started.
    Start(String),
    /// The time limit passed; the program itself was ended.
    TimedOut,
}

/// Runs a program without a window, passing `arguments` exactly as written, and captures
/// its output as UTF-8. With a time limit, only the program itself is ended when it passes.
pub fn run_captured(program: &str, arguments: &str, timeout: Option<Duration>) -> Result<Captured, RunError> {
    let mut child = Command::new(program)
        .raw_arg(arguments)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| RunError::Start(error.to_string()))?;
    // Both pipes are drained on their own threads so a full pipe can never block the program.
    let mut stdout = child.stdout.take().expect("piped stdout");
    let mut stderr = child.stderr.take().expect("piped stderr");
    let read_output = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout.read_to_end(&mut bytes);
        bytes
    });
    let read_error = std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stderr.read_to_end(&mut bytes);
        bytes
    });
    let started = Instant::now();
    let status = loop {
        match child.try_wait().map_err(|error| RunError::Start(error.to_string()))? {
            Some(status) => break status,
            None => {
                if timeout.is_some_and(|limit| started.elapsed() > limit) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(RunError::TimedOut);
                }
                std::thread::sleep(Duration::from_millis(20));
            }
        }
    };
    let output = String::from_utf8_lossy(&read_output.join().unwrap_or_default()).into_owned();
    let error = String::from_utf8_lossy(&read_error.join().unwrap_or_default()).into_owned();
    Ok(Captured { exit_code: status.code().unwrap_or(-1), output, error })
}
