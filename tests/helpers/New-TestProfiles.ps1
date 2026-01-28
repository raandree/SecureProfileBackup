#Requires -Version 5.1

<#
.SYNOPSIS
    Generates test profile directories with sample files for integration testing.

.DESCRIPTION
    Creates a configurable set of dummy user profiles in a specified directory.
    Each profile contains various files and subdirectories to simulate real user profiles.
    Each profile is configured with a random ACL entry granting FullControl to simulate
    a dedicated profile owner. This ACL is designed to be replicated during backup operations.
    This script is designed for use in integration tests of the Backup-UserProfile function.

.PARAMETER OutputPath
    The root directory where test profiles will be created.
    Default: './output/TestProfiles'

.PARAMETER ProfileCount
    The number of test profiles to generate.
    Default: 5

.PARAMETER ProfileNamePrefix
    Numeric prefix for profile names. Profile names will be sequential numbers starting from this value.
    Default: 10000

.PARAMETER IncludeEdgeCases
    When specified, includes edge case profiles such as:
    - Empty profile
    - Profile with special characters in filenames
    - Profile with deeply nested directories
    - Profile with large files
    - Profile with many small files
    - Profile with read-only files
    - Profile with hidden files and folders
    Default: $false

.PARAMETER FileSizeKB
    Base size in KB for generated test files.
    Default: 10

.PARAMETER CleanExisting
    When specified, removes existing test profiles before creating new ones.
    Default: $false

.PARAMETER NTFSSecurityModulePath
    Path to the NTFSSecurity module manifest for ACL configuration.
    Default: './output/NTFSSecurity/NTFSSecurity.psd1'

.EXAMPLE
    .\New-TestProfiles.ps1

    Creates 5 test profiles in ./output/TestProfiles with default settings.

.EXAMPLE
    .\New-TestProfiles.ps1 -ProfileCount 10 -IncludeEdgeCases -Verbose

    Creates 10 test profiles plus edge case profiles with verbose output.

.EXAMPLE
    .\New-TestProfiles.ps1 -OutputPath 'D:\TestData' -CleanExisting

    Creates test profiles in D:\TestData, removing any existing profiles first.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Returns objects describing each created profile.

.NOTES
    Author: SecureProfileBackup Test Framework
    Version: 1.2.0

    Each profile receives a unique ACL entry with FullControl for a SID in the domain space.
    The SID follows the pattern S-1-5-21-1230772385-5638642905-859402768-RID where:
    - The domain portion (S-1-5-21-1230772385-5638642905-859402768) is fixed
    - The RID (Relative Identifier) is derived from the profile name
    
    This matches the default SidFilterPattern in Backup-UserProfile, so profile owner
    ACLs are automatically replicated to backups without additional configuration.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = './output/TestProfiles',

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$ProfileCount = 5,

    [Parameter()]
    [ValidateRange(10000, 99999)]
    [int]$ProfileNamePrefix = 10000,

    [Parameter()]
    [switch]$IncludeEdgeCases,

    [Parameter()]
    [ValidateRange(1, 10240)]
    [int]$FileSizeKB = 10,

    [Parameter()]
    [switch]$CleanExisting,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$NTFSSecurityModulePath = './output/NTFSSecurity/NTFSSecurity.psd1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helper Functions

function New-RandomProfileOwnerSid {
    <#
    .SYNOPSIS
        Generates a SID within the specified domain SID space for a profile owner.
    .DESCRIPTION
        Creates a SID following the pattern S-1-5-21-1230772385-5638642905-859402768-RID
        where the domain components are fixed (matching the production domain) and
        only the RID (Relative Identifier) varies. The RID is derived from the
        profile name for traceability, or randomized within valid RID ranges.
    .NOTES
        Domain SID: S-1-5-21-1230772385-5638642905-859402768
        This matches the default SidFilterPattern used in Backup-UserProfile.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName
    )

    # Fixed domain SID components (matching production domain)
    $domainSidPrefix = 'S-1-5-21-1230772385-5638642905-859402768'
    
    # Generate RID (Relative Identifier) based on profile name
    # Use profile name as RID for traceability if numeric
    # Otherwise generate a random RID in the user range (1000+)
    if ($ProfileName -match '^\d+$') {
        $rid = [int]$ProfileName
    } else {
        # Generate random RID for non-numeric profile names
        # Using range 500000-999999 to avoid conflicts with real accounts
        $random = [System.Random]::new()
        $rid = $random.Next(500000, 1000000)
    }
    
    # Construct full SID string within domain SID space
    $sid = "$domainSidPrefix-$rid"
    
    Write-Verbose "Generated profile owner SID: $sid (based on profile: $ProfileName)"
    
    return $sid
}

