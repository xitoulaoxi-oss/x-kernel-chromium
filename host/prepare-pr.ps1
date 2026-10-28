# prepare-pr.ps1 -- turn the port-to-main patches into branches ready to push and
# open as pull requests against openkylin/x-kernel.
#
# WHY THIS DESIGN.  patches/x-kernel-solution.patch was written against the
# competition baseline d3a6ec9, which is now 31 commits behind upstream main; most
# of its files no longer apply.  patches/upstream/port-to-main/*.patch were regenerated as
# diff(current main -> our changed files) for exactly the files where that diff
# reverts nothing upstream, so each one applies to main by construction.  Branches
# built from those will merge, which is the whole point of a pull request.
#
# WHAT IT DOES
#   1. gets an x-kernel checkout (clones if needed, or reuses one)
#   2. verifies every patch still applies to main (read-only probe)
#   3. creates one branch per patch off main, applies it, commits
#   4. prints the exact push and Gitee steps -- it never pushes for you
#
# ASCII only, deliberately: PowerShell 5.1 reads a .ps1 as ANSI when it has no BOM,
# so a non-ASCII literal here would arrive as mojibake (same rule as xkwin.ps1).
#
# Usage, from the repository root:
#     powershell -NoProfile -ExecutionPolicy Bypass -File host\prepare-pr.ps1 -GitName you -GitEmail you@example.com
#     ... -Only pr-a-aarch64-sctlr-uct-uci            (just one group)
#     ... -Checkout D:\work\x-kernel -NoClone         (reuse an existing clone)

