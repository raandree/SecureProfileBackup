# SecureProfileBackup - System Patterns

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Backup-UserProfile                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐    ┌──────────┐    ┌────────────────────┐     │
│  │  BEGIN  │───▶│ PROCESS  │───▶│        END         │     │
│  │  Block  │    │  Block   │    │       Block        │     │
│  └─────────┘    └──────────┘    └────────────────────┘     │
│       │              │                    │                 │
│       ▼              ▼                    ▼                 │
│  Initialize     Per-Profile          Summarize             │
│  Target Dir     Operations           Results               │
└─────────────────────────────────────────────────────────────┘
```

## Design Patterns

### Advanced Function Pattern
- Uses `[CmdletBinding()]` for advanced function features
- Implements `SupportsShouldProcess` for safe operations
- Declares `[OutputType()]` for IntelliSense and pipeline clarity

### Begin-Process-End Pattern
```powershell
begin {
    # One-time initialization
    # Create target directory
    # Initialize results collection
}

process {
    # Per-item processing
    # Profile discovery
    # Backup and permission operations
}

end {
    # Summarization
    # Return aggregated results
}
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
│   └── Backup-UserProfile.ps1  # Main script with Backup-UserProfile function
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
├── .vscode/                # VS Code settings
└── .github/                # GitHub workflows
```

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Use robocopy over Copy-Item | Better performance, mirroring support, resilience |
| NTFSSecurity module | More intuitive API than native .NET ACL handling |
| Single function approach | Simple script, not a full module |
| Generic List for results | Better performance than array append |
| Pattern-based profile selection | Flexibility for different naming conventions |