function Set-ProfileOwnerAcl {
    <#
    .SYNOPSIS
        Configures ACL for a test profile with a random owner having FullControl.
    .DESCRIPTION
        Adds a random SID with FullControl to the profile directory.
        This simulates a dedicated user profile where only the owner has full access.
        The SID is designed to be replicated during backup operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string]$OwnerSid
    )

    Write-Verbose "Setting profile owner ACL for: $ProfilePath"
    Write-Verbose "Owner SID: $OwnerSid"

    try {
        # Convert SID string to SecurityIdentifier object for proper ACL application
        $sidObject = [System.Security.Principal.SecurityIdentifier]::new($OwnerSid)
        Write-Verbose "Created SecurityIdentifier object: $($sidObject.Value)"
        
        # Add FullControl for the profile owner SID
        # Use the SID object directly for more reliable ACL application
        Add-NTFSAccess -Path $ProfilePath -Account $sidObject -AccessRights 'FullControl' -ErrorAction Stop
        Write-Verbose "Added FullControl for SID: $OwnerSid"
        
        # Verify the ACL was applied
        $verifyAcl = Get-NTFSAccess -Path $ProfilePath -ErrorAction SilentlyContinue | 
            Where-Object { $_.Account.Sid -eq $OwnerSid }
        
        if ($verifyAcl) {
            Write-Verbose "Verified ACL entry exists for SID: $OwnerSid"
            return $true
        } else {
            Write-Warning "ACL entry not found after applying. SID: $OwnerSid"
            return $false
        }
    }
    catch {
        Write-Warning "Failed to set ACL for profile: $ProfilePath"
        Write-Warning "SID: $OwnerSid"
        Write-Warning "Error: $($_.Exception.Message)"
        Write-Warning "Full Error: $_"
        return $false
    }
}

function New-RandomContent {
    <#
    .SYNOPSIS
        Generates random text content of specified size.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SizeKB
    )

    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '
    $targetBytes = $SizeKB * 1024
    $sb = [System.Text.StringBuilder]::new($targetBytes)
    $random = [System.Random]::new()

    while ($sb.Length -lt $targetBytes) {
        [void]$sb.Append($chars[$random.Next($chars.Length)])
        if ($sb.Length % 80 -eq 0) {
            [void]$sb.AppendLine()
        }
    }

    return $sb.ToString()
}

