## What changed

<!-- One paragraph.  Link the issue if there is one. -->

## Why

<!-- The symptom or the gap this addresses, with a reproducible observation. -->

## How it was verified

<!--
Commands, expected readings, and the evidence directory.  "It builds" is not
verification for a kernel or harness change.
-->

- [ ] `bash -n build/*.sh` passes (if build scripts changed)
- [ ] `python -m compileall -q host` passes (if host tools changed)
- [ ] patch applies with `git apply --check` against the stated base
- [ ] `sha256sum -c artifacts/SHA256SUMS.txt` passes (if artifacts changed)
- [ ] docs links and commands were checked against the new tree
- [ ] no video or large binary was added

## Notes for reviewers

<!-- Known limitations, follow-up work, or anything deliberately left out. -->
