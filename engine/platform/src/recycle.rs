//! Sending a folder to the Recycle Bin. There is no permanent-delete path in this module.

use windows::core::{HSTRING, PCWSTR};
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_ALL, COINIT_APARTMENTTHREADED};
use windows::Win32::UI::Shell::{FileOperation, IFileOperation, IShellItem, SHCreateItemFromParsingName, FILEOPERATION_FLAGS};

/// RECYCLEONDELETE, ADDUNDORECORD, SHOWELEVATIONPROMPT, EARLYFAILURE, NOERRORUI, NOCONFIRMATION, SILENT.
const FLAGS: u32 = 0x0008_0000 | 0x2000_0000 | 0x0004_0000 | 0x0010_0000 | 0x0400 | 0x0010 | 0x0004;
const FAILURE: &str = "Windows could not recycle the whole folder. Check remaining files and Recycle Bin.";

fn recycle_on_this_thread(path: &str) -> windows::core::Result<bool> {
    // SAFETY: standard COM calls on a thread that this function initialises as a single-threaded apartment.
    unsafe {
        let item: IShellItem = SHCreateItemFromParsingName(PCWSTR(HSTRING::from(path).as_ptr()), None)?;
        let operation: IFileOperation = CoCreateInstance(&FileOperation, None, CLSCTX_ALL)?;
        operation.SetOperationFlags(FILEOPERATION_FLAGS(FLAGS))?;
        operation.DeleteItem(&item, None)?;
        operation.PerformOperations()?;
        Ok(operation.GetAnyOperationsAborted()?.as_bool())
    }
}

/// Moves a folder to the Recycle Bin, with an undo record. Succeeds only if the operation
/// was not aborted and the folder is gone from its original place afterwards.
pub fn recycle_folder(path: &str) -> Result<(), String> {
    let target = path.to_string();
    // The Shell requires a single-threaded apartment, so the work runs on its own thread.
    let outcome = std::thread::spawn(move || {
        // SAFETY: paired with CoUninitialize below when initialisation succeeded.
        let initialised = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) }.is_ok();
        let result = recycle_on_this_thread(&target);
        if initialised {
            // SAFETY: balances the successful CoInitializeEx above.
            unsafe { CoUninitialize() };
        }
        result
    })
    .join();
    match outcome {
        Ok(Ok(aborted)) => {
            if aborted || std::path::Path::new(path).is_dir() {
                Err(FAILURE.to_string())
            } else {
                Ok(())
            }
        }
        Ok(Err(error)) => Err(error.message()),
        Err(_) => Err(FAILURE.to_string()),
    }
}
