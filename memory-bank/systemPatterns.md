# SecureProfileBackup - System Patterns

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup-UserProfile.ps1                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌────────────────┐  ┌─────────────────┐  │
│  │ INITIALIZE  │─▶│ MAIN PROCESS   │─▶│ SUMMARY/OUTPUT  │  │
│  │   Region    │  │    Region      │  │     Region      │  │
│  └─────────────┘  └────────────────┘  └─────────────────┘  │
│        │                 │                    │             │
│        ▼                 ▼                    ▼             │
│   Load Module       Per-Profile          Summarize          │
│   Create Target     Operations           Results            │
│   Configure ACL     Mirror/Compress      Return Objects     │
└─────────────────────────────────────────────────────────────┘
```

## Design Patterns

### Advanced Function Pattern
- Uses `[CmdletBinding()]` for advanced function features
- Implements `SupportsShouldProcess` for safe operations
- Declares `[OutputType()]` for IntelliSense and pipeline clarity

### Region-Based Script Structure
The script uses `#region` sections for organization (converted from function-based to standalone script in v3.0.0):

```powershell
#region Functions
function Set-BackupFolderPermissions {
    # Configure NTFS permissions on backup root folder
}
#endregion

#region Initialization
# Import NTFSSecurity module
# Create target directory and configure permissions
# Initialize results collection
#endregion

#region Main Processing
# Profile discovery
# Per-profile backup and permission operations
#endregion

#region Summary and Output
# Summarization
# Return aggregated results
#endregion
```

### Splatting Pattern
Used for repetitive parameter sets:
```powershell
$permissionParams = @{
    Path         = $destPath
    AccessRights = 'FullControl'
}
Add-NTFSAccess @permissionParams -Account 'Administrators'
```

### Result Object Pattern
Returns structured objects for pipeline consumption:
```powershell
[PSCustomObject]@{
    ProfileName      = $profile.Name
    SourcePath       = $srcPath
    DestinationPath  = $destPath
    Status           = 'Success'
    RobocopyExitCode = $exitCode
    Error            = $null
}
```

## Error Handling Strategy

### Fail-Fast with Isolation
- `$ErrorActionPreference = 'Stop'` at script level
- Per-profile try-catch for isolation
- Continue processing other profiles on single failure
- Aggregate errors in result objects

### Robocopy Exit Code Handling
| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0-7 | Success (various copy states) | Continue |
| 8+ | Error occurred | Throw exception |

## Security Patterns

### Permission Layering
1. Standard principals (Administrators, SYSTEM)
2. Limited user access (Read, folder only)
3. Custom SIDs (configurable)
4. Replicated source ACEs (filtered by pattern)
5. Inheritance removal (isolation)

### ShouldProcess Integration
All state-changing operations wrapped:
```powershell
if ($PSCmdlet.ShouldProcess($target, 'Operation description')) {
    # Execute operation
}
```

## File Structure

```
SecureProfileBackup/
├── source/                 # Source code directory
│   └── Backup-UserProfile.ps1  # Main standalone script (v3.2.0)
├── tests/                  # Testing infrastructure
│   ├── Integration/        # Integration tests
│   │   └── Backup-UserProfile.Integration.Tests.ps1
│   ├── helpers/            # Test utilities
│   │   └── New-TestProfiles.ps1
│   ├── Invoke-Tests.ps1    # Test runner
│   └── README.md           # Test documentation
├── output/                 # Git-ignored output directory
│   ├── TestProfiles/       # Generated test data
│   ├── TestBackups/        # Test backup output
│   ├── TestResults/        # JUnit XML results
│   └── NTFSSecurity/       # Mock module (auto-generated)
├── memory-bank/            # Project documentation
│   ├── projectbrief.md     # Core requirements
│   ├── productContext.md   # User experience context
│   ├── systemPatterns.md   # This file
│   ├── techContext.md      # Technology details
│   ├── activeContext.md    # Current work focus
│   ├── progress.md         # Development status
│   └── promptHistory.md    # Interaction log
├── .clinerules/            # AI agent instructions
│   ├── chatmodes/          # Chat mode definitions
│   └── instructions/       # Language-specific guidelines
├── .gitignore              # Git ignore patterns
└── readme.md               # Project README
```

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Use robocopy over Copy-Item | Better performance, mirroring support, resilience |
| NTFSSecurity module | More intuitive API than native .NET ACL handling |
| Standalone script (v3.0.0) | Direct execution without dot-sourcing; simpler deployment |
| .NET ZipArchive for compression | Includes hidden files (unlike Compress-Archive); supports file exclusion |
| Generic List for results | Better performance than array append |
| Pattern-based profile selection | Flexibility for different naming conventions |
| Default ntuser* exclusion | Avoids locked file errors during backup |
| v2.3.0 security model | BUILTIN\Users has NO access to backups (security isolation) |
