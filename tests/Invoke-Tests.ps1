#Requires -Version 5.1

<#
.SYNOPSIS
    Test runner script for SecureProfileBackup integration tests.

.DESCRIPTION
    Orchestrates the execution of Pester tests for the Backup-UserProfile function.
    Handles test data generation, Pester module verification, and test execution.

.PARAMETER TestType
    The type of tests to run.
    - All: Run all tests (default)
    - Integration: Run only integration tests
    - Unit: Run only unit tests (when available)

.PARAMETER GenerateTestData
    When specified, regenerates test data before running tests.

.PARAMETER IncludeEdgeCases
    When specified, includes edge case test data.

.PARAMETER Verbosity
    Pester output verbosity level.
    - Normal: Standard output (default)
    - Detailed: Detailed output
    - Diagnostic: Full diagnostic output

.PARAMETER OutputPath
    Path where test results will be saved.
    Default: './output/TestResults'

.PARAMETER PassThru
    When specified, returns the Pester result object.

.EXAMPLE
    .\Invoke-Tests.ps1

    Runs all tests with default settings.

.EXAMPLE
    .\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases -Verbosity Detailed

    Regenerates test data with edge cases and runs tests with detailed output.

.EXAMPLE
    .\Invoke-Tests.ps1 -TestType Integration -PassThru

    Runs integration tests and returns the result object.

.OUTPUTS
    If -PassThru is specified, returns Pester result object.
    Otherwise, outputs test results to console.

.NOTES
    Author: SecureProfileBackup Test Framework
    Version: 1.0.0
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('All', 'Integration', 'Unit')]
    [string]$TestType = 'All',

    [Parameter()]
    [switch]$GenerateTestData,

    [Parameter()]
    [switch]$IncludeEdgeCases,

    [Parameter()]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Verbosity = 'Normal',

    [Parameter()]
    [string]$OutputPath = './output/TestResults',

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Script Variables
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:TestsPath = $PSScriptRoot
$script:OutputBasePath = Join-Path -Path $script:ProjectRoot -ChildPath 'output'
$script:TestProfilesPath = Join-Path -Path $script:OutputBasePath -ChildPath 'TestProfiles'
$script:TestResultsPath = Join-Path -Path $script:OutputBasePath -ChildPath 'TestResults'
$script:HelpersPath = Join-Path -Path $script:TestsPath -ChildPath 'helpers'
#endregion

#region Helper Functions

function Test-PesterModule {
    <#
    .SYNOPSIS
        Verifies Pester module is installed and meets version requirements.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $requiredVersion = [Version]'5.0.0'

    $pester = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $pester) {
        Write-Warning "Pester module is not installed."
        Write-Host "Install Pester with: Install-Module -Name Pester -Force -SkipPublisherCheck" -ForegroundColor Yellow
        return $false
    }

    if ($pester.Version -lt $requiredVersion) {
        Write-Warning "Pester version $($pester.Version) is installed, but version $requiredVersion or higher is required."
        Write-Host "Update Pester with: Update-Module -Name Pester -Force" -ForegroundColor Yellow
        return $false
    }

    Write-Verbose "Pester version $($pester.Version) found."
    return $true
}

function Initialize-TestData {
    <#
    .SYNOPSIS
        Generates test data for integration tests.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeEdgeCases,

        [Parameter()]
        [switch]$Force
    )

    $testDataGenerator = Join-Path -Path $script:HelpersPath -ChildPath 'New-TestProfiles.ps1'

    if (-not (Test-Path -Path $testDataGenerator)) {
        throw "Test data generator not found at: $testDataGenerator"
    }

    $shouldGenerate = $Force -or (-not (Test-Path -Path $script:TestProfilesPath))

    if ($shouldGenerate) {
        Write-Host "`n=== Generating Test Data ===" -ForegroundColor Cyan

        $params = @{
            OutputPath   = $script:TestProfilesPath
            ProfileCount = 3
            CleanExisting = $true
            Verbose      = $true
        }

        if ($IncludeEdgeCases) {
            $params['IncludeEdgeCases'] = $true
        }

        $results = & $testDataGenerator @params

        Write-Host "`nTest Data Summary:" -ForegroundColor Green
        Write-Host "  Profiles created: $($results.Count)"
        Write-Host "  Total files: $(($results | Measure-Object -Property FileCount -Sum).Sum)"
        Write-Host "  Total size: $('{0:N2}' -f ($results | Measure-Object -Property TotalSizeKB -Sum).Sum) KB"
        Write-Host ""

        return $results
    } else {
        Write-Verbose "Test data already exists at: $script:TestProfilesPath"
        return $null
    }
}

