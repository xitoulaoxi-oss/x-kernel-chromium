// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

//! Payload for a mini-oci guest smoke test.
//!
//! Launch through `mini-oci run smoke BUNDLE` with cwd `/`, `OCI_SMOKE=1`, and
//! procfs available in the configured rootfs. The program asserts cgroup membership
//! starts with `0::/oci-smoke`, validates cwd/environment, then prints
//! `OCI_SMOKE_PASS pid=...`. Missing or mismatched state panics; this validates
//! setup observations, not complete container isolation.

fn main() {
    let cgroup = std::fs::read_to_string("/proc/self/cgroup").expect("read cgroup membership");
    assert!(
        cgroup.starts_with("0::/oci-smoke"),
        "unexpected cgroup: {cgroup:?}"
    );
    assert_eq!(std::env::current_dir().unwrap().to_str(), Some("/"));
    assert_eq!(std::env::var("OCI_SMOKE").as_deref(), Ok("1"));
    println!("OCI_SMOKE_PASS pid={}", std::process::id());
}
