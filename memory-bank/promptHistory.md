# Prompt History

## 2026-01-28 - Configure NTFS Permissions on Backup Folder

### User Request
"The folder $TargetPath = 'T:\ProfilesBackup' has inheritance enabled by default. Please disable the inheritance, convert the inherited into explicit ACEs and remove authenticated users. Then add domain users for only read."

Followed by: "Please add the new code as a function to the backup script and call if after creating the folder 'ProfilesBackup'."

### Actions Taken
1. Created standalone `Set-FolderPermissions.ps1` script using NTFSSecurity module cmdlets:
   - `Disable-NTFSAccessInheritance` - Disables inheritance and converts inherited ACEs to explicit
   - `Get-NTFSAccess` + `Remove-NTFSAccess` - Removes Authenticated Users ACE
   - `Add-NTFSAccess` - Adds Domain Users with Read permissions applied to ThisFolderSubfoldersAndFiles

2. Integrated the functionality into `Backup-UserProfile.ps1`:
   - Added `Set-BackupFolderPermissions` function in new `#region Functions` section
   - Function accepts `Path` (mandatory) and `DomainUsersAccount` (default: 'YOURPROJECT\Domain Users') parameters
   - Called immediately after creating the target directory in the Initialization region
   - Respects `-Verbose` preference from parent script

### Key Implementation Details
```powershell
function Set-BackupFolderPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter()]
        [string]$DomainUsersAccount = 'YOURPROJECT\Domain Users'
    )

    # Step 1: Disable inheritance (converts inherited to explicit)
    Disable-NTFSAccessInheritance -Path $Path

    # Step 2: Remove Authenticated Users
    $authUsersAce = Get-NTFSAccess -Path $Path | Where-Object { $_.Account -like '*Authenticated Users*' }
    if ($authUsersAce) { $authUsersAce | Remove-NTFSAccess }

    # Step 3: Add Domain Users with Read
    Add-NTFSAccess -Path $Path -Account $DomainUsersAccount -AccessRights Read -AppliesTo ThisFolderSubfoldersAndFiles
}
```

### Integration Point
```powershell
if (-not (Test-Path -Path $TargetPath)) {
    if ($PSCmdlet.ShouldProcess($TargetPath, 'Create target directory')) {
        New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        Set-BackupFolderPermissions -Path $TargetPath -Verbose:$VerbosePreference
    }
}
```

### Files Modified
- `source/Backup-UserProfile.ps1` (v3.2.0 → v3.3.0)
- `memory-bank/promptHistory.md`

### Files Removed
- `Set-FolderPermissions.ps1` (standalone script replaced by integrated function)

---

## 2026-01-28 - Fix Hidden Files Missing from ZIP Archives

### User Request
"Now that we have hidden files and folders, we need to make sure they are part of the zip files. So far they are not and missing in the compressed backup."

### Issue
Hidden files and folders were not being included in ZIP archives when using Compress mode. PowerShell's `Compress-Archive` cmdlet does not include hidden files regardless of the approach used.

### Attempted Solutions

**Attempt 1: Using `-LiteralPath` with `Get-ChildItem -Force`**
```powershell
$itemsToCompress = @(Get-ChildItem -Path $srcPath -Force)
$compressParams = @{
    LiteralPath = $itemsToCompress.FullName
    ...
}
Compress-Archive @compressParams
```
**Result**: Failed - caused `Get-Item: Could not find item` errors for hidden files like `desktop.ini`.

**Attempt 2: Using wildcard path**
```powershell
$compressParams = @{
    Path = (Join-Path -Path $srcPath -ChildPath '*')
    ...
}
Compress-Archive @compressParams
```
**Result**: Failed - PowerShell's wildcard expansion excludes hidden files by default.

### Final Solution: .NET ZipFile Class
Replaced `Compress-Archive` with .NET's `System.IO.Compression.ZipFile` class which includes ALL files including hidden ones:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

$netCompressionLevel = switch ($CompressionLevel) {
    'Optimal'       { [System.IO.Compression.CompressionLevel]::Optimal }
    'Fastest'       { [System.IO.Compression.CompressionLevel]::Fastest }
    'NoCompression' { [System.IO.Compression.CompressionLevel]::NoCompression }
}

