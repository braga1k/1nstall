/// Folders the rules need to know about. Same set and meaning as `Environment.SpecialFolder` in 3.6.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpecialFolder {
    Windows,
    System,
    UserProfile,
    ProgramFiles,
    ProgramFilesX86,
    CommonApplicationData,
    LocalApplicationData,
    ApplicationData,
    MyDocuments,
    Desktop,
    MyPictures,
    MyMusic,
    MyVideos,
}

/// Everything the rules ask of the machine. The Windows implementation lives in `oneinstall-platform`;
/// tests can supply a fake.
pub trait Host {
    /// Lower-casing with the invariant Windows table. It differs from Unicode lower-casing:
    /// for example it leaves U+0130 and U+1E9E unchanged.
    fn lower_invariant(&self, text: &str) -> String;
    /// Expands `%NAME%` references.
    fn expand_environment(&self, text: &str) -> String;
    /// True only for an existing file, never for a directory.
    fn file_exists(&self, path: &str) -> bool;
    fn directory_exists(&self, path: &str) -> bool;
    /// Whether a file or directory is a reparse point (junction, symbolic link, cloud
    /// placeholder). `None` when its attributes cannot be read.
    fn is_reparse_point(&self, path: &str) -> Option<bool>;
    /// Absolute, normalised path. `None` when the text is not a usable path.
    fn full_path(&self, path: &str) -> Option<String>;
    /// The program part of a command line, as Windows itself splits it.
    fn program_name(&self, command_line: &str) -> Option<String>;
    fn special_folder(&self, folder: SpecialFolder) -> String;
    /// Path of a known folder given its GUID in braces. `None` if the GUID is unknown.
    fn known_folder(&self, guid: &str) -> Option<String>;
    /// Decimal separator of the user's number format.
    fn decimal_separator(&self) -> String;
}
