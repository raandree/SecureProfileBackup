# SecureProfileBackup - Project Brief

## Project Overview

SecureProfileBackup is a PowerShell-based user profile backup and migration utility designed for enterprise environments. The project provides automated backup of user profile directories with proper NTFS permission configuration.

## Core Requirements

1. **Profile Backup**: Mirror user profile directories from source to target location
2. **Permission Management**: Configure NTFS permissions on backup directories
3. **Selective Backup**: Support pattern-based profile selection (e.g., numeric-named profiles)
4. **ACL Replication**: Replicate specific ACL entries from source to backup
5. **Inheritance Control**: Disable inheritance on backup directories for security isolation

## Goals

- Provide reliable, repeatable profile backup operations
- Maintain security through proper permission configuration
- Support enterprise deployment scenarios
- Follow PowerShell best practices and coding standards

## Target Environment

- Windows Server / Windows 10/11 environments
- PowerShell 5.1+ (Windows PowerShell)
- Requires NTFSSecurity module
- Requires Administrator privileges

## Key Features

- Robocopy-based mirroring for efficient file transfer
- Configurable source/target paths
- Pattern-based profile filtering
- SID-based permission assignment
- ShouldProcess support (-WhatIf, -Confirm)
- Comprehensive error handling and logging

## Success Criteria

- All profile directories are successfully backed up
- NTFS permissions are correctly configured
- Inheritance is properly disabled
- Operation is repeatable and idempotent
- Verbose logging provides operational visibility