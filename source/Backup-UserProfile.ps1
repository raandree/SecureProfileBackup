#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Backs up user profile directories using mirror copy or ZIP compression.

.DESCRIPTION
    Copies user profile directories from a source location to a target backup location.
    Supports two backup modes:
    - Mirror: Uses robocopy to mirror directories with NTFS permission configuration
    - Compress: Creates ZIP archives of each profile in the target directory

    Both modes configure NTFS permissions including removing inheritance
    and setting explicit access for Administrators, SYSTEM, profile owner, and specified SIDs.
    BUILTIN\Users has NO access to backups - only authorized principals can access the content.

.PARAMETER SourcePath
    The source directory containing user profiles to backup.
    Default: 'C:\Users'

.PARAMETER TargetPath
    The target directory where profiles will be backed up.
    Default: 'T:\ProfilesBackup'

.PARAMETER BackupMode
    The backup method to use.
    - Mirror: Uses robocopy to mirror directories (default)
    - Compress: Creates ZIP archives of each profile
    Default: 'Mirror'

.PARAMETER ProfilePattern
    Regular expression pattern to match profile directory names.
    Default: '^\d+$' (matches numeric directory names)

.PARAMETER AdditionalSids
    Array of Security Identifiers (SIDs) to grant FullControl access.
    Applied in both Mirror and Compress modes.

.PARAMETER SidFilterPattern
    Pattern to filter existing ACL entries by SID for replication to backup.
    Applied in both Mirror and Compress modes.
    Default: 'S-1-5-21-1230*'

.PARAMETER NTFSSecurityModulePath
    Path to the NTFSSecurity module manifest.
    Required for both modes (NTFS permissions applied in both).
    Default: '.\NTFSSecurity\NTFSSecurity.psd1'

.PARAMETER CompressionLevel
    Compression level for ZIP archives.
    - Optimal: Best compression ratio (slower)
    - Fastest: Fastest compression (larger files)
    - NoCompression: Store only, no compression
    Only applies to Compress mode.
    Default: 'Optimal'

.PARAMETER ExcludePatterns
    Array of wildcard patterns to exclude from backup.
    Files matching these patterns will be skipped.
    Applies to both Mirror mode (via robocopy /XF) and Compress mode.
    Default: @('ntuser*') - excludes ntuser.dat and related files which are typically locked.

.EXAMPLE
    .\Backup-UserProfile.ps1

    Backs up all numeric-named profiles from C:\Users to T:\ProfilesBackup
    using robocopy mirror mode with default settings.

.EXAMPLE
    .\Backup-UserProfile.ps1 -BackupMode Compress -Verbose

    Creates ZIP archives of all matching profiles in T:\ProfilesBackup.

.EXAMPLE
    .\Backup-UserProfile.ps1 -BackupMode Compress -CompressionLevel Fastest -TargetPath 'E:\Backup'

    Creates quickly-compressed ZIP archives in E:\Backup.

.EXAMPLE
    .\Backup-UserProfile.ps1 -SourcePath 'D:\Users' -TargetPath 'E:\Backup' -Verbose

    Backs up profiles from D:\Users to E:\Backup with verbose output using mirror mode.

.EXAMPLE
    .\Backup-UserProfile.ps1 -AdditionalSids @('S-1-5-21-123456-789') -WhatIf

    Shows what would happen without making changes (mirror mode).

.EXAMPLE
    .\Backup-UserProfile.ps1 -BackupMode Compress -ExcludePatterns @('ntuser*', '*.tmp', 'Thumbs.db')

    Creates ZIP archives excluding ntuser files, temporary files, and Thumbs.db.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns objects with profile backup status and details.

.NOTES
    Author: SecureProfileBackup
    Version: 3.2.0
    Requires: NTFSSecurity module, Administrator privileges

    NTFS permissions applied to all backups (both Mirror and Compress modes):
    - Administrators: FullControl
    - SYSTEM: FullControl
    - Profile owner (replicated from source): FullControl
    - Additional SIDs: FullControl
    - BUILTIN\Users: NO ACCESS

    Inheritance is disabled and inherited rules are removed to ensure
    only explicitly granted principals can access the backups.