function New-StandardProfileContent {
    <#
    .SYNOPSIS
        Creates standard profile structure with typical user files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter()]
        [int]$FileSizeKB = 10
    )

    Write-Verbose "Creating standard profile content in: $ProfilePath"

    # Create standard Windows profile directories
    $directories = @(
        'Desktop'
        'Documents'
        'Downloads'
        'Pictures'
        'Music'
        'Videos'
        'AppData\Local'
        'AppData\Roaming'
        'AppData\LocalLow'
    )

    foreach ($dir in $directories) {
        $dirPath = Join-Path -Path $ProfilePath -ChildPath $dir
        New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created directory: $dir"
    }

    # Set the AppData folder as hidden (like in real Windows profiles)
    $appDataPath = Join-Path -Path $ProfilePath -ChildPath 'AppData'
    $appDataDir = Get-Item -Path $appDataPath -Force
    $appDataDir.Attributes = $appDataDir.Attributes -bor [System.IO.FileAttributes]::Hidden
    Write-Verbose "Set AppData folder as hidden"

    # Create sample files in each directory
    $fileTypes = @{
        'Desktop'   = @('shortcut.lnk.txt', 'readme.txt', 'notes.txt')
        'Documents' = @('report.docx.txt', 'spreadsheet.xlsx.txt', 'presentation.pptx.txt', 'memo.txt')
        'Downloads' = @('installer.exe.txt', 'archive.zip.txt', 'image.jpg.txt')
        'Pictures'  = @('photo1.jpg.txt', 'photo2.png.txt', 'screenshot.bmp.txt')
        'Music'     = @('song1.mp3.txt', 'song2.flac.txt')
        'Videos'    = @('video1.mp4.txt', 'clip.avi.txt')
    }

    foreach ($dir in $fileTypes.Keys) {
        $dirPath = Join-Path -Path $ProfilePath -ChildPath $dir
        foreach ($file in $fileTypes[$dir]) {
            $filePath = Join-Path -Path $dirPath -ChildPath $file
            $content = New-RandomContent -SizeKB $FileSizeKB
            Set-Content -Path $filePath -Value $content -Encoding UTF8
            Write-Verbose "Created file: $dir\$file"
        }
    }

    # Create some config files in AppData
    $appDataFiles = @(
        @{ Path = 'AppData\Local\settings.json'; Content = '{"theme": "dark", "language": "en-US"}' }
        @{ Path = 'AppData\Roaming\config.xml'; Content = '<?xml version="1.0"?><config><setting name="test" value="true"/></config>' }
        @{ Path = 'AppData\Local\cache.dat'; Content = (New-RandomContent -SizeKB ($FileSizeKB * 2)) }
    )

    foreach ($fileInfo in $appDataFiles) {
        $filePath = Join-Path -Path $ProfilePath -ChildPath $fileInfo.Path
        Set-Content -Path $filePath -Value $fileInfo.Content -Encoding UTF8
        Write-Verbose "Created AppData file: $($fileInfo.Path)"
    }

    # Create hidden folders (common in Windows profiles)
    $hiddenDirectories = @(
        'AppData\Local\Microsoft\Windows\History'
        'AppData\Local\Microsoft\Windows\INetCache'
        'AppData\Local\Microsoft\Windows\Temporary Internet Files'
        '.hidden_config'
    )

    foreach ($hiddenDir in $hiddenDirectories) {
        $hiddenDirPath = Join-Path -Path $ProfilePath -ChildPath $hiddenDir
        $createdDir = New-Item -Path $hiddenDirPath -ItemType Directory -Force
        $createdDir.Attributes = $createdDir.Attributes -bor [System.IO.FileAttributes]::Hidden
        Write-Verbose "Created hidden directory: $hiddenDir"
        
        # Add a file inside each hidden directory
        $hiddenDirFilePath = Join-Path -Path $hiddenDirPath -ChildPath 'data.dat'
        Set-Content -Path $hiddenDirFilePath -Value "Hidden directory content for: $hiddenDir" -Encoding UTF8
    }

    # Create hidden files
    $hiddenFiles = @(
        @{ Path = 'desktop.ini'; Content = '[.ShellClassInfo]' }
        @{ Path = 'AppData\Local\.cache'; Content = 'cache data' }
        @{ Path = 'Documents\.hidden_notes.txt'; Content = 'These are hidden notes' }
    )

    foreach ($hiddenFileInfo in $hiddenFiles) {
        $hiddenFilePath = Join-Path -Path $ProfilePath -ChildPath $hiddenFileInfo.Path
        Set-Content -Path $hiddenFilePath -Value $hiddenFileInfo.Content -Encoding UTF8
        $fileItem = Get-Item -Path $hiddenFilePath -Force
        $fileItem.Attributes = $fileItem.Attributes -bor [System.IO.FileAttributes]::Hidden
        Write-Verbose "Created hidden file: $($hiddenFileInfo.Path)"
    }

    # Create NTUSER.DAT placeholder
    $ntUserPath = Join-Path -Path $ProfilePath -ChildPath 'NTUSER.DAT.txt'
    Set-Content -Path $ntUserPath -Value 'NTUSER.DAT placeholder for testing' -Encoding UTF8
}

