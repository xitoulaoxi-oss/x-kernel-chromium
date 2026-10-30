# Local / remote comparison

Remote main and the local baseline were both `9612b12aa5935dafa0c6898ffe8735859e1034e9` when publication started; no remote-only commits were present. The local working tree contained unpublished acceptance fixes and runtime evidence.

The publication adds those runtime/tools/tests changes, migrates three reusable aggregators from local experiments into `host/acceptance`, updates current status and removes repetitive historical evidence from the tip. The full kernel source and patch inputs are unchanged. Old tracked evidence remains accessible at the previous commit; raw uncommitted evidence was archived outside the project before cleanup.

The curated set contains 42 provenance-tracked evidence files, about 102KB, plus its manifest and publication check result. It retains successful stability/JS/CSS/input/renderer records and failed startup/hang records. It does not claim complete finals acceptance or a guest Chromium memory qualification.

Downloaded browsers, profiles, duplicate kernel ELF files, temporary fixtures and local task plans are excluded from publication. Kernel release binaries are not committed. Normal fast-forward publication is used; Git history is not rewritten.

See [evidence](../evidence/README.md) and [publication checks](../evidence/publication-checks.json).
