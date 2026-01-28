# SecureProfileBackup Test Suite

This directory contains the test framework for the SecureProfileBackup Backup-UserProfile function.

## Directory Structure

```text
tests/
├── README.md                           # This file
├── Invoke-Tests.ps1                    # Test runner script
├── helpers/
│   └── New-TestProfiles.ps1           # Test data generator
└── Integration/
    └── Backup-UserProfile.Integration.Tests.ps1  # Integration tests
```

## Prerequisites

- PowerShell 5.1 or later
- Pester 5.0.0 or later

### Installing Pester

```powershell
# Install Pester (if not already installed)
Install-Module -Name Pester -Force -SkipPublisherCheck

# Or update existing installation
Update-Module -Name Pester -Force
```

## Running Tests

### Quick Start

Run all tests with default settings:

```powershell
cd tests
.\Invoke-Tests.ps1
```

### Generate Fresh Test Data

Regenerate test profiles before running tests:

```powershell
.\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases
```

### Run Specific Test Types

```powershell
# Run only integration tests
.\Invoke-Tests.ps1 -TestType Integration

# Run with detailed output
.\Invoke-Tests.ps1 -Verbosity Detailed

# Run with diagnostic output (most verbose)
.\Invoke-Tests.ps1 -Verbosity Diagnostic
```

### Get Test Results Object

```powershell
$results = .\Invoke-Tests.ps1 -PassThru
$results.PassedCount
$results.FailedCount
```

## Test Data Generation

The test data generator creates dummy user profiles for testing:

### Direct Usage

```powershell
# Generate default test profiles
.\helpers\New-TestProfiles.ps1 -Verbose

# Generate with edge cases
.\helpers\New-TestProfiles.ps1 -IncludeEdgeCases -Verbose

# Custom configuration
.\helpers\New-TestProfiles.ps1 -ProfileCount 10 -FileSizeKB 50 -CleanExisting
```

### Generated Profiles

**Standard Profiles** (Default: 5 profiles)

- Numeric names matching pattern `^\d+$` (e.g., 10000, 10001, 10002)
- Standard Windows profile structure:
  - Desktop, Documents, Downloads, Pictures, Music, Videos
  - AppData (Local, Roaming, LocalLow)
- Sample files in each directory

**Edge Case Profiles** (Optional with `-IncludeEdgeCases`)

| Profile | Type | Description |
|---------|------|-------------|
| 99991 | Empty | Empty directory |
| 99992 | SpecialChars | Files with spaces, dashes, dots |
| 99993 | DeepNested | 15 levels of directory nesting |
| 99994 | LargeFiles | Files up to 1MB |
| 99995 | ManyFiles | 100 small files |
| 99996 | ReadOnly | Files with read-only attribute |

## Test Coverage

### Integration Tests

The integration tests cover:

#### Parameter Validation

- Default parameter values
- ValidateScript for SourcePath
- SupportsShouldProcess (WhatIf, Confirm)

#### Mirror Mode Backup

- Profile discovery matching pattern
- WhatIf execution (no changes)
- Directory creation for each profile
- Robocopy execution and exit codes
- Result object properties
- Success status reporting

#### Compress Mode Backup

- ZIP archive creation
- Compressed size reporting
- Compression level support (Optimal, Fastest, NoCompression)
- Archive overwrite behavior

#### Edge Case Handling

- Empty profile directories
- Special characters in filenames
- Deeply nested directories (15 levels)
- Profiles with many files (100+)

#### Profile Pattern Matching

- Custom regex pattern support
- Non-matching pattern handling

#### Error Handling

- Missing NTFSSecurity module
- Target directory creation

#### Performance Tests

- Execution time validation

## Test Results

Test results are saved to:

```text
output/TestResults/TestResults_YYYYMMDD_HHmmss.xml
```

Results are in NUnit XML format, compatible with CI/CD systems.

## Mock NTFSSecurity Module

The integration tests create a mock NTFSSecurity module to allow testing without:

- Administrator privileges
- The actual NTFSSecurity module installed

The mock module provides:

- `Add-NTFSAccess` - Logs access changes
- `Get-NTFSAccess` - Returns mock ACL entries
- `Disable-NTFSAccessInheritance` - Logs inheritance changes

## Writing New Tests

### Test File Location

- **Integration tests**: `tests/Integration/*.Tests.ps1`
- **Unit tests**: `tests/Unit/*.Tests.ps1` (future)

### Test File Naming

Follow Pester conventions:

```text
<FunctionName>.<TestType>.Tests.ps1
```

### Test Structure Example

```powershell
#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    # Setup paths and discovery-time logic
}

BeforeAll {
    # Import modules and functions
    # Setup test fixtures
}

AfterAll {
    # Cleanup test artifacts
}

Describe 'Function-Name' -Tag 'Integration' {
    Context 'When condition' {
        It 'Should do something' {
            # Arrange
            # Act
            # Assert
        }
    }
}
```

## Troubleshooting

### Tests Fail with "Pester module not found"

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
```

### Tests Fail with "Test data not found"

```powershell
.\Invoke-Tests.ps1 -GenerateTestData
```

### Permission Errors

The integration tests are designed to run without administrator privileges by using a mock NTFSSecurity module. If you encounter permission errors:

1. Ensure you're running from the `tests` directory
2. Check that `output` folder exists and is writable
3. Try running with `-GenerateTestData -CleanExisting`

### Long Path Errors

Windows has a 260-character path limit by default. The deeply nested edge case (99993) may cause issues on systems without long path support enabled.

To enable long paths (Windows 10 1607+):

```powershell
# Run as Administrator
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
```

## CI/CD Integration

### Azure Pipelines Example

```yaml
- task: PowerShell@2
  displayName: 'Run Pester Tests'
  inputs:
    targetType: 'inline'
    script: |
      Set-Location tests
      .\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases -Verbosity Detailed
    pwsh: false

- task: PublishTestResults@2
  displayName: 'Publish Test Results'
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/TestResults_*.xml'
    failTaskOnFailedTests: true
```

### GitHub Actions Example

```yaml
- name: Run Tests
  shell: pwsh
  run: |
    Set-Location tests
    .\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: output/TestResults/*.xml