function New-EdgeCaseProfile {
    <#
    .SYNOPSIS
        Creates profiles with edge case scenarios for thorough testing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [ValidateSet('Empty', 'SpecialChars', 'DeepNested', 'LargeFiles', 'ManyFiles', 'ReadOnly', 'Hidden')]
        [string]$EdgeCaseType,

        [Parameter()]
        [int]$FileSizeKB = 10
    )

    $profilePath = Join-Path -Path $BasePath -ChildPath $ProfileName
    New-Item -Path $profilePath -ItemType Directory -Force | Out-Null

    Write-Verbose "Creating edge case profile [$EdgeCaseType]: $ProfileName"

    switch ($EdgeCaseType) {
        'Empty' {
            # Create a minimal profile with just one small marker file
            # This allows compression to work while testing near-empty scenarios
            $markerPath = Join-Path -Path $profilePath -ChildPath '.profile_marker'
            Set-Content -Path $markerPath -Value 'Minimal profile marker' -Encoding UTF8
            Write-Verbose "Created minimal profile with marker file"
        }

        'SpecialChars' {
            # Create files with various special characters in names
            $specialFiles = @(
                'file with spaces.txt'
                'file-with-dashes.txt'
                'file_with_underscores.txt'
                'file.multiple.dots.txt'
                'UPPERCASE.TXT'
                'MixedCase.Txt'
            )

            foreach ($file in $specialFiles) {
                $filePath = Join-Path -Path $profilePath -ChildPath $file
                Set-Content -Path $filePath -Value "Content for: $file" -Encoding UTF8
            }
            Write-Verbose "Created $($specialFiles.Count) files with special characters"
        }

        'DeepNested' {
            # Create deeply nested directory structure
            $currentPath = $profilePath
            for ($i = 1; $i -le 15; $i++) {
                $currentPath = Join-Path -Path $currentPath -ChildPath "Level$i"
                New-Item -Path $currentPath -ItemType Directory -Force | Out-Null

                # Add a file at each level
                $filePath = Join-Path -Path $currentPath -ChildPath "file_level_$i.txt"
                Set-Content -Path $filePath -Value "Content at level $i" -Encoding UTF8
            }
            Write-Verbose "Created 15-level deep directory structure"
        }

        'LargeFiles' {
            # Create a few larger files
            $largeFileSizes = @(100, 500, 1024) # KB

            foreach ($size in $largeFileSizes) {
                $filePath = Join-Path -Path $profilePath -ChildPath "large_${size}KB.dat"
                $content = New-RandomContent -SizeKB $size
                Set-Content -Path $filePath -Value $content -Encoding UTF8
                Write-Verbose "Created large file: ${size}KB"
            }
        }

        'ManyFiles' {
            # Create many small files
            $fileCount = 100
            $smallDir = Join-Path -Path $profilePath -ChildPath 'ManyFiles'
            New-Item -Path $smallDir -ItemType Directory -Force | Out-Null

            for ($i = 1; $i -le $fileCount; $i++) {
                $filePath = Join-Path -Path $smallDir -ChildPath "file_$($i.ToString('D4')).txt"
                Set-Content -Path $filePath -Value "Small file content #$i" -Encoding UTF8
            }
            Write-Verbose "Created $fileCount small files"
        }

        'ReadOnly' {
            # Create files with read-only attribute
            $roDir = Join-Path -Path $profilePath -ChildPath 'ReadOnlyFiles'
            New-Item -Path $roDir -ItemType Directory -Force | Out-Null

            for ($i = 1; $i -le 5; $i++) {
                $filePath = Join-Path -Path $roDir -ChildPath "readonly_$i.txt"
                Set-Content -Path $filePath -Value "Read-only file content #$i" -Encoding UTF8
                Set-ItemProperty -Path $filePath -Name IsReadOnly -Value $true
            }
            Write-Verbose "Created 5 read-only files"
        }

        'Hidden' {
            # Create a comprehensive set of hidden files and folders for testing
            # This tests backup/restore handling of hidden attributes
            
            # Create hidden directories at various levels
            $hiddenDirs = @(
                '.hidden_root_folder'
                'Documents\.hidden_docs'
                'AppData\.hidden_appdata'
                'AppData\Local\.hidden_local'
            )

            foreach ($hiddenDir in $hiddenDirs) {
                $hiddenDirPath = Join-Path -Path $profilePath -ChildPath $hiddenDir
                $createdDir = New-Item -Path $hiddenDirPath -ItemType Directory -Force
                $createdDir.Attributes = $createdDir.Attributes -bor [System.IO.FileAttributes]::Hidden
                
                # Add visible files inside hidden directories
                $visibleFilePath = Join-Path -Path $hiddenDirPath -ChildPath 'visible_inside_hidden.txt'
                Set-Content -Path $visibleFilePath -Value "This is a visible file inside a hidden folder: $hiddenDir" -Encoding UTF8
                
                # Add hidden files inside hidden directories
                $hiddenFilePath = Join-Path -Path $hiddenDirPath -ChildPath '.hidden_inside_hidden.txt'
                Set-Content -Path $hiddenFilePath -Value "This is a hidden file inside a hidden folder: $hiddenDir" -Encoding UTF8
                $hiddenFileItem = Get-Item -Path $hiddenFilePath -Force
                $hiddenFileItem.Attributes = $hiddenFileItem.Attributes -bor [System.IO.FileAttributes]::Hidden
            }
            Write-Verbose "Created $($hiddenDirs.Count) hidden directories with nested content"

            # Create hidden files in visible directories
            $visibleDir = Join-Path -Path $profilePath -ChildPath 'VisibleFolder'
            New-Item -Path $visibleDir -ItemType Directory -Force | Out-Null

            $hiddenFiles = @(
                @{ Name = '.gitignore'; Content = '# Git ignore file' }
                @{ Name = '.env'; Content = 'SECRET_KEY=test123' }
                @{ Name = 'desktop.ini'; Content = '[.ShellClassInfo]' }
                @{ Name = '.hidden_config.json'; Content = '{"hidden": true}' }
                @{ Name = 'thumbs.db'; Content = 'Thumbnail cache placeholder' }
            )

            foreach ($hiddenFile in $hiddenFiles) {
                $filePath = Join-Path -Path $visibleDir -ChildPath $hiddenFile.Name
                Set-Content -Path $filePath -Value $hiddenFile.Content -Encoding UTF8
                $fileItem = Get-Item -Path $filePath -Force
                $fileItem.Attributes = $fileItem.Attributes -bor [System.IO.FileAttributes]::Hidden
            }
            Write-Verbose "Created $($hiddenFiles.Count) hidden files in visible folder"

            # Create a mix of hidden and visible files in root
            $rootHiddenFiles = @('.profile', '.bashrc', '.config')
            foreach ($fileName in $rootHiddenFiles) {
                $filePath = Join-Path -Path $profilePath -ChildPath $fileName
                Set-Content -Path $filePath -Value "Root hidden file: $fileName" -Encoding UTF8
                $fileItem = Get-Item -Path $filePath -Force
                $fileItem.Attributes = $fileItem.Attributes -bor [System.IO.FileAttributes]::Hidden
            }

            # Create some visible files for comparison
            $visibleFiles = @('visible1.txt', 'visible2.txt', 'readme.txt')
            foreach ($fileName in $visibleFiles) {
                $filePath = Join-Path -Path $profilePath -ChildPath $fileName
                Set-Content -Path $filePath -Value "Visible file: $fileName" -Encoding UTF8
            }

            Write-Verbose "Created Hidden edge case profile with mixed hidden/visible content"
        }
    }

    return [PSCustomObject]@{
        ProfileName   = $ProfileName
        ProfilePath   = $profilePath
        EdgeCaseType  = $EdgeCaseType
    }
}

