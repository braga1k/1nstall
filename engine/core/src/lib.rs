//! Rules of the 1nstall engine.
//!
//! Nothing here touches the machine. Everything that depends on Windows (file existence,
//! environment expansion, path normalisation, casing tables) goes through [`Host`], so the
//! rules can be tested against the recorded 3.6 behaviour in `oracle/golden`.

/// A regular expression compiled once on first use.
macro_rules! pattern {
    ($text:expr) => {{
        static CELL: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
        CELL.get_or_init(|| regex::Regex::new($text).expect("valid pattern"))
    }};
}

pub mod error;
pub mod host;
pub mod model;
pub mod packages;
pub mod text;
pub mod uninstall;

pub use error::{EngineError, ErrorKind};
pub use host::{Host, SpecialFolder};
pub use model::{Command, InstalledApp, PackageInventory, PackageRecord, SetupEntry, SetupSelection};