.LINK
    https://github.com/raandree/NTFSSecurity
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$SourcePath = 'C:\Users',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TargetPath = 'T:\ProfilesBackup',

    [Parameter()]
    [ValidateSet('Mirror', 'Compress')]
    [string]$BackupMode = 'Mirror',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProfilePattern = '^\d+$',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]]$AdditionalSids = @('S-1-5-21-1230772385-5638642905-859402768-12345'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SidFilterPattern = 'S-1-5-21-1230*',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$NTFSSecurityModulePath = '.\NTFSSecurity\NTFSSecurity.psd1',

    [Parameter()]
    [ValidateSet('Optimal', 'Fastest', 'NoCompression')]
    [string]$CompressionLevel = 'Optimal',

    [Parameter()]
    [string[]]$ExcludePatterns = @('ntuser*')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Initialization

Write-Verbose "Starting profile backup operation"
Write-Verbose "Mode: $BackupMode"
Write-Verbose "Source: $SourcePath"
Write-Verbose "Target: $TargetPath"

# Import NTFSSecurity module (required for both modes - permissions applied to all backups)
if (-not (Test-Path -Path $NTFSSecurityModulePath -PathType Leaf)) {
    throw "NTFSSecurity module not found at: $NTFSSecurityModulePath"
}
Import-Module -Name $NTFSSecurityModulePath -ErrorAction Stop
Write-Verbose "Loaded NTFSSecurity module from: $NTFSSecurityModulePath"

# Ensure target root exists
if (-not (Test-Path -Path $TargetPath)) {
    if ($PSCmdlet.ShouldProcess($TargetPath, 'Create target directory')) {
        New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created target directory: $TargetPath"
    }
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

#endregion

#region Main Processing

$allProfiles = @(Get-ChildItem -Path $SourcePath -Directory |
    Where-Object { $_.Name -match $ProfilePattern })

Write-Verbose "Found $($allProfiles.Count) profiles matching pattern '$ProfilePattern'"

foreach ($userProfile in $allProfiles) {
    $srcPath = Join-Path -Path $SourcePath -ChildPath $userProfile.Name

    # Determine destination based on mode
    if ($BackupMode -eq 'Compress') {
        $destPath = Join-Path -Path $TargetPath -ChildPath "$($userProfile.Name).zip"
    } else {
        $destPath = Join-Path -Path $TargetPath -ChildPath $userProfile.Name
    }

    $result = [PSCustomObject]@{
        ProfileName      = $userProfile.Name
        SourcePath       = $srcPath
        DestinationPath  = $destPath
        BackupMode       = $BackupMode
        Status           = 'Pending'
        RobocopyExitCode = $null
        CompressedSize   = $null
        Error            = $null
    }

    try {
        Write-Verbose "Processing profile: $($userProfile.Name) [$BackupMode mode]"

        if ($BackupMode -eq 'Compress') {
            # ZIP Compression Mode
            if ($PSCmdlet.ShouldProcess($destPath, "Compress profile to ZIP archive")) {
                # Remove existing ZIP if present
                if (Test-Path -Path $destPath) {
                    Remove-Item -Path $destPath -Force
                    Write-Verbose "Removed existing archive: $destPath"
                }

                Write-Verbose "Compressing with level: $CompressionLevel"

                # Check if profile has any content (including hidden files)
                $allItems = @(Get-ChildItem -Path $srcPath -Force)
                
                if ($allItems.Count -eq 0) {
                    Write-Warning "No items found in profile: $srcPath"
                    $result.Status = 'Skipped'
                    $result.Error = 'Profile directory is empty'
                    $results.Add($result)
                    continue
                }

                Write-Verbose "Found $($allItems.Count) items to compress (including hidden)"

                # Use .NET ZipArchive class to ensure hidden files are included
                # and to support file exclusion patterns (e.g., ntuser* files which are locked)
                Add-Type -AssemblyName System.IO.Compression
                Add-Type -AssemblyName System.IO.Compression.FileSystem

                # Map CompressionLevel to .NET enum
                $netCompressionLevel = switch ($CompressionLevel) {
                    'Optimal'       { [System.IO.Compression.CompressionLevel]::Optimal }
                    'Fastest'       { [System.IO.Compression.CompressionLevel]::Fastest }
                    'NoCompression' { [System.IO.Compression.CompressionLevel]::NoCompression }
                    default         { [System.IO.Compression.CompressionLevel]::Optimal }
                }

                # Create ZIP archive manually to support exclusion patterns
                # CreateFromDirectory doesn't support file exclusions
                $zipStream = [System.IO.File]::Create($destPath)
                try {
                    $zipArchive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
                    try {
                        # Normalize the source path to ensure consistent path handling
                        # This resolves any relative paths and ensures trailing slash handling is consistent
                        $normalizedSrcPath = [System.IO.Path]::GetFullPath($srcPath).TrimEnd('\', '/')
                        
                        # Get all files recursively, including hidden files
                        $allFiles = Get-ChildItem -Path $srcPath -Recurse -Force -File -ErrorAction SilentlyContinue

                        $excludedCount = 0
                        $addedCount = 0

                        foreach ($file in $allFiles) {
                            # Check if file matches any exclusion pattern
                            $isExcluded = $false
                            foreach ($pattern in $ExcludePatterns) {
                                if ($file.Name -like $pattern) {
                                    $isExcluded = $true
                                    $excludedCount++
                                    Write-Verbose "Excluding file (matches '$pattern'): $($file.Name)"
                                    break
                                }
                            }

                            if ($isExcluded) {
                                continue
                            }

                            # Calculate relative path for ZIP entry
                            # Use normalized path to ensure correct substring calculation
                            $fileFullPath = [System.IO.Path]::GetFullPath($file.FullName)
                            $relativePath = $fileFullPath.Substring($normalizedSrcPath.Length).TrimStart('\', '/')

                            try {
                                # Create entry and copy file content
                                $entry = $zipArchive.CreateEntry($relativePath, $netCompressionLevel)
                                $entryStream = $entry.Open()
                                try {
                                    $fileStream = [System.IO.File]::OpenRead($file.FullName)
                                    try {
                                        $fileStream.CopyTo($entryStream)
                                        $addedCount++
                                    }
                                    finally {
                                        $fileStream.Dispose()
                                    }
                                }
                                finally {
                                    $entryStream.Dispose()
                                }
                            }
                            catch {
                                Write-Warning "Could not add file to archive: $($file.FullName) - $($_.Exception.Message)"
                            }
                        }

                        Write-Verbose "Added $addedCount files to archive, excluded $excludedCount files"
                    }
                    finally {
                        $zipArchive.Dispose()
                    }
                }
                finally {
                    $zipStream.Dispose()
                }

                # Get compressed file size
                $zipInfo = Get-Item -Path $destPath
                $result.CompressedSize = $zipInfo.Length
                Write-Verbose "Created archive: $destPath ($('{0:N2}' -f ($zipInfo.Length / 1MB)) MB)"
            }

            # Configure NTFS permissions on ZIP file
            if ($PSCmdlet.ShouldProcess($destPath, 'Configure NTFS permissions on ZIP archive')) {
                # Add standard permissions (FullControl)
                $permissionParams = @{
                    Path         = $destPath
                    AccessRights = 'FullControl'
                }

                Add-NTFSAccess @permissionParams -Account 'Administrators'
                Add-NTFSAccess @permissionParams -Account 'NT Authority\SYSTEM'

                # Add additional SIDs with FullControl
                foreach ($sid in $AdditionalSids) {
                    Write-Verbose "Adding FullControl for SID: $sid"
                    Add-NTFSAccess @permissionParams -Account $sid
                }

                # Replicate matching ACL entries from source (profile owner)
                $sourceAcl = Get-NTFSAccess -Path $userProfile.FullName |
                    Where-Object { $_.Account.Sid -like $SidFilterPattern }

                foreach ($ace in $sourceAcl) {
                    Write-Verbose "Replicating ACE for: $($ace.Account)"
                    Add-NTFSAccess @permissionParams -Account $ace.Account
                }

                # Note: BUILTIN\Users intentionally has NO access to ZIP archives
                # Only Administrators, SYSTEM, profile owner, and additional SIDs can access

                # Disable inheritance and remove inherited rules
                Disable-NTFSAccessInheritance -Path $destPath -RemoveInheritedAccessRules
                Write-Verbose "Configured permissions and disabled inheritance for: $destPath"
            }

            $result.Status = 'Success'
        } else {
            # Mirror Mode (robocopy with NTFS permissions)
            
            # Create destination directory
            if ($PSCmdlet.ShouldProcess($destPath, 'Create backup directory')) {
                New-Item -Path $destPath -ItemType Directory -Force | Out-Null
            }

            # Execute robocopy
            if ($PSCmdlet.ShouldProcess("$srcPath -> $destPath", 'Mirror directory with robocopy')) {
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
                    Write-Verbose "Excluding files matching patterns: $($ExcludePatterns -join ', ')"
                }

                $robocopyProcess = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                $result.RobocopyExitCode = $robocopyProcess.ExitCode

                # Robocopy exit codes: 0-7 are success, 8+ are errors
                if ($robocopyProcess.ExitCode -ge 8) {
                    throw "Robocopy failed with exit code: $($robocopyProcess.ExitCode)"
                }

                Write-Verbose "Robocopy completed with exit code: $($robocopyProcess.ExitCode)"
            }

            # Configure NTFS permissions
            if ($PSCmdlet.ShouldProcess($destPath, 'Configure NTFS permissions')) {
                # Add standard permissions
                $permissionParams = @{
                    Path         = $destPath
                    AccessRights = 'FullControl'
                }

                Add-NTFSAccess @permissionParams -Account 'Administrators'
                Add-NTFSAccess @permissionParams -Account 'NT Authority\SYSTEM'

                # Note: BUILTIN\Users intentionally has NO access to backup folders
                # Only Administrators, SYSTEM, profile owner, and additional SIDs can access

                # Add additional SIDs
                foreach ($sid in $AdditionalSids) {
                    Write-Verbose "Adding FullControl for SID: $sid"
                    Add-NTFSAccess @permissionParams -Account $sid
                }

                # Replicate matching ACL entries from source
                $sourceAcl = Get-NTFSAccess -Path $userProfile.FullName |
                    Where-Object { $_.Account.Sid -like $SidFilterPattern }

                foreach ($ace in $sourceAcl) {
                    Write-Verbose "Replicating ACE for: $($ace.Account)"
                    Add-NTFSAccess @permissionParams -Account $ace.Account
                }

                # Disable inheritance and remove inherited rules
                Disable-NTFSAccessInheritance -Path $destPath -RemoveInheritedAccessRules
                Write-Verbose "Disabled inheritance for: $destPath"
            }

            $result.Status = 'Success'
        }
    }
    catch {
        $result.Status = 'Failed'
        $result.Error = $_.Exception.Message
        Write-Error "Failed to backup profile '$($userProfile.Name)': $_"
    }

    $results.Add($result)
}

#endregion

#region Summary and Output

Write-Verbose "Backup operation completed. Processed $($results.Count) profiles."

$successCount = @($results | Where-Object { $_.Status -eq 'Success' }).Count
$failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Verbose "Success: $successCount, Failed: $failedCount"

if ($BackupMode -eq 'Compress') {
    $compressedResults = @($results | Where-Object { $null -ne $_.CompressedSize })
    if ($compressedResults.Count -gt 0) {
        $measurement = $compressedResults | Measure-Object -Property CompressedSize -Sum
        $totalSize = if ($null -ne $measurement.Sum) { $measurement.Sum } else { 0 }
        Write-Verbose "Total compressed size: $('{0:N2}' -f ($totalSize / 1MB)) MB"
    } else {
        Write-Verbose "No compressed archives created."
    }
}

# Return results
return $results

#endregion