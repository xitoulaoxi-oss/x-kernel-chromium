# Optional monotonic-clock helper

`guest/mono-clock.c` is source for the existing CLOCK_MONOTONIC diagnostic. The binary stays local. Default `guest/serve-pages.txt` serves official pages and shell helpers without requiring this diagnostic ELF.

With an AArch64 Linux cross compiler installed, build a static helper from the repository root, for example:

```sh
aarch64-linux-gnu-gcc -O2 -static -o guest/mono-clock guest/mono-clock.c
```

This is a documented build recipe, not a build executed during this review. Before a clock diagnostic, create a session-specific serve manifest copied from guest/serve-pages.txt and append guest/mono-clock; pass that manifest via -ServeManifest. Verify the guest binary's hash. The prior real helper run is preserved in the 134500Z/06 log. Ordinary smoke/functional sessions do not need this helper.
