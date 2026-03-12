Import-Module Pester -ErrorAction Stop

$testPath = Join-Path $PSScriptRoot "tests"
Invoke-Pester -Path $testPath