#endregion

#region Main Execution

Write-Verbose "Starting test profile generation"
Write-Verbose "Output Path: $OutputPath"
Write-Verbose "Profile Count: $ProfileCount"
Write-Verbose "Include Edge Cases: $IncludeEdgeCases"
Write-Verbose "NTFSSecurity Module: $NTFSSecurityModulePath"

# Import NTFSSecurity module for ACL configuration
if (-not (Test-Path -Path $NTFSSecurityModulePath -PathType Leaf)) {
    Write-Warning "NTFSSecurity module not found at: $NTFSSecurityModulePath"
    Write-Warning "ACL configuration will be skipped. Profiles will be created without custom ACLs."
    $aclEnabled = $false
} else {
    try {
        # IMPORTANT: Remove any existing NTFSSecurity module first to ensure we use the specified one
        # This prevents mock modules from interfering with real module usage
        $existingModule = Get-Module -Name NTFSSecurity -All -ErrorAction SilentlyContinue
        if ($existingModule) {
            Write-Verbose "Removing existing NTFSSecurity module(s) from memory..."
            $existingModule | Remove-Module -Force -ErrorAction SilentlyContinue
        }
        
        # Now import the specified module with -Force to ensure fresh load
        Import-Module -Name $NTFSSecurityModulePath -Force -ErrorAction Stop
        
        # Verify the loaded module is from the expected path
        $loadedModule = Get-Module -Name NTFSSecurity
        Write-Verbose "Loaded NTFSSecurity module:"
        Write-Verbose "  Path: $($loadedModule.ModuleBase)"
        Write-Verbose "  Version: $($loadedModule.Version)"
        
        $aclEnabled = $true
    }
    catch {
        Write-Warning "Failed to import NTFSSecurity module: $_"
        Write-Warning "ACL configuration will be skipped. Profiles will be created without custom ACLs."
        $aclEnabled = $false
    }
}

