$pesterModule = Get-Module -ListAvailable Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pesterModule -or $pesterModule.Version.Major -lt 5) {
    throw "Pester 5 or later is required. Install it with: Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck"
}

Import-Module Pester -MinimumVersion 5.0 -Force -ErrorAction Stop

$testPath = Join-Path $PSScriptRoot "tests"
$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.TestRegistry.Enabled = $false

Invoke-Pester -Configuration $config
