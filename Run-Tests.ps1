param(
    [switch]$EnableExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$testPath = Join-Path $projectRoot "tests"

$pesterModule = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $pesterModule) {
    throw "Pester is required to run ReadRite tests. Install it with: Install-Module Pester -Scope CurrentUser -Force"
}

Import-Module $pesterModule.Path -Force
$pesterVersion = (Get-Module Pester).Version
Write-Host "Running ReadRite tests with Pester $pesterVersion"

if ($pesterVersion.Major -ge 5) {
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $testPath
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = "Detailed"
    $result = Invoke-Pester -Configuration $configuration
}
else {
    $result = Invoke-Pester -Script $testPath -PassThru
}

if ($EnableExit) {
    if ($result.FailedCount -gt 0) {
        exit 1
    }

    exit 0
}