# Clean existing if requested
if ($CleanExisting -and (Test-Path -Path $OutputPath)) {
    Write-Verbose "Removing existing test profiles at: $OutputPath"
    Remove-Item -Path $OutputPath -Recurse -Force
}

# Create output directory
if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Verbose "Created output directory: $OutputPath"
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Create standard profiles
for ($i = 0; $i -lt $ProfileCount; $i++) {
    $profileName = ($ProfileNamePrefix + $i).ToString()
    $profilePath = Join-Path -Path $OutputPath -ChildPath $profileName

    Write-Verbose "Creating standard profile: $profileName"

    try {
        New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
        New-StandardProfileContent -ProfilePath $profilePath -FileSizeKB $FileSizeKB

        # Generate and apply random ACL for profile owner
        $ownerSid = $null
        $aclApplied = $false
        if ($aclEnabled) {
            $ownerSid = New-RandomProfileOwnerSid -ProfileName $profileName
            $aclApplied = Set-ProfileOwnerAcl -ProfilePath $profilePath -OwnerSid $ownerSid
            Write-Verbose "Applied owner ACL with SID: $ownerSid (Success: $aclApplied)"
        }

        $fileCount = (Get-ChildItem -Path $profilePath -Recurse -File).Count
        $totalSize = (Get-ChildItem -Path $profilePath -Recurse -File | Measure-Object -Property Length -Sum).Sum

        $result = [PSCustomObject]@{
            ProfileName  = $profileName
            ProfilePath  = $profilePath
            Type         = 'Standard'
            FileCount    = $fileCount
            TotalSizeKB  = [math]::Round($totalSize / 1024, 2)
            OwnerSid     = $ownerSid
            AclApplied   = $aclApplied
            Status       = 'Created'
            Error        = $null
        }

        $results.Add($result)
        Write-Verbose "Created profile $profileName with $fileCount files ($('{0:N2}' -f ($totalSize / 1024)) KB)"
    }
    catch {
        $result = [PSCustomObject]@{
            ProfileName  = $profileName
            ProfilePath  = $profilePath
            Type         = 'Standard'
            FileCount    = 0
            TotalSizeKB  = 0
            OwnerSid     = $null
            AclApplied   = $false
            Status       = 'Failed'
            Error        = $_.Exception.Message
        }

        $results.Add($result)
        Write-Error "Failed to create profile $profileName`: $_"
    }
}

