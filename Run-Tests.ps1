param(
    [switch]$EnableExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$testPath = Join-Path $projectRoot "tests"

$pesterModule = Get-Module -ListAvailable Pester |
    Where-Object { $_.Version.Major -lt 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $pesterModule) {
    throw "ReadRite tests require Pester 3.x or 4.x. Install it with: Install-Module Pester -RequiredVersion 3.4.0 -Scope CurrentUser -Force"
}

Import-Module $pesterModule.Path -Force
$pesterVersion = (Get-Module Pester).Version
Write-Host "Running ReadRite tests with Pester $pesterVersion"

$result = Invoke-Pester -Script $testPath -PassThru

if ($EnableExit) {
    if ($result.FailedCount -gt 0) {
        exit 1
    }

    exit 0
}
