param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Args = @($Args)

Import-Module (Join-Path $PSScriptRoot "MinimalNotes.psm1") -Force -ErrorAction Stop

try {
    Invoke-MinimalNotesCli -Command $Command -Arguments $Args
} catch {
    Write-Error $_
    exit 1
}
