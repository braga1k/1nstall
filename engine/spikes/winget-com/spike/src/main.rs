// Isolated test: can a plain Rust process use the WinGet COM API, and does it give a complete inventory?
// Read-only. Prints counts only.
mod bindings;

use std::time::Instant;

use bindings::Microsoft::Management::Deployment::*;
use windows::core::{Interface, Result, GUID};
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_LOCAL_SERVER, COINIT_MULTITHREADED};

const PACKAGE_MANAGER: GUID = GUID::from_u128(0xC53A4F16_787E_42A4_B304_29EFFB4BF597);
const FIND_PACKAGES_OPTIONS: GUID = GUID::from_u128(0x572DED96_9C60_4526_8F92_EE7D91D38C1A);
const COMPOSITE_OPTIONS: GUID = GUID::from_u128(0x526534B8_7E46_47C8_8416_B1685C327D37);

fn create<T: Interface>(class: &GUID) -> Result<T> {
    unsafe { CoCreateInstance(class, None, CLSCTX_LOCAL_SERVER) }
}

fn run(in_process: bool) -> Result<()> {
    println!("--- {}", if in_process { "through the factory DLL shipped next to the program" } else { "plain CoCreateInstance" });
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    let clock = Instant::now();
    let manager = if in_process { PackageManager::new()? } else { create(&PACKAGE_MANAGER)? };
    println!("activation: ok in {:.2}s", clock.elapsed().as_secs_f32());

    let clock = Instant::now();
    let local = manager.GetLocalPackageCatalog(LocalPackageCatalog::InstalledPackages)?;
    let connection = local.Connect()?;
    println!("local catalog: status {:?}", connection.Status()?);
    let options = if in_process { FindPackagesOptions::new()? } else { create(&FIND_PACKAGES_OPTIONS)? };
    let found = connection.PackageCatalog()?.FindPackages(&options)?;
    println!("local catalog: {} installed packages, find status {:?}, {:.2}s", found.Matches()?.Size()?, found.Status()?, clock.elapsed().as_secs_f32());

    let clock = Instant::now();
    let winget = manager.GetPredefinedPackageCatalog(PredefinedPackageCatalog::OpenWindowsCatalog)?;
    let composite = if in_process { CreateCompositePackageCatalogOptions::new()? } else { create(&COMPOSITE_OPTIONS)? };
    composite.Catalogs()?.Append(&winget)?;
    composite.SetCompositeSearchBehavior(CompositeSearchBehavior::LocalCatalogs)?;
    let connection = manager.CreateCompositePackageCatalog(&composite)?.Connect()?;
    println!("composite catalog: status {:?}", connection.Status()?);
    let options = if in_process { FindPackagesOptions::new()? } else { create(&FIND_PACKAGES_OPTIONS)? };
    let found = connection.PackageCatalog()?.FindPackages(&options)?;
    let matches = found.Matches()?;
    let (mut with_id, mut with_version, mut correlated) = (0u32, 0u32, 0u32);
    for index in 0..matches.Size()? {
        let package = matches.GetAt(index)?.CatalogPackage()?;
        if !package.Id()?.is_empty() {
            with_id += 1;
        }
        if package.InstalledVersion().and_then(|version| version.Version()).map(|text| !text.is_empty()).unwrap_or(false) {
            with_version += 1;
        }
        // A package correlated with the winget source offers a default install version from that catalog.
        if let Ok(version) = package.DefaultInstallVersion() {
            if version.PackageCatalog().and_then(|catalog| catalog.Info()).and_then(|info| info.Name()).map(|name| name == "winget").unwrap_or(false) {
                correlated += 1;
            }
        }
    }
    println!("composite catalog: {} packages; with id {with_id}; with installed version {with_version}; correlated with winget {correlated}; {:.2}s", matches.Size()?, clock.elapsed().as_secs_f32());
    Ok(())
}

fn main() {
    for in_process in [false, true] {
        if let Err(error) = run(in_process) {
            println!("FAILED: 0x{:08X} {}", error.code().0 as u32, error.message());
        }
    }
}
