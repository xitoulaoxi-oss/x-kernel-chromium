# One mapping from a local helper name to the path the guest actually has.
# A hand-written -Key command once used /tmp/xk-targets.sh while the upload
# landed at /tmp/xk-xk-targets.sh, so all callers and tests share this function.
function Get-GuestRemotePath {
    param([string]$Path)
    $leaf = Split-Path -Leaf ([System.IO.Path]::GetFullPath($Path))
    return "/tmp/xk-$leaf"
}
