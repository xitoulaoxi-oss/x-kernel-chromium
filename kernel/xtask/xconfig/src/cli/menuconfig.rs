// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 KylinSoft Co., Ltd. <https://www.kylinos.cn/>
// See LICENSES for license details.

use std::{io, path::PathBuf};

use crossterm::{
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};

use crate::{
    config::ConfigEngine,
    error::{KconfigError, Result},
    ui::MenuConfigApp,
    validate::validate_input_path,
};

pub fn menuconfig_command(kconfig: PathBuf, srctree: PathBuf) -> Result<()> {
    for path in [&kconfig, &srctree] {
        validate_input_path(path)?;
    }

    println!("Loading configuration...");

    let mut engine = ConfigEngine::from_kconfig(&kconfig, &srctree)?;
    println!("Parsed {} entries", engine.entries().len());

    // Try the load unconditionally: a `.config` that disappears between an
    // existence check and the open must behave like "no configuration",
    // while every other read error (permissions, invalid UTF-8, ...) stays
    // a hard error instead of silently starting from defaults.
    match engine.load_menuconfig_config(".config") {
        Ok(()) => println!("Loaded existing .config"),
        Err(KconfigError::Io(error)) if error.kind() == io::ErrorKind::NotFound => {
            println!("No existing .config found, using defaults");
        }
        Err(error) => return Err(error),
    }

    println!("Launching TUI...");

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let (entries, symbol_table, dependency_resolver) = engine.into_menuconfig_parts();
    let mut app = MenuConfigApp::new_with_resolver(entries, symbol_table, dependency_resolver)?;
    let res = app.run(&mut terminal);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    res
}
