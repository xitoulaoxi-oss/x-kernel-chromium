function Resolve-StagingInputs {
    param([string]$Root, [string[]]$ManifestPaths, [string]$Scripts, [string]$Uploads)
    $paths = @($ManifestPaths) + @($Scripts -split ';') + @($Uploads -split ';')
    $seen = @{}
    foreach ($path in $paths) {
        if (-not $path -or -not $path.Trim()) { continue }
        $path = $path.Trim()
        $full = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $Root $path }
        $full = [System.IO.Path]::GetFullPath($full)
        if (-not (Test-Path -LiteralPath $full)) { throw "Staging input missing: $full" }
        $item = Get-Item -LiteralPath $full
        if ($item.Extension -eq '.sh' -and [System.IO.File]::ReadAllText($full).Contains("`r")) {
            throw "Guest shell script must use LF line endings: $full"
        }
        $key = $item.Name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            if ($seen[$key] -ne $full) { throw "Staging basename collision: $key" }
            continue
        }
        $seen[$key] = $full
        $full
    }
}
