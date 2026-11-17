//! Records, per instrumented function, how often it ran and which distinct values its
//! arguments and return value took, then writes them as JSON when the process exits.
//!
//! Values are compared by their `Debug` output, capped at `CAP` bytes so that large
//! buffers cost little; a value whose output hit the cap is marked truncated, since two
//! truncated values that compare equal may still differ.

pub use rettrace_macros::trace;

use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::fmt::{self, Debug, Write as _};
use std::hash::{Hash, Hasher};
use std::io::Write as _;
use std::sync::{Mutex, Once};

const CAP: usize = 2048;
const MAX_DISTINCT: usize = 16;
const EXAMPLE_LEN: usize = 240;

struct Capped {
    buf: String,
    truncated: bool,
}

impl fmt::Write for Capped {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        if self.buf.len() + s.len() > CAP {
            let mut end = CAP - self.buf.len();
            while !s.is_char_boundary(end) {
                end -= 1;
            }
            self.buf.push_str(&s[..end]);
            self.truncated = true;
            return Err(fmt::Error);
        }
        self.buf.push_str(s);
        Ok(())
    }
}

/// A value's capped `Debug` output and whether it was cut short.
pub type Described = Option<(String, bool)>;

fn describe<T: Debug + ?Sized>(value: &T) -> Described {
    let mut out = Capped {
        buf: String::new(),
        truncated: false,
    };
    let _ = write!(out, "{value:?}");
    Some((out.buf, out.truncated))
}

/// Autoref specialization: `(&&Probe(&v)).rt_describe()` uses `Debug` when `v` has it.
pub struct Probe<'a, T: ?Sized>(pub &'a T);

pub trait ViaDebug {
    fn rt_describe(&self) -> Described;
}

impl<T: Debug + ?Sized> ViaDebug for &Probe<'_, T> {
    fn rt_describe(&self) -> Described {
        describe(self.0)
    }
}

pub trait ViaOpaque {
    fn rt_describe(&self) -> Described;
}

impl<T: ?Sized> ViaOpaque for Probe<'_, T> {
    fn rt_describe(&self) -> Described {
        None
    }
}

#[derive(Default)]
struct Values {
    seen: u64,
    opaque: u64,
    truncated: u64,
    /// Hash of the Debug output -> (example, count).
    distinct: HashMap<u64, (String, u64)>,
    overflow: bool,
}

impl Values {
    fn add(&mut self, value: Described) {
        self.seen += 1;
        let Some((text, truncated)) = value else {
            self.opaque += 1;
            return;
        };
        if truncated {
            self.truncated += 1;
        }
        let mut h = DefaultHasher::new();
        text.hash(&mut h);
        truncated.hash(&mut h);
        let key = h.finish();
        if let Some(entry) = self.distinct.get_mut(&key) {
            entry.1 += 1;
        } else if self.distinct.len() < MAX_DISTINCT {
            let mut example: String = text.chars().take(EXAMPLE_LEN).collect();
            if truncated || text.chars().count() > EXAMPLE_LEN {
                example.push('…');
            }
            self.distinct.insert(key, (example, 1));
        } else {
            self.overflow = true;
        }
    }
}

#[derive(Default)]
struct Stats {
    calls: u64,
    ret: Option<Values>,
    args: Vec<(&'static str, Values)>,
}

static STATE: Mutex<Option<HashMap<&'static str, Stats>>> = Mutex::new(None);
static REGISTER: Once = Once::new();

fn with_stats(label: &'static str, f: impl FnOnce(&mut Stats)) {
    REGISTER.call_once(|| unsafe {
        libc::atexit(dump);
    });
    let mut state = STATE.lock().unwrap_or_else(|e| e.into_inner());
    f(state
        .get_or_insert_with(HashMap::new)
        .entry(label)
        .or_default());
}

/// Count a call of `label`.
pub fn call(label: &'static str) {
    with_stats(label, |s| s.calls += 1);
}

/// Record the value of argument `name` of `label`.
pub fn arg(label: &'static str, name: &'static str, value: Described) {
    with_stats(label, |s| {
        let values = match s.args.iter_mut().position(|(n, _)| *n == name) {
            Some(i) => &mut s.args[i].1,
            None => {
                s.args.push((name, Values::default()));
                &mut s.args.last_mut().expect("pushed").1
            }
        };
        values.add(value);
    });
}

/// Record a return value of `label`.
pub fn ret(label: &'static str, value: Described) {
    with_stats(label, |s| s.ret.get_or_insert_with(Values::default).add(value));
}

/// Gives an async block the expected output type, so `?` inside it can convert errors.
pub fn expect_output<T, F: std::future::Future<Output = T>>(f: F) -> F {
    f
}

fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn values_json(v: &Values) -> String {
    let mut distinct: Vec<_> = v.distinct.iter().collect();
    distinct.sort_by(|a, b| b.1 .1.cmp(&a.1 .1));
    let distinct: Vec<String> = distinct
        .iter()
        .map(|(hash, (example, count))| format!("[{},{},\"{hash:016x}\"]", json_str(example), count))
        .collect();
    format!(
        "{{\"seen\":{},\"opaque\":{},\"truncated\":{},\"overflow\":{},\"distinct\":[{}]}}",
        v.seen,
        v.opaque,
        v.truncated,
        v.overflow,
        distinct.join(",")
    )
}

extern "C" fn dump() {
    let Ok(dir) = std::env::var("RETTRACE_DIR") else {
        return;
    };
    let state = STATE.lock().unwrap_or_else(|e| e.into_inner());
    let Some(state) = state.as_ref() else {
        return;
    };
    let exe = std::env::current_exe()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .unwrap_or_default();
    let mut entries: Vec<_> = state.iter().collect();
    entries.sort_by_key(|(label, _)| *label);
    let mut out = format!("{{\"exe\":{},\"functions\":{{", json_str(&exe));
    for (i, (label, stats)) in entries.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let args: Vec<String> = stats
            .args
            .iter()
            .map(|(name, v)| format!("{}:{}", json_str(name), values_json(v)))
            .collect();
        out.push_str(&format!(
            "{}:{{\"calls\":{},\"ret\":{},\"args\":{{{}}}}}",
            json_str(label),
            stats.calls,
            stats.ret.as_ref().map_or("null".to_string(), values_json),
            args.join(",")
        ));
    }
    out.push_str("}}\n");
    let path = format!("{dir}/rettrace-{exe}-{}.json", std::process::id());
    if let Ok(mut f) = std::fs::File::create(path) {
        let _ = f.write_all(out.as_bytes());
    }
}
