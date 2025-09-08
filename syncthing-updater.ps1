# Syncthing Auto-Update Script for Windows
# Run this script as Administrator for best results

param(
    [string]$InstallPath = "C:\Program Files\Syncthing",
    [string]$ServiceName = "Syncthing",
    [switch]$Force
)

# Function to get latest version from GitHub API
function Get-LatestSyncthingVersion {
    try {
        $apiUrl = "https://api.github.com/repos/syncthing/syncthing/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get
        return $response.tag_name.TrimStart('v')
    }
    catch {
        Write-Error "Failed to fetch latest version: $($_.Exception.Message)"
        return $null
    }
}

# Function to get current installed version
function Get-CurrentSyncthingVersion {
    try {
        if (Test-Path "$InstallPath\syncthing.exe") {
            $versionOutput = & "$InstallPath\syncthing.exe" --version 2>$null
            if ($versionOutput -match "syncthing v(\d+\.\d+\.\d+)") {
                return $matches[1]
            }
        }
        return $null
    }
    catch {
        Write-Warning "Could not determine current version: $($_.Exception.Message)"
        return $null
    }
}

# Function to stop Syncthing service/process
function Stop-Syncthing {
    Write-Host "Stopping Syncthing..." -ForegroundColor Yellow
    
    # Try to stop as service first
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    
    # Kill any remaining processes
    Get-Process -Name "syncthing" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Function to start Syncthing service/process
function Start-Syncthing {
    Write-Host "Starting Syncthing..." -ForegroundColor Green
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }
    else {
        # If not running as service, you might want to start it manually
        Write-Host "No service found. You may need to start Syncthing manually." -ForegroundColor Yellow
    }
}

# Function to download and install update
function Update-Syncthing {
    param([string]$Version)
    
    Write-Host "Downloading Syncthing v$Version..." -ForegroundColor Cyan
    
    # Construct download URL
    $downloadUrl = "https://github.com/syncthing/syncthing/releases/download/v$Version/syncthing-windows-amd64-v$Version.zip"
    $tempPath = "$env:TEMP\syncthing-v$Version.zip"
    $extractPath = "$env:TEMP\syncthing-v$Version"
    
    try {
        # Download the file
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
        
        # Extract the archive
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
        Expand-Archive -Path $tempPath -DestinationPath $extractPath
        
        # Find the syncthing.exe in extracted folder
        $syncthingExe = Get-ChildItem -Path $extractPath -Name "syncthing.exe" -Recurse | Select-Object -First 1
        if (-not $syncthingExe) {
            throw "syncthing.exe not found in downloaded archive"
        }
        
        $sourcePath = Join-Path $extractPath $syncthingExe.DirectoryName "syncthing.exe"
        
        # Stop Syncthing before replacing
        Stop-Syncthing
        
        # Create install directory if it doesn't exist
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        }
        
        # Backup current version
        $backupPath = "$InstallPath\syncthing.exe.bak"
        if (Test-Path "$InstallPath\syncthing.exe") {
            Copy-Item "$InstallPath\syncthing.exe" $backupPath -Force
            Write-Host "Backed up current version to syncthing.exe.bak" -ForegroundColor Yellow
        }
        
        # Copy new version
        Copy-Item $sourcePath "$InstallPath\syncthing.exe" -Force
        
        Write-Host "Successfully updated to Syncthing v$Version" -ForegroundColor Green
        
        # Start Syncthing again
        Start-Syncthing
        
        # Cleanup
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-Error "Failed to update Syncthing: $($_.Exception.Message)"
        
        # Restore backup if update failed
        if (Test-Path "$InstallPath\syncthing.exe.bak") {
            Copy-Item "$InstallPath\syncthing.exe.bak" "$InstallPath\syncthing.exe" -Force
            Write-Host "Restored previous version from backup" -ForegroundColor Yellow
        }
        
        Start-Syncthing
        return $false
    }
}

# Main script logic
Write-Host "Syncthing Auto-Update Script" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator. Some operations may fail."
}

# Get current and latest versions
$currentVersion = Get-CurrentSyncthingVersion
$latestVersion = Get-LatestSyncthingVersion

if (-not $latestVersion) {
    Write-Error "Could not fetch latest version information. Exiting."
    exit 1
}

Write-Host "Current version: $(if ($currentVersion) { $currentVersion } else { 'Not found' })" -ForegroundColor White
Write-Host "Latest version:  $latestVersion" -ForegroundColor White

# Check if update is needed
if ($currentVersion -eq $latestVersion -and -not $Force) {
    Write-Host "Syncthing is already up to date!" -ForegroundColor Green
    exit 0
}

if ($Force) {
    Write-Host "Force update requested..." -ForegroundColor Yellow
}
else {
    Write-Host "Update available!" -ForegroundColor Yellow
}

# Prompt for confirmation unless Force is specified
if (-not $Force) {
    $confirmation = Read-Host "Do you want to update to v$latestVersion? (y/N)"
    if ($confirmation -notmatch '^[Yy]') {
        Write-Host "Update cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Perform the update
$success = Update-Syncthing -Version $latestVersion

if ($success) {
    Write-Host "`nUpdate completed successfully!" -ForegroundColor Green
    Write-Host "Syncthing has been updated to v$latestVersion" -ForegroundColor Green
}
else {
    Write-Host "`nUpdate failed!" -ForegroundColor Red
    exit 1
}
