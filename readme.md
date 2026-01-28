# SecureProfileBackup

**User Profile Backup Utility for Windows Enterprise Environments**

SecureProfileBackup is a PowerShell-based utility that automates the backup of user profile directories with proper NTFS permission configuration. It supports both mirror (robocopy) and compression (ZIP) backup modes, making it ideal for hardware refresh cycles, domain migrations, profile recovery, and disaster recovery scenarios.

## Features

- **Dual Backup Modes**: Mirror directories using robocopy or create compressed ZIP archives
- **NTFS Permission Management**: Automatic configuration of security principals with proper access rights
- **Security Isolation**: Disables inheritance and removes BUILTIN\Users access to protect sensitive data
- **Pattern-Based Selection**: Flexible regex patterns to select specific profiles for backup
- **ACL Replication**: Preserves profile owner permissions from source to backup
- **SID-Based Access Control**: Grant access to additional security principals via SID
- **Dry-Run Support**: Preview operations with `-WhatIf` before execution
- **Compression Options**: Multiple compression levels (Optimal, Fastest, NoCompression)
- **File Exclusion**: Exclude files by pattern (e.g., `ntuser*` excluded by default)
- **Hidden File Support**: Includes hidden files in ZIP archives using .NET ZipArchive class
- **Comprehensive Logging**: Verbose output for troubleshooting and audit trails
- **Detailed Results**: Returns structured objects with backup status and details

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| PowerShell | 5.1+ | Windows PowerShell or PowerShell 7+ |
| Windows | 10/11/Server 2016+ | NTFS file system required |
| Privileges | Administrator | Required for NTFS permission management |
| NTFSSecurity Module | Latest | See installation instructions below |

## Installation

### 1. Clone or Download the Project

```powershell
git clone https://github.com/yourusername/SecureProfileBackup.git
cd SecureProfileBackup
```

### 2. Install the NTFSSecurity Module

The script requires the NTFSSecurity module for NTFS permission management.

**Option A: Install from PowerShell Gallery (Recommended)**

```powershell
Install-Module -Name NTFSSecurity -Scope CurrentUser -Force
```

**Option B: Use a local copy**

If you have the module locally, specify the path using the `-NTFSSecurityModulePath` parameter.

### 3. Verify Installation

```powershell
# Check NTFSSecurity module is available
Get-Module -Name NTFSSecurity -ListAvailable

# Verify robocopy is available (built into Windows)
Get-Command robocopy.exe
```

## Usage

### Basic Usage

```powershell
# Run with default settings (Mirror mode)
.\source\Backup-UserProfile.ps1

# Run with verbose output
.\source\Backup-UserProfile.ps1 -Verbose

# Preview changes without executing (dry run)
.\source\Backup-UserProfile.ps1 -WhatIf
```

### Mirror Mode (Default)

Uses robocopy to mirror directories, preserving file attributes and timestamps.

```powershell
# Mirror profiles from C:\Users to T:\ProfilesBackup
.\source\Backup-UserProfile.ps1 -BackupMode Mirror -Verbose

# Custom source and target paths
.\source\Backup-UserProfile.ps1 -SourcePath 'D:\Users' -TargetPath 'E:\Backup'
```

### Compress Mode

Creates ZIP archives of each profile for portable, space-efficient backups.

```powershell
# Create ZIP archives with optimal compression
.\source\Backup-UserProfile.ps1 -BackupMode Compress -Verbose

# Fast compression (larger files, faster processing)
.\source\Backup-UserProfile.ps1 -BackupMode Compress -CompressionLevel Fastest

# No compression (store only, fastest)
.\source\Backup-UserProfile.ps1 -BackupMode Compress -CompressionLevel NoCompression

# Custom file exclusions (applies to both modes)
.\source\Backup-UserProfile.ps1 -ExcludePatterns @('ntuser*', '*.tmp', 'Thumbs.db')

# No exclusions (may error on locked files)
.\source\Backup-UserProfile.ps1 -ExcludePatterns @()
```

### Advanced Options

