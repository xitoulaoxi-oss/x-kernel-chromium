# Publication policy

Publish reproducible source, official pages, required configuration, test fixtures and a small representative set of real successes and failures. Keep provenance hashes for normalized evidence. Do not publish full backup directories, browser profiles/downloads, build products, VM images, screenshots/videos, local task transcripts or credentials.

Before pushing: run regression and syntax checks, validate evidence JSON/hashes, inspect the diff and tracked file list, and compare with the latest `origin/main`. Commit on top of the current remote and use a normal fast-forward push. Kernel binaries are separate Release assets.

Raw logs are archived locally before cleanup. A remote-only change must be integrated before publication; never force-push over another contributor's work.
