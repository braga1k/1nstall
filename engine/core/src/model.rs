/// One uninstall registration as the engine sees it. Text fields are optional because the
/// registry may simply not have them.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct InstalledApp {
    pub id: Option<String>,
    pub name: Option<String>,
    pub publisher: Option<String>,
    pub version: Option<String>,
    pub kind: Option<String>,
    pub location: Option<String>,
    pub command: Option<String>,
    pub registry_path: Option<String>,
    pub package_family: Option<String>,
    pub machine: bool,
    pub view32: bool,
    pub msi: bool,
    pub removal_verified: bool,
    pub ownership_verified: bool,
    pub identity_verified: bool,
    pub restart_requested_at: i64,
    pub can_remove: bool,
    pub size_kb: i64,
}

/// A program to start and the raw argument text to pass to it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Command {
    pub file_name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageRecord {
    pub id: Option<String>,
    pub name: Option<String>,
    pub source: Option<String>,
    pub installed_version: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PackageInventory {
    /// Every installed package is listed; absence means not installed.
    pub complete: bool,
    /// Only some packages are listed; absence means unknown.
    pub partial: bool,
    pub packages: Vec<PackageRecord>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupEntry {
    pub id: String,
    pub source: String,
    pub name: String,
    pub version: String,
}

/// A saved selection. Version 1 lists catalog keys; version 2 lists package identities.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SetupSelection {
    pub version: i32,
    pub keys: Vec<String>,
    pub apps: Vec<SetupEntry>,
}
