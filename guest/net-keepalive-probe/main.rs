// TCP keep-alive sockopt probe for the X-Kernel guest.
//
// The delivered rootfs has no interpreter (no python, no perl, no apt), so the
// only way to exercise setsockopt from inside the guest is a static binary.
//
// No dependencies on purpose: `libc` is not needed for two extern declarations,
// and a crate-free build works without network access.
//
// Linux uapi values (`include/uapi/linux/tcp.h`):
//   TCP_KEEPIDLE  = 4   -- idle time before the first probe, seconds
//   TCP_KEEPINTVL = 5   -- interval between probes, seconds
//   TCP_KEEPCNT   = 6   -- number of failed probes before giving up
//
// Before the pr-c patch every one of these answers ENOPROTOOPT (92); after it the
// values round-trip through getsockopt.

use std::io;
use std::net::{TcpListener, TcpStream};
use std::os::fd::{AsRawFd, RawFd};

const IPPROTO_TCP: i32 = 6;
const SET_VALUE: i32 = 30;
const EOPNOTSUPP: i32 = 95;
const ENOPROTOOPT: i32 = 92;

const OPTIONS: [(&str, i32); 3] = [
    ("TCP_KEEPIDLE", 4),
    ("TCP_KEEPINTVL", 5),
    ("TCP_KEEPCNT", 6),
];

extern "C" {
    fn setsockopt(fd: i32, level: i32, name: i32, value: *const i32, len: u32) -> i32;
    fn getsockopt(fd: i32, level: i32, name: i32, value: *mut i32, len: *mut u32) -> i32;
}

fn set(fd: RawFd, name: i32, value: i32) -> io::Result<()> {
    // SAFETY: `value` is a live i32 and the size matches what the kernel reads.
    let rc = unsafe { setsockopt(fd, IPPROTO_TCP, name, &value, 4) };
    if rc == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

fn get(fd: RawFd, name: i32) -> io::Result<i32> {
    let mut value: i32 = 0;
    let mut len: u32 = 4;
    // SAFETY: `value` and `len` are live and describe a 4-byte i32 buffer.
    let rc = unsafe { getsockopt(fd, IPPROTO_TCP, name, &mut value, &mut len) };
    if rc == 0 {
        Ok(value)
    } else {
        Err(io::Error::last_os_error())
    }
}

fn main() {
    println!("=== keepalive probe start ===");
    println!("kernel: {}", kernel_version());

    // A connected TCP socket: keep-alive options are per socket, and an
    // unconnected descriptor would not tell us the option path works.
    let listener = match TcpListener::bind(("127.0.0.1", 0)) {
        Ok(l) => l,
        Err(e) => {
            println!("bind failed: {e}");
            println!("=== keepalive probe end ===");
            std::process::exit(2);
        }
    };
    let addr = listener.local_addr().expect("local_addr");
    let stream = match TcpStream::connect(addr) {
        Ok(s) => s,
        Err(e) => {
            println!("connect failed: {e}");
            println!("=== keepalive probe end ===");
            std::process::exit(2);
        }
    };
    let fd = stream.as_raw_fd();

    let mut failures = 0;
    for (name, opt) in OPTIONS {
        match set(fd, opt, SET_VALUE) {
            Ok(()) => match get(fd, opt) {
                Ok(back) if back == SET_VALUE => {
                    println!("{name} set ok, read back {back}");
                }
                Ok(back) => {
                    println!("{name} set ok but read back {back}, expected {SET_VALUE}");
                    failures += 1;
                }
                Err(e) => {
                    println!("{name} getsockopt failed: {e}");
                    failures += 1;
                }
            },
            Err(e) => {
                let code = e.raw_os_error().unwrap_or(0);
                let what = match code {
                    ENOPROTOOPT => "ENOPROTOOPT",
                    EOPNOTSUPP => "EOPNOTSUPP",
                    _ => "error",
                };
                println!("{name} FAILED: {e} ({what} {code})");
                failures += 1;
            }
        }
    }

    println!("=== keepalive probe end ===");
    drop(stream);
    drop(listener);
    std::process::exit(if failures == 0 { 0 } else { 1 });
}

/// First three fields of `/proc/version`, so the log says which kernel ran.
///
/// The init shell that the harness reaches starts before `/proc` is mounted, so
/// this is usually unavailable; the harness transcript carries the boot banner
/// (git_commit / build_id) instead, which identifies the kernel better anyway.
fn kernel_version() -> String {
    match std::fs::read_to_string("/proc/version") {
        Ok(text) => text.split_whitespace().take(3).collect::<Vec<_>>().join(" "),
        Err(_) => "n/a (/proc not mounted in this shell)".to_string(),
    }
}