```powershell
# Custom profile pattern (backup only profiles matching pattern)
.\source\Backup-UserProfile.ps1 -ProfilePattern '^\d{5}$'  # 5-digit profiles only

# Add additional SIDs with FullControl access
.\source\Backup-UserProfile.ps1 -AdditionalSids @('S-1-5-21-123456789-987654321-111111111-1234')

# Custom SID filter for ACL replication
.\source\Backup-UserProfile.ps1 -SidFilterPattern 'S-1-5-21-YOURDOMAIN*'

# Specify NTFSSecurity module path
.\source\Backup-UserProfile.ps1 -NTFSSecurityModulePath 'C:\Modules\NTFSSecurity\NTFSSecurity.psd1'
```

### Complete Example

```powershell
.\source\Backup-UserProfile.ps1 `
    -BackupMode Compress `
    -SourcePath 'C:\Users' `
    -TargetPath 'D:\ProfileBackups' `
    -ProfilePattern '^\d+$' `
    -AdditionalSids @('S-1-5-21-1230772385-5638642905-859402768-99') `
    -CompressionLevel Optimal `
    -NTFSSecurityModulePath 'C:\Modules\NTFSSecurity\NTFSSecurity.psd1' `
    -Verbose
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `SourcePath` | String | `C:\Users` | Source directory containing user profiles |
| `TargetPath` | String | `T:\ProfilesBackup` | Target directory for backups |
| `BackupMode` | String | `Mirror` | Backup method: `Mirror` or `Compress` |
| `ProfilePattern` | String | `^\d+$` | Regex pattern to match profile directory names |
| `AdditionalSids` | String[] | *(see script)* | SIDs to grant FullControl access |
| `SidFilterPattern` | String | `S-1-5-21-1230*` | Pattern to filter ACL entries for replication |
| `NTFSSecurityModulePath` | String | `.\NTFSSecurity\NTFSSecurity.psd1` | Path to NTFSSecurity module |
| `CompressionLevel` | String | `Optimal` | ZIP compression level (Compress mode only) |
| `ExcludePatterns` | String[] | `@('ntuser*')` | File patterns to exclude from backup (both modes) |

## Output

The script returns an array of `PSCustomObject` with the following properties:

| Property | Description |
|----------|-------------|
| `ProfileName` | Name of the profile directory |
| `SourcePath` | Full path to source profile |
| `DestinationPath` | Full path to backup location (folder or ZIP) |
| `BackupMode` | Backup mode used (Mirror or Compress) |
| `Status` | Result status: `Success`, `Failed`, or `Skipped` |
| `RobocopyExitCode` | Robocopy exit code (Mirror mode only) |
| `CompressedSize` | Size in bytes of ZIP archive (Compress mode only) |
| `Error` | Error message if backup failed |

### Example Output

```powershell
$results = .\source\Backup-UserProfile.ps1 -BackupMode Compress -Verbose
$results | Format-Table -AutoSize

# ProfileName SourcePath           DestinationPath                 BackupMode Status  CompressedSize
# ----------- ----------           ---------------                 ---------- ------  --------------
# 10000       C:\Users\10000       T:\ProfilesBackup\10000.zip     Compress   Success      15728640
# 10001       C:\Users\10001       T:\ProfilesBackup\10001.zip     Compress   Success       8945664
# 10002       C:\Users\10002       T:\ProfilesBackup\10002.zip     Compress   Success      12582912
```

## NTFS Permissions Applied

Both backup modes configure the following NTFS permissions on backup files/folders:

| Principal | Access Level |
|-----------|--------------|
| Administrators | FullControl |
| NT AUTHORITY\SYSTEM | FullControl |
| Profile Owner (replicated from source) | FullControl |
| Additional SIDs (if specified) | FullControl |
| BUILTIN\Users | **NO ACCESS** |

**Security Features:**

- Inheritance is disabled on all backups
- Inherited ACEs are removed to prevent permission leakage
- Only explicitly granted principals can access backup content

## Directory Structure

```text
SecureProfileBackup/
├── readme.md                    # This file
├── .gitignore                   # Git ignore patterns
├── source/
│   └── Backup-UserProfile.ps1   # Main backup script
├── tests/
│   ├── README.md                # Test documentation
│   ├── Invoke-Tests.ps1         # Test runner script
│   ├── helpers/
│   │   └── New-TestProfiles.ps1 # Test data generator
│   └── Integration/
│       └── Backup-UserProfile.Integration.Tests.ps1
├── output/                      # Generated test data and results
└── memory-bank/                 # Project documentation
    ├── projectbrief.md
    ├── productContext.md
    ├── techContext.md
    ├── systemPatterns.md
    ├── progress.md
    ├── activeContext.md
    └── promptHistory.md