param(
    [string]$Checkout = "$env:USERPROFILE\x-kernel-pr",
    # IMPORTANT: this is the Gitee LOGIN NAME, i.e. the path segment in
    # https://gitee.com/<this>/x-kernel -- NOT the display name shown on the page.
    # The two often differ (display name "Alice", login name "alice123"), and git
    # only accepts the login name.  When the 'fork' remote already exists the script
    # takes it from that URL instead, which is authoritative.
    [string]$GiteeUser = '',
    [string]$GitName = '',
    [string]$GitEmail = '',
    [string]$Upstream = 'https://gitee.com/openkylin/x-kernel.git',
    # Branch every PR off this.  main is right: it is what reviewers merge into.
    [string]$Base = 'main',
    [switch]$NoClone,
    [string[]]$Only = @()
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pkg  = [System.IO.Path]::GetFullPath((Join-Path $here '..'))
$portDir = Join-Path $pkg 'patches\upstream\port-to-main'

if (-not (Test-Path -LiteralPath $portDir)) {
    throw "port-to-main patches not found: $portDir"
}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Step($n, $msg) { Write-Host ""; Write-Host "[$n] $msg" -ForegroundColor Cyan }

# Purpose and description per patch.  A reviewer reads the title first, so each one
# states the symptom, then what the fix does.
$Meta = @{
    'pr-a-aarch64-sctlr-uct-uci' = @{
        Title = 'aarch64: allow EL0 reads of CTR_EL0 (clear SCTLR_EL1.UCT/UCI)'
        Why   = ('With the reset value of SCTLR_EL1 the kernel traps EL0 reads of CTR_EL0 and EL0 cache maintenance, but does not claim that trap, so the exception is delivered to user space as SIGILL. libgcc reads CTR_EL0 to size the cache line during initialisation, so any dynamically linked process that loads it dies at start-up. Clearing UCT and UCI in init_mmu() is what Linux does on this CPU; the VHE configuration is excluded because the same control bits then live in SCTLR_EL2.')
    }
    'pr-b-drm-legacy-modeset' = @{
        Title = 'io/drmdevice: legacy ADDFB, MODE_CURSOR and SET_CLIENT_CAP semantics'
        Why   = ('The modesetting driver probes the legacy ADDFB ioctl, asks for the cursor through MODE_CURSOR, and sets client capabilities; none of those were handled, so ScreenInit never completed and nothing reached the scanout. This translates legacy ADDFB into ADDFB2 and reuses one implementation, implements MODE_CURSOR, and makes SET_CLIENT_CAP follow Linux drm_setclientcap() semantics (unknown cap returns EOPNOTSUPP, value greater than 1 returns EINVAL). Also reports an unknown framebuffer from DIRTYFB as ENOENT, which is what drm_mode_dirtyfb_ioctl() returns. The regression test in io/drmdevice/tests/mode.rs drives real fds and real ioctls rather than mocks.')
    }
    'pr-c-tcp-keepalive' = @{
        Title = 'net/knet: accept TCP_KEEPIDLE, TCP_KEEPINTVL and TCP_KEEPCNT'
        Why   = ('A network service that sets the three keep-alive knobs at start-up retries on every rejection, which floods the console, and never gets the idle timeout it asked for. TCP_KEEPIDLE is wired to the smoltcp keep-alive idle timer so it takes effect; TCP_KEEPINTVL and TCP_KEEPCNT have no second knob in smoltcp, so they are recorded and read back by getsockopt instead of being accepted as silent no-ops.')
    }
    'pr-f-gem-close-closefb' = @{
        Title = 'io/drmdevice: implement GEM_CLOSE and MODE_CLOSEFB'
        Why   = ('Two teardown ioctls were missing, so a client could not release a handle or a framebuffer through the interfaces it actually uses. GEM_CLOSE (0x09) is the GEM spelling of the dumb-buffer release that DESTROY_DUMB (0xB4) already performs: both end in drm_gem_handle_delete() on Linux, so they now share one take_dumb() helper instead of keeping two copies of the teardown. MODE_CLOSEFB (0xD0) is the checked variant of RMFB (0xAF) -- it answers an unknown framebuffer with ENOENT and refuses with EBUSY while the framebuffer is still bound to the legacy CRTC or to the plane, which is what Linux drm_mode_closefb_ioctl() does and what RMFB here does not. Both are listed in IK946N item 5. GEM_CLOSE follows the kernel in reporting an unknown handle as EINVAL rather than the ENOENT that IK946N sketches, because that is what drm_gem_handle_delete() returns.')
    }
    'pr-g-drm-set-property' = @{
        Title = 'io/drmdevice: implement MODE_SETPROPERTY and MODE_OBJ_SETPROPERTY'
        Why   = ('Both property-setting entry points were missing, so a client that does not use atomic commits had no way to write a property at all -- MODE_ATOMIC was the only caller of the internal property table. MODE_SETPROPERTY (0xAB) is the legacy connector-only form and MODE_OBJ_SETPROPERTY (0xBA) carries an explicit object type; each is a thin adapter that resolves the target and then runs the same apply_prop() the atomic path drives, through one shared set_one_property() that repeats atomic''s copy-unlock-commit sequence. That keeps the three entry points from drifting apart, and an unknown property is reported as ENOENT, which is what drm_mode_setproperty_user() returns. The uapi layouts are pinned with compile-time size assertions: struct drm_mode_obj_set_property is 24 bytes and not 20, because the structure aligns to 8 and its last field ends at offset 20. Getting that padding wrong changes the command word and silently makes the handler unreachable, which is exactly what happened to MODE_CURSOR earlier in this series. Listed as item 5 of IK946N.')
    }
    'pr-d-tmpfs-modes' = @{
        Title = 'fs/boot: mount tmpfs with the modes Linux uses (1777 for /dev/shm and /tmp)'
        Why   = ('/dev/shm and /tmp were mounted 0755, so a non-root process could not create a shared-memory segment there and anything relying on POSIX shared memory failed. Linux mounts both 1777, which is what makes them usable by every user while still preventing deletion of other users entries. The mode is applied to the mounted tmpfs root, not to the mount point before mounting, because the latter is overwritten by the mount.')
    }
    'pr-e-inotify-new-files' = @{
        Title = 'fs: add the inotify core objects (fd, watch table, event queue, VFS notifications)'
        Why   = ('inotify_init1 was routed to sys_dummy_fd and always returned ENOSYS, and there was no event source at all, so a watch could never fire. This adds the objects inotify needs: a real fd with a watch table, a per-watch event queue with a path index, a notifier abstraction, and the VFS-level IN_CREATE hook that feeds it. Event layout matches Linux: 16-byte header, NUL-terminated name padded to 8 bytes. The call wiring lands separately so that this can be reviewed as data structures plus one hook.')
    }
}

# --- patches to work on ------------------------------------------------------
$patchFiles = Get-ChildItem -LiteralPath $portDir -Filter '*.patch' | Sort-Object Name
if ($Only.Count -gt 0) {
    $patchFiles = $patchFiles | Where-Object { $Only -contains ($_.BaseName) }
}
if (-not $patchFiles) {
    throw "no patch matched. Available: $((Get-ChildItem -LiteralPath $portDir -Filter '*.patch' | ForEach-Object { $_.BaseName }) -join ', ')"
}

Say ""
Say "package : $pkg"
Say "patches : $portDir"
Say ("  " + $patchFiles.Count + " pull request(s) to prepare, based on upstream '$Base'")

# --- 1. checkout -------------------------------------------------------------
Step 1 "checkout"
if (-not (Test-Path -LiteralPath $Checkout)) {
    if ($NoClone) { throw "-NoClone was given but $Checkout does not exist" }
    Say "  cloning $Upstream"
    Say "  a full clone, not --filter=blob:none: a partial clone makes git apply and"
    Say "  git push fetch objects on demand, which fails as soon as the network does."
    & git clone $Upstream $Checkout
    if ($LASTEXITCODE -ne 0) { throw "git clone failed. Clone it by hand, then re-run with -Checkout <dir> -NoClone" }
} else {
    Say "  reusing $Checkout"
    Push-Location $Checkout
    $filter = (& git config --get remote.origin.partialclonefilter) 2>$null
    Pop-Location
    if ($filter) {
        Say ("  WARNING: this is a partial clone (filter=" + $filter + ").") 'Yellow'
        Say "  It needs the network for git apply / git push. If those fail, re-clone" 'Yellow'
        Say "  without --filter=blob:none, or run: git fetch --refetch --filter=blob:limit=1m origin" 'Yellow'
    }
}

Push-Location $Checkout
try {
    # Native git calls that are expected to fail must not terminate the script:
    # under $ErrorActionPreference='Stop' a native command's stderr becomes a
    # terminating ErrorRecord, so e.g. `git branch -D <missing>` would abort.
    function Invoke-Git {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $out = @(& git @GitArgs 2>&1)
            return [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
        } finally {
            $ErrorActionPreference = $prev
        }
    }

    if ((Invoke-Git rev-parse --is-inside-work-tree).Out -join '' -ne 'true') {
        throw "$Checkout is not a git checkout"
    }

    Step 2 "git identity"
    $name  = (Invoke-Git config user.name).Out  -join ''
    $email = (Invoke-Git config user.email).Out -join ''
    if ((-not $name) -and $GitName)   { Invoke-Git config --global user.name  $GitName  | Out-Null; $name  = $GitName }
    if ((-not $email) -and $GitEmail) { Invoke-Git config --global user.email $GitEmail | Out-Null; $email = $GitEmail }
    if (-not $name -or -not $email) {
        Say "  user.name / user.email are not set; git will refuse to commit." 'Yellow'
        Say "  Use the address verified on your Gitee account (https://gitee.com/profile/emails),"
        Say "  otherwise the commit is not attributed to you and the PR does not count."
        Say '  Re-run with: -GitName yourname -GitEmail you@example.com' 'Yellow'
        throw "set your git identity first, then re-run"
    }
    Say "  $name <$email>"

    # Username from an existing fork remote is authoritative; else the parameter.
    if (-not $GiteeUser) {
        if (((Invoke-Git remote).Out) -contains 'fork') {
            $url = (Invoke-Git remote get-url fork).Out -join ''
            $m = [regex]::Match($url, 'gitee\.com[:/](?<u>[^/]+)/')
            if ($m.Success) { $GiteeUser = $m.Groups['u'].Value; Say "  Gitee user from 'fork' remote: $GiteeUser" 'Green' }
        }
    }
    if (-not $GiteeUser) { $GiteeUser = $env:XK_GITEE_USER }
    if ($GiteeUser) { Say "  Gitee user: $GiteeUser" }

    Step 3 "update and check out $Base"
    $f = Invoke-Git fetch origin
    if ($f.Code -ne 0) { Say "  fetch failed (offline?) -- continuing with what is local" 'Yellow' }
    # --force, because a previous interrupted run can leave an applied-but-uncommitted
    # patch in the worktree; without it the checkout either refuses or carries the
    # stale changes into the probe below and every patch looks broken.
    $co = Invoke-Git checkout --force --quiet $Base
    if ($co.Code -ne 0) {
        Say ("  " + ($co.Out -join ' | ')) 'Red'
        throw "cannot check out $Base"
    }
    $rs = Invoke-Git reset --hard --quiet $Base | Out-Null
    $pull = Invoke-Git pull --ff-only origin $Base
    if ($pull.Code -ne 0) { Say "  pull --ff-only did not fast-forward; using the local $Base" 'Yellow' }
    $dirty = ((Invoke-Git status --porcelain).Out | Where-Object { $_ })
    if ($dirty) {
        Say ("  WARNING: worktree still has " + $dirty.Count + " uncommitted item(s) after reset:") 'Yellow'
        foreach ($d in ($dirty | Select-Object -First 5)) { Say ("    " + $d) 'Yellow' }
    }
    Say ("  at " + ((Invoke-Git rev-parse --short HEAD).Out -join ''))

    Step 4 "does each patch still apply? (read-only)"
    $applicable = @()
    foreach ($p in $patchFiles) {
        $chk = Invoke-Git apply --check $p.FullName
        if ($chk.Code -eq 0) {
            Say ("  OK   " + $p.BaseName) 'Green'
            $applicable += $p
        } else {
            Say ("  FAIL " + $p.BaseName) 'Red'
            foreach ($l in ($chk.Out | Select-Object -First 4)) { Say ("       " + $l) 'Red' }
            Say "       skipped: upstream moved again since this patch was generated." 'Yellow'
        }
    }
    if (-not $applicable) { throw "no patch applies to $Base -- nothing to prepare" }

    Step 5 "create one branch per patch"
    $made = @()
    foreach ($p in $applicable) {
        $branch = $p.BaseName
        Say ""
        Say ("  --- " + $branch + " ---") 'White'

        # Clean the worktree before touching it.  A previous run that stopped after
        # `git apply` but before `git commit` leaves the patch staged in the worktree,
        # and the next attempt then fails with "patch does not apply" -- which reads
        # like a broken patch when it is only leftover state.  This checkout is a
        # scratch tree for building branches, so discarding tracked changes here is
        # intended; -B then creates or resets the branch.
        $co = Invoke-Git checkout --force --quiet $Base
        if ($co.Code -ne 0) { throw ("cannot force-checkout " + $Base + ": " + ($co.Out -join ' ')) }
        $rs = Invoke-Git reset --hard --quiet $Base
        if ($rs.Code -ne 0) { throw ("cannot reset to " + $Base + ": " + ($rs.Out -join ' ')) }

        # Files the patch CREATES must not already exist, or applying it fails on
        # "already exists".  They can survive a forced checkout because they are
        # untracked, so remove exactly those and nothing else.
        $newPaths = @()
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $p.FullName -Raw),
                                        '(?m)^diff --git a/(\S+) b/\S+\r?\nnew file mode')) {
            $newPaths += $m.Groups[1].Value
        }
        foreach ($np in $newPaths) {
            $full = Join-Path $Checkout $np
            if (Test-Path -LiteralPath $full) {
                $tracked = (Invoke-Git ls-files --error-unmatch $np).Code -eq 0
                if (-not $tracked) {
                    Remove-Item -LiteralPath $full -Force
                    Say ("    removed leftover untracked " + $np) 'Yellow'
                }
            }
        }

        $bc = Invoke-Git checkout --quiet -B $branch
        if ($bc.Code -ne 0) { throw ("cannot create branch " + $branch + ": " + ($bc.Out -join ' ')) }

        $ap = Invoke-Git apply $p.FullName
        if ($ap.Code -ne 0) { throw ("apply failed for " + $branch + ": " + ($ap.Out -join ' ')) }
        Invoke-Git add -A | Out-Null

        # NOTE: the local must NOT be called $meta -- PowerShell variable names are
        # case-insensitive, so `$meta = $Meta[$branch]` would assign back into $Meta
        # itself: the first iteration replaces the table with one entry, the second
        # nulls it, the third fails with "cannot index into a null array".
        $entry = $Meta[$branch]
        $title = if ($entry) { $entry.Title } else { $branch }
        $why   = if ($entry) { $entry.Why }   else { 'See patches/upstream/port-to-main/' + $branch + '.patch' }
        $msgFile = Join-Path $portDir ('.' + $branch + '.msg')
        [System.IO.File]::WriteAllText($msgFile, ($title + "`n`n" + $why + "`n"),
                                       (New-Object System.Text.UTF8Encoding($false)))
        $cm = Invoke-Git commit --quiet -F $msgFile
        Remove-Item $msgFile -Force -ErrorAction SilentlyContinue
        if ($cm.Code -ne 0) { throw ("commit failed for " + $branch + ": " + ($cm.Out -join ' ')) }

        $files = ((Invoke-Git show --pretty=format: --name-only HEAD).Out | Where-Object { $_ }) -join ', '
        Say ("    committed: " + $files) 'Green'
        $made += [pscustomobject]@{ Branch = $branch; Title = $title; Why = $why }
    }

    Step 6 "manual steps (nothing was pushed)"
    if (-not $GiteeUser) {
        Say "  Gitee username unknown; <YOU> is a placeholder." 'Yellow'
        Say "  Re-run with -GiteeUser yourname for ready-to-paste commands." 'Yellow'
        $GiteeUser = '<YOU>'
    }
    Say ""
    Say "  a) Fork once: https://gitee.com/openkylin/x-kernel -> Fork"
    Say "     Your copy becomes https://gitee.com/$GiteeUser/x-kernel"
    Say ""
    Say "  b) Push each branch:"
    Say "       git remote add fork https://gitee.com/$GiteeUser/x-kernel.git"
    foreach ($m in $made) { Say ("       git push fork " + $m.Branch + ":" + $m.Branch) }
    Say ""
    Say "  c) For each branch: https://gitee.com/openkylin/x-kernel/pulls -> new PR"
    Say "       source : $GiteeUser/x-kernel : <branch>"
    Say "       target : openkylin/x-kernel : main"
    Say "     The source dropdown lists your FORK's branches. If a branch is missing,"
    Say "     the push in (b) did not land."
    Say ""
    Say "  d) Paste the title and the paragraph below into each PR."
    Say ""
    foreach ($m in $made) {
        Say ("  === " + $m.Branch + " ===") 'White'
        Say ("  Title: " + $m.Title) 'White'
        Say ("  " + $m.Why)
        Say ""
    }
    Say "  Branches created locally:" 'Green'
    foreach ($m in $made) { Say ("    " + $m.Branch) 'Green' }
    Say ""
    Say "  Suggested order: pr-a first (one file, unblocks EL0 user space), then pr-b"
    Say "  (DRM), then pr-c/pr-d.  pr-e adds data structures only; it needs the call"
    Say "  wiring before it compiles as a feature, so submit it after reviewing."
}
finally {
    Pop-Location
}
