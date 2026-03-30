<#
.SYNOPSIS
    Interactive Feedback MCP - One-click installer for Antigravity IDE (Windows)
.DESCRIPTION
    This script automatically:
    1. Clones the repository to %USERPROFILE%\interactive-feedback-mcp
    2. Installs dependencies via uv
    3. Configures MCP server in Antigravity IDE
    4. Adds global coding rules for optimal usage
.NOTES
    Usage: irm https://raw.githubusercontent.com/nhatpse/Antigravity-MCP/main/install.ps1 | iex
#>

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step { param([string]$msg) Write-Host "`n=> $msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$msg) Write-Host "   [OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "   [!] $msg" -ForegroundColor Yellow }
function Write-Err { param([string]$msg) Write-Host "   [X] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "=============================================" -ForegroundColor Magenta
Write-Host "  Interactive Feedback MCP - Installer" -ForegroundColor Magenta
Write-Host "  github.com/nhatpse/Antigravity-MCP" -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Magenta

# --- Configuration ---
$REPO_URL = "https://github.com/nhatpse/Antigravity-MCP.git"
$INSTALL_DIR = Join-Path $env:USERPROFILE "interactive-feedback-mcp"
$GEMINI_DIR = Join-Path $env:USERPROFILE ".gemini"
$ANTIGRAVITY_DIR = Join-Path $GEMINI_DIR "antigravity"
$MCP_CONFIG_FILE = Join-Path $ANTIGRAVITY_DIR "mcp_config.json"
$GEMINI_MD_FILE = Join-Path $GEMINI_DIR "GEMINI.md"

$CODING_RULE = @"
Whenever you want to ask a question, always call the MCP interactive_feedback.
Whenever you're about to complete a user request, call the MCP interactive_feedback instead of simply ending the process. Keep calling MCP until the user's feedback is empty, then end the request.
"@

# --- Step 1: Check prerequisites ---
Write-Step "Checking prerequisites..."

# Check Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Err "Git is not installed. Please install Git first: https://git-scm.com/downloads"
    exit 1
}
Write-Ok "Git found"

# Check/Install uv
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
    Write-Warn "uv not found. Installing uv standalone installer..."
    try {
        Invoke-Expression (Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1")
        
        # Add to current path for immediate use
        $env:Path += ";$env:USERPROFILE\.local\bin"
        
        $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
        if (-not $uvCmd) {
            throw "uv still not found after standalone install"
        }
        Write-Ok "uv installed successfully"
    } catch {
        Write-Err "Failed to install uv. Please install manually: https://docs.astral.sh/uv/"
        exit 1
    }
} else {
    Write-Ok "uv found at: $($uvCmd.Source)"
}

$UV_PATH = $uvCmd.Source

# --- Step 2: Clone or update repository ---
Write-Step "Setting up repository..."

if (Test-Path $INSTALL_DIR) {
    Write-Warn "Directory already exists: $INSTALL_DIR"
    $response = Read-Host "   Overwrite? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "   Using existing installation." -ForegroundColor Gray
    } else {
        Remove-Item -Recurse -Force $INSTALL_DIR
        $proc = Start-Process git -ArgumentList "clone", "-q", $REPO_URL, $INSTALL_DIR -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -ne 0) { throw "Failed to clone repository" }
        Write-Ok "Repository cloned to: $INSTALL_DIR"
    }
} else {
    $proc = Start-Process git -ArgumentList "clone", "-q", $REPO_URL, $INSTALL_DIR -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) { throw "Failed to clone repository" }
    Write-Ok "Repository cloned to: $INSTALL_DIR"
}

# --- Step 3: Install Python dependencies ---
Write-Step "Installing Python dependencies..."

Push-Location $INSTALL_DIR
try {
    $proc = Start-Process $UV_PATH -ArgumentList "sync" -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) { throw "uv sync failed" }
    Write-Ok "Dependencies installed"
} catch {
    Write-Err "Failed to install dependencies: $_"
    Pop-Location
    exit 1
}
Pop-Location

# --- Step 4: Configure MCP server in Antigravity ---
Write-Step "Configuring MCP server in Antigravity..."

# Ensure directories exist
if (-not (Test-Path $ANTIGRAVITY_DIR)) {
    New-Item -ItemType Directory -Path $ANTIGRAVITY_DIR -Force | Out-Null
}

# Build the MCP server entry
$mcpEntry = @{
    command = $UV_PATH
    args = @(
        "--directory"
        $INSTALL_DIR
        "run"
        "server.py"
    )
}

if (Test-Path $MCP_CONFIG_FILE) {
    # Read existing config
    $content = Get-Content $MCP_CONFIG_FILE -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        $config = [PSCustomObject]@{}
    } else {
        $config = $content | ConvertFrom-Json
    }

    # Ensure $config is an object if parsing somehow returned primitive
    if (-not $config) {
        $config = [PSCustomObject]@{}
    }

    # Ensure mcpServers object exists
    if (-not $config.mcpServers) {
        $config | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
    }

    # Check if already configured
    if ($config.mcpServers."interactive-feedback-mcp") {
        Write-Warn "MCP server already configured. Updating..."
    }

    # Add/Update the entry
    $config.mcpServers | Add-Member -NotePropertyName "interactive-feedback-mcp" -NotePropertyValue ([PSCustomObject]$mcpEntry) -Force

    $jsonOut = $config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($MCP_CONFIG_FILE, $jsonOut)
} else {
    # Create new config
    $config = @{
        mcpServers = @{
            "interactive-feedback-mcp" = $mcpEntry
        }
    }
    $jsonOut = $config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($MCP_CONFIG_FILE, $jsonOut)
}

Write-Ok "MCP config updated: $MCP_CONFIG_FILE"

# --- Step 5: Add global coding rules ---
Write-Step "Adding global coding rules..."

if (-not (Test-Path $GEMINI_DIR)) {
    New-Item -ItemType Directory -Path $GEMINI_DIR -Force | Out-Null
}

if (Test-Path $GEMINI_MD_FILE) {
    $existingContent = Get-Content $GEMINI_MD_FILE -Raw
    if ($existingContent -like "*interactive_feedback*") {
        Write-Warn "Coding rules already contain interactive_feedback reference. Skipping."
    } else {
        # Append the coding rules
        Add-Content -Path $GEMINI_MD_FILE -Value "`n$CODING_RULE"
        Write-Ok "Coding rules appended to: $GEMINI_MD_FILE"
    }
} else {
    Set-Content -Path $GEMINI_MD_FILE -Value $CODING_RULE -Encoding UTF8
    Write-Ok "Coding rules created: $GEMINI_MD_FILE"
}

# --- Done ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install path : $INSTALL_DIR" -ForegroundColor Gray
Write-Host "  MCP config   : $MCP_CONFIG_FILE" -ForegroundColor Gray
Write-Host "  Coding rules : $GEMINI_MD_FILE" -ForegroundColor Gray
Write-Host ""
Write-Host "  Please restart Antigravity IDE to apply changes." -ForegroundColor Yellow
Write-Host ""
