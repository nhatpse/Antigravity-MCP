#!/usr/bin/env bash
# =============================================
#  Interactive Feedback MCP - Installer
#  github.com/nhatpse/Antigravity-MCP
# =============================================
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nhatpse/Antigravity-MCP/main/install.sh | bash
#   (or)
#   wget -qO- https://raw.githubusercontent.com/nhatpse/Antigravity-MCP/main/install.sh | bash

set -euo pipefail

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

step()  { echo -e "\n${CYAN}=> $1${NC}"; }
ok()    { echo -e "   ${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "   ${YELLOW}[!]${NC} $1"; }
err()   { echo -e "   ${RED}[X]${NC} $1"; }

echo ""
echo -e "${MAGENTA}=============================================${NC}"
echo -e "${MAGENTA}  Interactive Feedback MCP - Installer${NC}"
echo -e "${GRAY}  github.com/nhatpse/Antigravity-MCP${NC}"
echo -e "${MAGENTA}=============================================${NC}"

# --- Configuration ---
REPO_URL="https://github.com/nhatpse/Antigravity-MCP.git"
INSTALL_DIR="$HOME/interactive-feedback-mcp"
GEMINI_DIR="$HOME/.gemini"
ANTIGRAVITY_DIR="$GEMINI_DIR/antigravity"
MCP_CONFIG_FILE="$ANTIGRAVITY_DIR/mcp_config.json"
GEMINI_MD_FILE="$GEMINI_DIR/GEMINI.md"

CODING_RULE='Whenever you want to ask a question, always call the MCP interactive_feedback (exact tool name: mcp_interactive-feedback-mcp_interactive_feedback).
Whenever you'\''re about to complete a user request, call the MCP interactive_feedback instead of simply ending the process. Keep calling MCP until the user'\''s feedback is empty, then end the request.'

# --- Step 1: Check prerequisites ---
step "Checking prerequisites..."

# Check Git
if ! command -v git &> /dev/null; then
    err "Git is not installed. Please install Git first."
    exit 1
fi
ok "Git found"

# Check/Install uv
if ! command -v uv &> /dev/null; then
    warn "uv not found. Installing standalone uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 > /dev/null
    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v uv &> /dev/null; then
        err "Failed to install uv. Please install manually: https://docs.astral.sh/uv/"
        exit 1
    fi
    ok "uv installed successfully"
else
    ok "uv found at: $(which uv)"
fi

UV_PATH="$(which uv)"

# --- Step 2: Clone or update repository ---
step "Setting up repository..."

if [ -d "$INSTALL_DIR" ]; then
    warn "Directory already exists: $INSTALL_DIR"
    read -r -p "   Overwrite? (y/N) " response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        rm -rf "$INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 > /dev/null
        ok "Repository cloned to: $INSTALL_DIR"
    else
        echo "   Using existing installation."
    fi
else
    git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 > /dev/null
    ok "Repository cloned to: $INSTALL_DIR"
fi

# --- Step 3: Install Python dependencies ---
step "Installing Python dependencies..."

cd "$INSTALL_DIR"
"$UV_PATH" sync 2>&1 > /dev/null
ok "Dependencies installed"
cd - > /dev/null

# --- Step 4: Configure MCP server in Antigravity ---
step "Configuring MCP server in Antigravity..."

mkdir -p "$ANTIGRAVITY_DIR"

MCP_ENTRY=$(cat <<EOF
{
  "mcpServers": {
    "interactive-feedback-mcp": {
      "command": "$UV_PATH",
      "args": [
        "--directory",
        "$INSTALL_DIR",
        "run",
        "server.py"
      ]
    }
  }
}
EOF
)

if [ -f "$MCP_CONFIG_FILE" ]; then
    # Check if jq is available for proper JSON merging
    if command -v jq &> /dev/null; then
        EXISTING=$(cat "$MCP_CONFIG_FILE")
        MERGED=$(echo "$EXISTING" | jq --argjson entry "$MCP_ENTRY" '
            .mcpServers["interactive-feedback-mcp"] = $entry.mcpServers["interactive-feedback-mcp"]
        ')
        echo "$MERGED" > "$MCP_CONFIG_FILE"
        ok "MCP config updated (merged with existing): $MCP_CONFIG_FILE"
    else
        # Without jq, check if already configured
        if grep -q "interactive-feedback-mcp" "$MCP_CONFIG_FILE"; then
            warn "MCP config already contains interactive-feedback-mcp entry."
            warn "Please verify manually: $MCP_CONFIG_FILE"
        else
            warn "jq not found. Cannot merge JSON safely."
            warn "Please manually add the MCP entry to: $MCP_CONFIG_FILE"
            echo ""
            echo "$MCP_ENTRY"
            echo ""
        fi
    fi
else
    echo "$MCP_ENTRY" > "$MCP_CONFIG_FILE"
    ok "MCP config created: $MCP_CONFIG_FILE"
fi

# --- Step 5: Add global coding rules ---
step "Adding global coding rules..."

mkdir -p "$GEMINI_DIR"

if [ -f "$GEMINI_MD_FILE" ]; then
    if grep -q "interactive_feedback" "$GEMINI_MD_FILE"; then
        warn "Coding rules already contain interactive_feedback reference. Skipping."
    else
        echo "" >> "$GEMINI_MD_FILE"
        echo "$CODING_RULE" >> "$GEMINI_MD_FILE"
        ok "Coding rules appended to: $GEMINI_MD_FILE"
    fi
else
    echo "$CODING_RULE" > "$GEMINI_MD_FILE"
    ok "Coding rules created: $GEMINI_MD_FILE"
fi

# --- Done ---
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "  Install path : ${GRAY}$INSTALL_DIR${NC}"
echo -e "  MCP config   : ${GRAY}$MCP_CONFIG_FILE${NC}"
echo -e "  Coding rules : ${GRAY}$GEMINI_MD_FILE${NC}"
echo ""
echo -e "  ${YELLOW}Please restart Antigravity IDE to apply changes.${NC}"
echo ""