function Initialize-TestResultsDirectory {
    <#
    .SYNOPSIS
        Creates the test results directory if it doesn't exist.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $script:TestResultsPath)) {
        New-Item -Path $script:TestResultsPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created test results directory: $script:TestResultsPath"
    }
}

#endregion

#region Main Execution

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  SecureProfileBackup Test Runner" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify Pester module
Write-Host "Checking Pester module..." -ForegroundColor Yellow
if (-not (Test-PesterModule)) {
    Write-Error "Pester module check failed. Please install or update Pester."
    exit 1
}
Write-Host "  Pester module OK" -ForegroundColor Green

# Generate test data if requested or needed
if ($GenerateTestData -or (-not (Test-Path -Path $script:TestProfilesPath))) {
    $testDataParams = @{}
    if ($IncludeEdgeCases) {
        $testDataParams['IncludeEdgeCases'] = $true
    }
    if ($GenerateTestData) {
        $testDataParams['Force'] = $true
    }
    Initialize-TestData @testDataParams
} else {
    Write-Host "Using existing test data at: $script:TestProfilesPath" -ForegroundColor Yellow
}

# Ensure test results directory exists
Initialize-TestResultsDirectory

# Build Pester configuration
Write-Host "`n=== Running Tests ===" -ForegroundColor Cyan

$pesterConfig = New-PesterConfiguration

# Set run path based on test type
switch ($TestType) {
    'Integration' {
        $pesterConfig.Run.Path = Join-Path -Path $script:TestsPath -ChildPath 'Integration'
        $pesterConfig.Filter.Tag = @('Integration')
    }
    'Unit' {
        $pesterConfig.Run.Path = Join-Path -Path $script:TestsPath -ChildPath 'Unit'
        $pesterConfig.Filter.Tag = @('Unit')
    }
    default {
        $pesterConfig.Run.Path = $script:TestsPath
    }
}

# Configure output
$pesterConfig.Output.Verbosity = $Verbosity

# Configure test results
$testResultFile = Join-Path -Path $script:TestResultsPath -ChildPath "TestResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
$pesterConfig.TestResult.Enabled = $true
$pesterConfig.TestResult.OutputPath = $testResultFile
$pesterConfig.TestResult.OutputFormat = 'NUnitXml'

# Configure code coverage (optional)
$pesterConfig.CodeCoverage.Enabled = $false

# Run tests
Write-Host "Test Type: $TestType" -ForegroundColor White
Write-Host "Test Path: $($pesterConfig.Run.Path.Value)" -ForegroundColor White
Write-Host "Verbosity: $Verbosity" -ForegroundColor White
Write-Host ""

$pesterConfig.Run.PassThru = $true
$results = Invoke-Pester -Configuration $pesterConfig

# Display summary
Write-Host "`n=== Test Results Summary ===" -ForegroundColor Cyan
Write-Host "  Passed:   $($results.PassedCount)" -ForegroundColor Green
Write-Host "  Failed:   $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Skipped:  $($results.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Total:    $($results.TotalCount)" -ForegroundColor White
Write-Host "  Duration: $($results.Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor White
Write-Host ""
Write-Host "Test results saved to: $testResultFile" -ForegroundColor Gray

# Exit with appropriate code
if ($results.FailedCount -gt 0) {
    Write-Host "`nSome tests failed!" -ForegroundColor Red
    if ($PassThru) {
        return $results
    }
    exit 1
} else {
    Write-Host "`nAll tests passed!" -ForegroundColor Green
    if ($PassThru) {
        return $results
    }
    exit 0
}

#endregion