[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $srcPath,
    $destPath,
    $netCompressionLevel,
    $false  # includeBaseDirectory = false
)
```

### Why .NET ZipFile Works
- .NET's `ZipFile.CreateFromDirectory()` uses the file system directly and includes ALL files
- PowerShell's `Compress-Archive` uses path globbing which respects Windows file visibility settings
- The .NET method is also more efficient for large directories

### Files Modified
- `source/Backup-UserProfile.ps1` (v3.0.0 → v3.1.0)
- `memory-bank/promptHistory.md`

---

## 2026-01-28 - Add Hidden Files and Folders to Test Profiles

### User Request
"The script 'New-TestProfiles.ps1' creates test profiles. Test profiles have also some hidden folders and files. Please make sure some folders and files in the test profiles are hidden."

### Actions Taken
1. Read `New-TestProfiles.ps1` to understand current structure
2. Added hidden folders and files to standard profiles in `New-StandardProfileContent`:
   - Hidden directories: `AppData\Local\Microsoft\Windows\History`, `INetCache`, `Temporary Internet Files`, `.hidden_config`
   - Hidden files: `desktop.ini`, `AppData\Local\.cache`, `Documents\.hidden_notes.txt`
   - Each hidden directory contains a `data.dat` file
3. Added new `Hidden` edge case type to `New-EdgeCaseProfile`:
   - Added to `ValidateSet` parameter validation
   - Implemented comprehensive hidden content creation:
     - Hidden directories at various levels (`.hidden_root_folder`, `Documents\.hidden_docs`, etc.)
     - Both visible and hidden files inside hidden directories
     - Hidden files in visible directories (`.gitignore`, `.env`, `desktop.ini`, `.hidden_config.json`, `thumbs.db`)
     - Root-level hidden files (`.profile`, `.bashrc`, `.config`)
     - Visible files for comparison testing
4. Updated edge cases array to include `@{ Name = '99997'; Type = 'Hidden' }`
5. Updated `.PARAMETER IncludeEdgeCases` help to list all 7 edge case types

### Key Implementation Details
```powershell
# Setting hidden attribute on directories
$createdDir = New-Item -Path $path -ItemType Directory -Force
$createdDir.Attributes = $createdDir.Attributes -bor [System.IO.FileAttributes]::Hidden

# Setting hidden attribute on files
$fileItem = Get-Item -Path $path -Force
$fileItem.Attributes = $fileItem.Attributes -bor [System.IO.FileAttributes]::Hidden
```

### Files Modified
- `tests/helpers/New-TestProfiles.ps1` (v1.2.0 → v1.3.0)
- `memory-bank/activeContext.md`
- `memory-bank/promptHistory.md`

---

## 2026-01-28 - Add Random ACL to Test Profiles

### User Request
"The 'New-TestProfiles.ps1' script creates test profiles. A profile is for dedicated user and only that user has access to it. Please add a random ACL to each test profile with full control. This ACL entry must be added to the backup, either the zip file or the backup folder."

### Actions Taken
1. Read `New-TestProfiles.ps1` and `Backup-UserProfile.ps1` to understand current implementation
2. Added `NTFSSecurityModulePath` parameter to `New-TestProfiles.ps1`
3. Created `New-RandomProfileOwnerSid` function to generate domain-like SIDs (pattern: `S-1-5-21-RANDOM-RANDOM-RANDOM-RID`)
4. Created `Set-ProfileOwnerAcl` function to apply FullControl permission via NTFSSecurity module
5. Updated main execution to:
   - Import NTFSSecurity module (with graceful fallback if not available)
   - Apply random ACL to each standard profile
   - Apply random ACL to each edge case profile
   - Report `OwnerSid` and `AclApplied` in result objects
6. Updated integration tests:
   - Enhanced mock module to store and return profile owner SIDs
   - Added tests for ACL replication with wildcard `SidFilterPattern` (`S-1-5-21-*`)
   - Added dedicated "Profile Owner ACL Replication" context for Mirror and Compress modes

### Key Implementation Details
- Random SIDs use format `S-1-5-21-RANDOM-RANDOM-RANDOM-RID` where RID is the profile name (for traceability)
- ACL replication in backup uses existing `SidFilterPattern` parameter
- Default `SidFilterPattern` (`S-1-5-21-1230*`) doesn't match random SIDs
- Tests use `-SidFilterPattern 'S-1-5-21-*'` to match all domain-like SIDs

### Files Modified
- `tests/helpers/New-TestProfiles.ps1` (v1.0.0 → v1.2.0)
- `tests/Integration/Backup-UserProfile.Integration.Tests.ps1`
- `memory-bank/activeContext.md`
- `memory-bank/promptHistory.md`

---

## 2026-01-28 - Convert Backup-UserProfile from Function to Script

### User Request
"change the Backup-UserProfile.ps1 to a script and move the function's content to the script level"

### Actions Taken
1. Converted `source/Backup-UserProfile.ps1` from function to standalone script:
   - Removed `function Backup-UserProfile { ... }` wrapper
   - Moved all parameters to script-level `param()` block
   - Replaced `begin/process/end` blocks with `#region` sections
   - Script now executes immediately when invoked (no dot-sourcing required)
   - Updated version to 3.0.0

