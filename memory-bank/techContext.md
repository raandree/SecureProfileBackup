# SecureProfileBackup - Technology Context

## Technology Stack

### Core Technologies

| Technology | Version | Purpose |
|------------|---------|---------|
| PowerShell | 5.1+ | Scripting runtime |
| Windows | 10/11/Server 2016+ | Target platform |
| robocopy | Built-in | File mirroring |
| NTFSSecurity | Latest | NTFS permission management |

### PowerShell Requirements

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator
```

**Note**: NTFSSecurity module can be loaded from a local path (`.\NTFSSecurity\NTFSSecurity.psd1`) or from system installation. The `-NTFSSecurityModulePath` parameter allows specifying the module location.

## Dependencies

### External Modules

#### NTFSSecurity
- **Purpose**: Simplified NTFS permission management
- **Location**: Bundled locally at `.\NTFSSecurity\NTFSSecurity.psd1`
- **Repository**: https://github.com/raandree/NTFSSecurity
- **Key Cmdlets Used**:
  - `Add-NTFSAccess` - Add ACEs to file/folder
  - `Get-NTFSAccess` - Read existing ACEs
  - `Disable-NTFSAccessInheritance` - Remove inheritance

**Installation** (if not bundled):
```powershell
Install-Module -Name NTFSSecurity -Scope CurrentUser
```

### Built-in Tools

#### robocopy
- **Purpose**: Robust file copy with mirroring
- **Flags Used**:
  - `/MIR` - Mirror mode (sync with deletions)
  - `/R:3` - Retry count
  - `/W:5` - Wait time between retries (seconds)
  - `/DCOPY:T` - Copy directory timestamps
  - `/NP` - No progress display
  - `/NDL` - No directory listing

## Development Setup

### Prerequisites
1. Windows PowerShell 5.1 or PowerShell 7+
2. Administrator privileges
3. NTFSSecurity module installed
4. Source and target paths accessible

### Installation Steps
```powershell
# 1. Clone or download project
git clone <repository-url>
cd SecureProfileBackup

# 2. Verify NTFSSecurity module is present
Test-Path '.\NTFSSecurity\NTFSSecurity.psd1'

# If module is not bundled, install it:
# Install-Module -Name NTFSSecurity -Scope CurrentUser -Force
```

### Running the Script
```powershell
# Default execution (requires Administrator)
.\source\Backup-UserProfile.ps1

# With verbose output
.\source\Backup-UserProfile.ps1 -Verbose

# Dry run (preview only)
.\source\Backup-UserProfile.ps1 -WhatIf

# Custom paths
.\source\Backup-UserProfile.ps1 -SourcePath 'D:\Users' -TargetPath 'E:\Backup'

# Compress mode with file exclusions
.\source\Backup-UserProfile.ps1 -BackupMode Compress -ExcludePatterns @('ntuser*', '*.tmp')
```

## Technical Constraints

### Platform Limitations
- Windows only (NTFS permissions are Windows-specific)
- Requires local Administrator or equivalent
- Target drive must support NTFS

### Performance Considerations
- Robocopy is more efficient than PowerShell native Copy-Item
- Large profiles may take significant time
- Network targets may require stable connection

### Security Considerations
- Script modifies file system permissions
- Requires elevated privileges
- SIDs must be valid in the domain context

## Coding Standards

### Applied Standards (from .clinerules)
- PowerShell best practices per `powershell.instructions.md`
- Approved verbs only
- CmdletBinding with ShouldProcess
- Complete comment-based help
- Proper error handling
- 4-space indentation
- No aliases in scripts

### PSScriptAnalyzer Compliance
Script designed to pass all critical PSScriptAnalyzer rules:
- ✅ PSAvoidUsingCmdletAliases
- ✅ PSUseDeclaredVarsMoreThanAssignments
- ✅ PSAvoidUsingPositionalParameters
- ✅ PSUseApprovedVerbs
- ✅ PSUseShouldProcessForStateChangingFunctions

## Tool Usage Patterns

### Robocopy Integration
```powershell
$robocopyArgs = @(
    $srcPath
    $destPath
    '/MIR'
    '/R:3'
    '/W:5'
    '/DCOPY:T'
    '/NP'
    '/NDL'
)

# Add file exclusion patterns if specified
if ($ExcludePatterns.Count -gt 0) {
    $robocopyArgs += '/XF'
    $robocopyArgs += $ExcludePatterns
}

$process = Start-Process -FilePath 'robocopy.exe' `
    -ArgumentList $robocopyArgs `
    -NoNewWindow -Wait -PassThru
```

### .NET ZipArchive Integration (Compress Mode)
```powershell
# Used instead of Compress-Archive to include hidden files and support exclusions
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$netCompressionLevel = switch ($CompressionLevel) {
    'Optimal' { [System.IO.Compression.CompressionLevel]::Optimal }
    'Fastest' { [System.IO.Compression.CompressionLevel]::Fastest }
    'NoCompression' { [System.IO.Compression.CompressionLevel]::NoCompression }
}

$zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
# Manual file iteration with exclusion pattern support
```

### NTFSSecurity Patterns
```powershell
# Splatting for repeated parameters
$params = @{
    Path         = $destPath
    AccessRights = 'FullControl'
}

Add-NTFSAccess @params -Account 'Administrators'
Add-NTFSAccess @params -Account 'NT Authority\SYSTEM'

# Disable inheritance
Disable-NTFSAccessInheritance -Path $destPath -RemoveInheritedAccessRules
```

## Testing Approach

### Automated Testing (Pester 5.x)
```powershell
# Run all tests
cd tests
.\Invoke-Tests.ps1

# Generate test data and run tests
.\Invoke-Tests.ps1 -GenerateTestData -IncludeEdgeCases

# Run with detailed output
.\Invoke-Tests.ps1 -Verbosity Detailed
```

### Manual Testing
```powershell
# 1. Test with WhatIf
.\source\Backup-UserProfile.ps1 -WhatIf -Verbose

# 2. Test single profile (modify pattern)
.\source\Backup-UserProfile.ps1 -ProfilePattern '^TestUser$' -Verbose

# 3. Verify permissions using NTFSSecurity
Get-NTFSAccess -Path 'T:\ProfilesBackup\<profile>'
Get-NTFSInheritance -Path 'T:\ProfilesBackup\<profile>'
```

### Validation Commands
```powershell
# Check robocopy availability
Get-Command robocopy.exe

# Verify NTFSSecurity module
Get-Module -Name NTFSSecurity -ListAvailable

# Test path access
Test-Path 'C:\Users'
Test-Path 'T:\ProfilesBackup'

# List hidden files in test profiles
Get-ChildItem -Path './output/TestProfiles/10000' -Recurse -Force -Attributes Hidden
