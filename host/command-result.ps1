# Command completion must come from the actual marker output, never silence.
function Get-GuestCommandResult {
    param([string]$Transcript, [string]$Nonce)
    $clean = [regex]::Replace($Transcript, '\x1b\[[0-9;?]*[a-zA-Z]', '')
    $pattern = '(?m)^__' + [regex]::Escape($Nonce) + '__rc=(\d+)\r?$'
    $match = [regex]::Match($clean, $pattern)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups[1].Value
}
