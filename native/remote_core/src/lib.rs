//! Minimal, dependency-free ABI for the HarmonyOS UI integration.
//!
//! This crate intentionally does not pretend to implement the RustDesk protocol yet.
//! The transport/session implementation will live behind `RemoteCore`, keeping the C
//! ABI and ArkTS layer stable while upstream RustDesk modules are integrated.

use std::ffi::{c_char, CStr, CString};
use std::ptr;
use std::sync::Mutex;

const VERSION: &[u8] = b"remote_core/0.1.0\0";

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RemoteState {
    Idle = 0,
    Connecting = 1,
    Authenticating = 2,
    Connected = 3,
    Reconnecting = 4,
    Failed = 5,
}

struct Session {
    state: RemoteState,
    remote_id: String,
    id_server: String,
    relay_server: String,
    api_server: String,
    public_key: String,
    use_websocket: bool,
    last_error: CString,
}

impl Default for Session {
    fn default() -> Self {
        Self {
            state: RemoteState::Idle,
            remote_id: String::new(),
            id_server: String::new(),
            relay_server: String::new(),
            api_server: String::new(),
            public_key: String::new(),
            use_websocket: false,
            last_error: CString::new("").expect("empty CString is valid"),
        }
    }
}

pub struct RemoteCore {
    session: Mutex<Session>,
}

fn read_required(value: *const c_char, field: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{field} is null"));
    }
    // SAFETY: The public ABI requires a valid, NUL-terminated UTF-8 string.
    let input = unsafe { CStr::from_ptr(value) };
    input
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{field} is not UTF-8"))
}

#[no_mangle]
pub extern "C" fn remote_core_version() -> *const c_char {
    VERSION.as_ptr().cast()
}

#[no_mangle]
pub extern "C" fn remote_core_create() -> *mut RemoteCore {
    Box::into_raw(Box::new(RemoteCore {
        session: Mutex::new(Session::default()),
    }))
}

/// Destroys a handle returned by `remote_core_create`.
///
/// # Safety
/// `core` must either be null or a unique live handle from this library.
#[no_mangle]
pub unsafe extern "C" fn remote_core_destroy(core: *mut RemoteCore) {
    if !core.is_null() {
        // SAFETY: Guaranteed by the function contract.
        drop(unsafe { Box::from_raw(core) });
    }
}

/// Records a connection request. Returns 0 when accepted and -1 on invalid input.
/// The real RustDesk session driver will replace the state transition in milestone 2.
#[no_mangle]
pub extern "C" fn remote_core_connect(
    core: *mut RemoteCore,
    remote_id: *const c_char,
    id_server: *const c_char,
    relay_server: *const c_char,
    api_server: *const c_char,
    public_key: *const c_char,
    use_websocket: u8,
) -> i32 {
    if core.is_null() {
        return -1;
    }

    let id = match read_required(remote_id, "remote_id") {
        Ok(value) if !value.trim().is_empty() => value,
        Ok(_) => return -1,
        Err(_) => return -1,
    };
    let id_server = read_required(id_server, "id_server").unwrap_or_default();
    let relay_server = read_required(relay_server, "relay_server").unwrap_or_default();
    let api_server = read_required(api_server, "api_server").unwrap_or_default();
    let public_key = read_required(public_key, "public_key").unwrap_or_default();

    if !id_server.is_empty() && public_key.len() < 16 {
        return -1;
    }

    // SAFETY: Null was rejected and the handle is owned by the caller for this call.
    let remote = unsafe { &*core };
    let mut session = remote.session.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    session.remote_id = id;
    session.id_server = id_server;
    session.relay_server = relay_server;
    session.api_server = api_server;
    session.public_key = public_key;
    session.use_websocket = use_websocket != 0;
    session.state = RemoteState::Connecting;
    session.last_error = CString::new("").expect("empty CString is valid");
    0
}

#[no_mangle]
pub extern "C" fn remote_core_disconnect(core: *mut RemoteCore) {
    if core.is_null() {
        return;
    }
    // SAFETY: Null was rejected and the handle is owned by the caller for this call.
    let remote = unsafe { &*core };
    let mut session = remote.session.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    session.state = RemoteState::Idle;
}

#[no_mangle]
pub extern "C" fn remote_core_state(core: *const RemoteCore) -> RemoteState {
    if core.is_null() {
        return RemoteState::Failed;
    }
    // SAFETY: Null was rejected; this function only reads synchronized state.
    let remote = unsafe { &*core };
    let session = remote.session.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    session.state
}

#[no_mangle]
pub extern "C" fn remote_core_last_error(core: *const RemoteCore) -> *const c_char {
    if core.is_null() {
        return ptr::null();
    }
    // SAFETY: Null was rejected. The pointer is valid until the next mutating call.
    let remote = unsafe { &*core };
    let session = remote.session.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    session.last_error.as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_idle() {
        let core = remote_core_create();
        assert_eq!(remote_core_state(core), RemoteState::Idle);
        // SAFETY: `core` is a unique handle allocated above.
        unsafe { remote_core_destroy(core) };
    }
}
