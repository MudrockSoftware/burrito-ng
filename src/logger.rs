//! Tiny prefix-style logger for user-facing wrapper messages.
//!
//! Output errors (e.g. a closed pipe) are deliberately ignored, logging must never crash the wrapper.

use std::fmt::Arguments;
use std::io::{self, Write};

pub fn print_stdout(prefix: &str, args: Arguments, newline: bool) {
    let mut out = io::stdout().lock();
    let _ = write!(out, "{prefix}{args}");
    if newline {
        let _ = writeln!(out);
    }
    let _ = out.flush();
}

pub fn print_stderr(prefix: &str, args: Arguments) {
    let mut err = io::stderr().lock();
    let _ = writeln!(err, "{prefix}{args}");
}

/// A question to the user, printed to stdout without a trailing newline.
macro_rules! query {
    ($($arg:tt)*) => { $crate::logger::print_stdout("[?] ", format_args!($($arg)*), false) };
}

macro_rules! info {
    ($($arg:tt)*) => { $crate::logger::print_stdout("[i] ", format_args!($($arg)*), true) };
}

macro_rules! log_stderr {
    ($($arg:tt)*) => { $crate::logger::print_stderr("[l] ", format_args!($($arg)*)) };
}

macro_rules! warning {
    ($($arg:tt)*) => { $crate::logger::print_stderr("[w] ", format_args!($($arg)*)) };
}

macro_rules! err {
    ($($arg:tt)*) => { $crate::logger::print_stderr("[!] ", format_args!($($arg)*)) };
}

/// Debug output, only emitted by non-production (debug) wrapper builds.
macro_rules! debug {
    ($($arg:tt)*) => {
        if !$crate::config::IS_PROD {
            $crate::logger::print_stderr("debug: ", format_args!($($arg)*))
        }
    };
}

pub(crate) use {debug, err, info, log_stderr, query, warning};