2. Updated integration tests for script invocation:
   - Created `Invoke-BackupUserProfile` wrapper function that calls script with parameters
   - Added alias `Backup-UserProfile` for backward compatibility with existing tests
   - All existing tests continue to work without modification

### Key Implementation Details
- Script uses `#region Initialization`, `#region Main Processing`, `#region Summary and Output`
- `$PSCmdlet.ShouldProcess()` works correctly in script context
- All parameters remain the same with identical defaults

### Files Modified
- `source/Backup-UserProfile.ps1` (v2.3.0 → v3.0.0)
- `tests/Integration/Backup-UserProfile.Integration.Tests.ps1` (v1.0.0 → v2.0.0)
- `memory-bank/activeContext.md`
- `memory-bank/promptHistory.md`

---

## 2026-01-27 - Testing Infrastructure Implementation

### User Request
"Now we need to take care of testing the script. For this we need integration tests and for these tests we need test data. Please start with a script that generates test data, some dummy profiles with some files inside. The Pester integration tests should be in the folder 'tests', the test data should be generated in the folder `output` and this folder should be ignored by git."

### Actions Taken
1. Created `.gitignore` to exclude `output/` folder
2. Created test folder structure:
   - `tests/`
   - `tests/Integration/`
   - `tests/helpers/`
3. Created test data generator (`tests/helpers/New-TestProfiles.ps1`):
   - Generates configurable number of test profiles
   - Creates realistic folder structures (Desktop, Documents, Downloads, etc.)
   - Includes edge case profiles (empty, special characters, deep nesting, large files, many files, unicode)
4. Created Pester integration tests (`tests/Integration/Backup-UserProfile.Integration.Tests.ps1`):
   - 23 comprehensive test cases
   - Tests for both Mirror and Compress modes
   - Parameter validation tests
   - Edge case handling tests
   - Performance tests
5. Created test runner script (`tests/Invoke-Tests.ps1`)
6. Created tests README documentation (`tests/README.md`)

### Issues Encountered & Resolved
1. **Pester 5.x Variable Scoping**: Variables in `BeforeDiscovery` not available in `BeforeAll` - moved path setup to `BeforeAll`
2. **Null/Single Object `.Count`**: Pipeline results could be null or single objects - added `@()` array subexpression
3. **Test Results Path**: Path concatenation issue - fixed variable naming
4. **ValidateSet Attribute Access**: Changed from `.Attributes.ValidValues` to proper type filtering

### Current Status
- Test framework: **Functional**
- Tests passing: **11/23**
- Tests failing: **12/23** (edge cases needing refinement)

### Files Created
- `.gitignore`
- `tests/README.md`
- `tests/Invoke-Tests.ps1`
- `tests/Integration/Backup-UserProfile.Integration.Tests.ps1`
- `tests/helpers/New-TestProfiles.ps1`

### Files Modified
- `source/Backup-UserProfile.ps1` (array handling fix)
- `memory-bank/progress.md`
- `memory-bank/activeContext.md`
- `memory-bank/promptHistory.md`