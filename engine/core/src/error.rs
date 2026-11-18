use std::fmt;

/// Why a rule rejected its input. The first three mirror the exception classes of 3.6,
/// so results can be compared with the recorded behaviour.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    /// 3.6: `ArgumentException`.
    Argument,
    /// 3.6: `IOException`. Used for content that parses but breaks a rule.
    Io,
    /// 3.6: `InvalidOperationException`.
    InvalidOperation,
    /// Text that is not JSON. 3.6 reported these with serializer-specific messages.
    JsonSyntax,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EngineError {
    pub kind: ErrorKind,
    pub message: String,
}

impl EngineError {
    pub fn argument(message: &str) -> Self {
        Self { kind: ErrorKind::Argument, message: message.to_string() }
    }
    pub fn io(message: &str) -> Self {
        Self { kind: ErrorKind::Io, message: message.to_string() }
    }
    pub fn invalid_operation(message: &str) -> Self {
        Self { kind: ErrorKind::InvalidOperation, message: message.to_string() }
    }
    pub fn json_syntax(message: impl fmt::Display) -> Self {
        Self { kind: ErrorKind::JsonSyntax, message: message.to_string() }
    }
}

impl fmt::Display for EngineError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for EngineError {}