```

## Testing

The project includes a comprehensive test suite using Pester 5.0+.

### Running Tests

```powershell
# Navigate to tests directory
cd tests

# Run all tests
.\Invoke-Tests.ps1

# Generate test data and run tests
.\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases

# Run with detailed output
.\Invoke-Tests.ps1 -Verbosity Detailed
```

### Generating Test Data

```powershell
# Create test profiles
.\tests\helpers\New-TestProfiles.ps1 -OutputPath .\output\ -Verbose

# Include edge cases (empty dirs, special chars, deep nesting, etc.)
.\tests\helpers\New-TestProfiles.ps1 -OutputPath .\output\ -IncludeEdgeCases -Verbose
```

For more details, see the [Test Suite Documentation](tests/README.md).

## Robocopy Exit Codes

When using Mirror mode, the script reports robocopy exit codes:

| Exit Code | Meaning |
|-----------|---------|
| 0 | No files copied, no errors |
| 1 | Files copied successfully |
| 2 | Extra files or directories detected |
| 3 | Some files copied, extra files detected |
| 4 | Mismatched files or directories |
| 5 | Some files copied, some mismatched |
| 6 | Additional files and mismatched present |
| 7 | Files copied, extras and mismatches present |
| 8+ | **Error** - Copy failures occurred |

Exit codes 0-7 are considered success; 8+ indicate errors.

## Troubleshooting

### "NTFSSecurity module not found"

Ensure the module is installed and the path is correct:

```powershell
# Check if module is installed
Get-Module -Name NTFSSecurity -ListAvailable

# Install if missing
Install-Module -Name NTFSSecurity -Scope CurrentUser -Force
```

### "Access Denied" errors

- Ensure you're running PowerShell as Administrator
- Verify you have read access to the source profiles
- Check that the target drive supports NTFS

### Long Path Errors

Enable long path support on Windows 10 1607+:

```powershell
# Run as Administrator
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
```

### Empty profiles are skipped in Compress mode

This is expected behavior. Empty directories cannot be compressed into ZIP archives and are reported with `Status = 'Skipped'`.

### Files like ntuser.dat are not backed up

By default, the script excludes files matching `ntuser*` pattern (ntuser.dat, ntuser.dat.LOG1, etc.) because these files are typically locked by Windows. To include them (may cause errors on locked files):

```powershell
.\source\Backup-UserProfile.ps1 -ExcludePatterns @()
```

## Use Cases

- **Hardware Refresh**: Backup profiles before reimaging workstations
- **Domain Migration**: Preserve profiles when migrating between domains
- **Profile Corruption Recovery**: Maintain backup copies for restoration
- **Disaster Recovery**: Regular backups for business continuity
- **User Offboarding**: Archive departed user data with proper security
- **Compliance**: Auditable backup operations with permission documentation

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is provided as-is for enterprise use. See LICENSE file for details.

## Related Resources

- [NTFSSecurity Module](https://github.com/raandree/NTFSSecurity) - NTFS permission management
- [Robocopy Documentation](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy) - Microsoft robocopy reference
- [Pester Testing Framework](https://pester.dev/) - PowerShell testing framework

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.2.0 | Current | Added `-ExcludePatterns` parameter for both modes, default excludes `ntuser*` |
| 3.1.0 | - | Dual backup modes (Mirror/Compress), hidden file support, enhanced security |
| 3.0.0 | - | Added compression mode with ZIP archive support |
| 2.0.0 | - | Added NTFS permission management |
| 1.0.0 | - | Initial release with robocopy mirror |
