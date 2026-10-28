// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

pub mod engine;
pub mod generator;
pub mod oldconfig;
pub mod reader;
pub mod writer;

use std::{
    fs::File,
    io::{self, Write},
    path::Path,
};

pub use engine::*;
pub use generator::*;
pub use oldconfig::{ConfigChanges, OldConfigLoader};
pub use reader::*;
pub use writer::*;

use crate::error::{KconfigError, Result};

pub(crate) fn write_if_changed(path: &Path, content: &str) -> Result<bool> {
    if std::fs::read_to_string(path).is_ok_and(|existing| existing == content) {
        return Ok(false);
    }
    publish_atomically(path, content)?;
    Ok(true)
}

/// Publish `content` at `path` without writing through whatever currently
/// occupies `path`. The content is written to a fresh temporary file in the
/// destination directory and moved into place with `rename`, which replaces
/// the destination directory entry (including a symbolic link) instead of
/// following it, and never exposes a partially written configuration.
///
/// If `path` already exists as a regular file, its permissions are carried
/// over to the replacement. The temporary file is removed on every failure
/// path, leaving any previous file untouched.
fn publish_atomically(path: &Path, content: &str) -> Result<()> {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let file_name = path
        .file_name()
        .map(|name| name.to_string_lossy())
        .ok_or_else(|| {
            KconfigError::Config(format!("output path has no file name: {}", path.display()))
        })?;

    let pid = std::process::id();
    let mut attempt = 0;
    let (mut temp, temp_path) = loop {
        let temp_path = directory.join(format!(".{file_name}.tmp.{pid}.{attempt}"));
        match File::create_new(&temp_path) {
            Ok(temp) => break (temp, temp_path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => attempt += 1,
            Err(error) => return Err(error.into()),
        }
    };

    let published = (|| -> io::Result<()> {
        // Carry over the permissions of an existing regular file so replacing
        // it does not silently widen or narrow access.
        if let Ok(metadata) = std::fs::symlink_metadata(path)
            && metadata.file_type().is_file()
        {
            temp.set_permissions(metadata.permissions())?;
        }
        temp.write_all(content.as_bytes())?;
        temp.sync_all()
    })();
    drop(temp);
    if let Err(error) = published.and_then(|()| std::fs::rename(&temp_path, path)) {
        let _ = std::fs::remove_file(&temp_path);
        return Err(error.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::write_if_changed;

    #[test]
    fn unchanged_content_is_not_rewritten() {
        let temp_dir = TempDir::new().unwrap();
        let path = temp_dir.path().join("generated");

        assert!(write_if_changed(&path, "value\n").unwrap());
        assert!(!write_if_changed(&path, "value\n").unwrap());
        assert!(write_if_changed(&path, "new value\n").unwrap());
    }

    #[test]
    fn symlinked_output_is_replaced_not_followed() {
        let temp_dir = TempDir::new().unwrap();
        let victim = temp_dir.path().join("victim");
        std::fs::write(&victim, "victim\n").unwrap();
        let path = temp_dir.path().join("generated");
        std::os::unix::fs::symlink(&victim, &path).unwrap();

        assert!(write_if_changed(&path, "value\n").unwrap());

        // The symlink target must be untouched and the output directory entry
        // must now be a regular file holding the new content.
        assert_eq!(std::fs::read_to_string(&victim).unwrap(), "victim\n");
        let metadata = std::fs::symlink_metadata(&path).unwrap();
        assert!(metadata.file_type().is_file());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "value\n");
    }

    #[test]
    fn replaced_file_keeps_permissions_and_leaves_no_temporaries() {
        use std::os::unix::fs::PermissionsExt;

        let temp_dir = TempDir::new().unwrap();
        let path = temp_dir.path().join("generated");
        std::fs::write(&path, "old\n").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();

        assert!(write_if_changed(&path, "value\n").unwrap());

        let metadata = std::fs::metadata(&path).unwrap();
        assert_eq!(metadata.permissions().mode(), 0o100600);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "value\n");

        let leftovers: Vec<_> = std::fs::read_dir(temp_dir.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .filter(|name| name.to_string_lossy().contains(".tmp."))
            .collect();
        assert!(leftovers.is_empty(), "leftover temporaries: {leftovers:?}");
    }
}