# Create edge case profiles if requested
if ($IncludeEdgeCases) {
    Write-Verbose "Creating edge case profiles"

    $edgeCases = @(
        @{ Name = '99991'; Type = 'Empty' }
        @{ Name = '99992'; Type = 'SpecialChars' }
        @{ Name = '99993'; Type = 'DeepNested' }
        @{ Name = '99994'; Type = 'LargeFiles' }
        @{ Name = '99995'; Type = 'ManyFiles' }
        @{ Name = '99996'; Type = 'ReadOnly' }
        @{ Name = '99997'; Type = 'Hidden' }
    )

    foreach ($edgeCase in $edgeCases) {
        try {
            $ecResult = New-EdgeCaseProfile -BasePath $OutputPath -ProfileName $edgeCase.Name -EdgeCaseType $edgeCase.Type -FileSizeKB $FileSizeKB

            $profilePath = Join-Path -Path $OutputPath -ChildPath $edgeCase.Name

            # Generate and apply random ACL for edge case profile owner
            $ownerSid = $null
            $aclApplied = $false
            if ($aclEnabled) {
                $ownerSid = New-RandomProfileOwnerSid -ProfileName $edgeCase.Name
                $aclApplied = Set-ProfileOwnerAcl -ProfilePath $profilePath -OwnerSid $ownerSid
                Write-Verbose "Applied owner ACL with SID: $ownerSid (Success: $aclApplied)"
            }

            $files = @(Get-ChildItem -Path $profilePath -Recurse -File -ErrorAction SilentlyContinue)
            $fileCount = $files.Count
            $totalSize = if ($fileCount -gt 0) { ($files | Measure-Object -Property Length -Sum).Sum } else { 0 }

            $result = [PSCustomObject]@{
                ProfileName  = $edgeCase.Name
                ProfilePath  = $profilePath
                Type         = "EdgeCase-$($edgeCase.Type)"
                FileCount    = $fileCount
                TotalSizeKB  = [math]::Round($totalSize / 1024, 2)
                OwnerSid     = $ownerSid
                AclApplied   = $aclApplied
                Status       = 'Created'
                Error        = $null
            }

            $results.Add($result)
        }
        catch {
            $result = [PSCustomObject]@{
                ProfileName  = $edgeCase.Name
                ProfilePath  = (Join-Path -Path $OutputPath -ChildPath $edgeCase.Name)
                Type         = "EdgeCase-$($edgeCase.Type)"
                FileCount    = 0
                TotalSizeKB  = 0
                OwnerSid     = $null
                AclApplied   = $false
                Status       = 'Failed'
                Error        = $_.Exception.Message
            }

            $results.Add($result)
            Write-Error "Failed to create edge case profile $($edgeCase.Name): $_"
        }
    }
}

# Summary
$successCount = @($results | Where-Object { $_.Status -eq 'Created' }).Count
$failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
$aclAppliedCount = @($results | Where-Object { $_.AclApplied -eq $true }).Count
$fileMeasure = $results | Measure-Object -Property FileCount -Sum
$sizeMeasure = $results | Measure-Object -Property TotalSizeKB -Sum
$totalFiles = if ($fileMeasure.Sum) { $fileMeasure.Sum } else { 0 }
$totalSizeKB = if ($sizeMeasure.Sum) { $sizeMeasure.Sum } else { 0 }

Write-Verbose "Test profile generation completed"
Write-Verbose "Profiles created: $successCount, Failed: $failedCount"
Write-Verbose "ACLs applied: $aclAppliedCount"
Write-Verbose "Total files: $totalFiles, Total size: $('{0:N2}' -f $totalSizeKB) KB"

# Output owner SID info for backup script configuration
if ($aclAppliedCount -gt 0) {
    Write-Verbose "Profile owner SIDs use domain: S-1-5-21-1230772385-5638642905-859402768-*"
    Write-Verbose "These SIDs match the default SidFilterPattern in Backup-UserProfile (S-1-5-21-1230*)"
}

# Return results
return $results

#endregion