#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# FSR-Stack Packager
# Exports Felipe's personal skill collection as a shareable zip,
# with pre-flight secret scanning to guarantee nothing leaks.
# BSD/macOS bash compatible.
# ============================================================

# --- Header banner ---
cat <<'BANNER'
============================================================
  FSR-Stack Packager
  Package & sanitize .claude/skills for safe distribution
============================================================
BANNER

# --- Resolve workspace root from script location (no realpath/readlink -f) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"

# --- Output path (optional first arg, default = Desktop with timestamp) ---
DEFAULT_OUTPUT="$HOME/Desktop/fsr-stack-$(date +%Y%m%d-%H%M%S).zip"
OUTPUT_PATH="${1:-$DEFAULT_OUTPUT}"

# Normalize output to absolute path (expand ~ and relative paths)
case "$OUTPUT_PATH" in
    /*) ;;                                            # already absolute
    ~*) OUTPUT_PATH="${OUTPUT_PATH/#\~/$HOME}" ;;     # expand leading tilde
    *)  OUTPUT_PATH="$(pwd)/$OUTPUT_PATH" ;;          # relative -> absolute
esac

echo "Workspace root : $WORKSPACE_ROOT"
echo "Output path    : $OUTPUT_PATH"
echo ""

# --- Verify source skills directory exists ---
SKILLS_SRC="$WORKSPACE_ROOT/skills"
if [ ! -d "$SKILLS_SRC" ]; then
    echo "ERROR: Skills directory not found at: $SKILLS_SRC" >&2
    exit 1
fi

# --- Create temp working directory ---
STAGE_DIR="$(mktemp -d -t fsr-stack-export)"

# --- Trap cleanup on any exit (success or failure) ---
cleanup() {
    if [ -n "${STAGE_DIR:-}" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
    fi
}
trap cleanup EXIT INT TERM

echo "Staging dir    : $STAGE_DIR"
echo ""

# --- Copy skills directory ---
echo "[1/6] Copying skills..."
cp -R "$SKILLS_SRC" "$STAGE_DIR/skills"

# --- Copy supporting files (if present) ---
echo "[2/6] Copying supporting files..."
copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "       + $(basename "$src")"
    fi
}
copy_if_exists "$WORKSPACE_ROOT/.env.example"                       "$STAGE_DIR/.env.example"
copy_if_exists "$WORKSPACE_ROOT/mcp-servers.example.json"           "$STAGE_DIR/mcp-servers.example.json"
copy_if_exists "$WORKSPACE_ROOT/SETUP.md"                           "$STAGE_DIR/SETUP.md"
copy_if_exists "$WORKSPACE_ROOT/README.md"                          "$STAGE_DIR/README.md"

# --- SCAN 1: gitleaks ---
echo ""
echo "[3/6] SCAN 1 - gitleaks..."
GITLEAKS_RAN=0
if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks detect --source "$STAGE_DIR" --no-git --verbose --redact; then
        echo ""
        echo "ERROR: gitleaks detected secrets in the staged package." >&2
        echo "       Review the output above, remove the offending values, and re-run." >&2
        exit 1
    fi
    GITLEAKS_RAN=1
    echo "       gitleaks: clean"
else
    echo "       WARNING: gitleaks not found."
    echo "       Install it with 'brew install gitleaks' for pre-flight secret scanning."
    echo "       Continuing with SCAN 2 only."
fi

# --- SCAN 2: custom grep for common secret patterns ---
echo ""
echo "[4/6] SCAN 2 - custom secret pattern grep..."

# Extended regex patterns (BSD grep -E compatible, no PCRE).
# Each pattern on its own line; we OR-join with '|' below.
# Patterns are tightened to avoid matching obvious placeholder values
# like "xoxb-your-bot-token" or "sk-your-openai-key-here".
PATTERNS=(
    'apify_api_[A-Za-z0-9]{20,}'
    'pat[A-Za-z0-9]{14,}\.[A-Za-z0-9]{64,}'
    'xox[baprs]-[0-9]{10,}-[0-9]{10,}-[A-Za-z0-9]{20,}'
    'sk-[A-Za-z0-9]{40,}'
    'Bearer [A-Za-z0-9+/=_-]{40,}'
    'AKIA[0-9A-Z]{16}'
)

# Join patterns with | for a single -E pass
JOINED=""
for p in "${PATTERNS[@]}"; do
    if [ -z "$JOINED" ]; then
        JOINED="$p"
    else
        JOINED="$JOINED|$p"
    fi
done

# -r recursive, -E extended regex, -n line number, -H filename, -I skip binary,
# --exclude .DS_Store to avoid noise. Disable set -e for this grep call because
# grep returns 1 when no matches (which is the success case for us).
set +e
MATCHES="$(grep -rEnIH --exclude='.DS_Store' "$JOINED" "$STAGE_DIR" 2>/dev/null)"
GREP_RC=$?
set -e

if [ $GREP_RC -eq 0 ] && [ -n "$MATCHES" ]; then
    echo ""
    echo "ERROR: Custom secret scan found potential secrets:" >&2
    echo "$MATCHES" >&2
    echo ""
    echo "Refusing to package. Clean the source files and re-run." >&2
    exit 1
fi
echo "       custom patterns: clean"

# --- Build an exclude list for zip (mirrors .gitignore + noise) ---
echo ""
echo "[5/6] Creating zip archive..."

# Ensure output directory exists
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"

# Remove any existing zip at the target path (idempotent)
rm -f "$OUTPUT_PATH"

# Build zip from the stage dir. Excludes: .DS_Store anywhere, any nested .env,
# node_modules, mcp-servers.json (real one), .sessions.json, .git, attachments,
# and .astronaut-state. These mirror the workspace .gitignore for safety.
(
    cd "$STAGE_DIR"
    zip -rq "$OUTPUT_PATH" . \
        -x "*.DS_Store" \
           "*/.DS_Store" \
           "*/.env" \
           ".env" \
           "*/node_modules/*" \
           "node_modules/*" \
           "*/mcp-servers.json" \
           "mcp-servers.json" \
           "*/.sessions.json" \
           ".sessions.json" \
           "*/.git/*" \
           ".git/*" \
           "*/attachments/*" \
           "*/.astronaut-state/*"
)

if [ ! -f "$OUTPUT_PATH" ]; then
    echo "ERROR: zip command did not produce an archive at $OUTPUT_PATH" >&2
    exit 1
fi

# --- Summary ---
echo ""
echo "[6/6] Computing checksum & summary..."

SHA256="$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
SIZE_HUMAN="$(du -h "$OUTPUT_PATH" | awk '{print $1}')"
FILE_COUNT="$(unzip -l "$OUTPUT_PATH" | tail -1 | awk '{print $2}')"

echo ""
echo "============================================================"
echo "  PACKAGE READY"
echo "============================================================"
echo "  Output : $OUTPUT_PATH"
echo "  Size   : $SIZE_HUMAN"
echo "  Files  : $FILE_COUNT"
echo "  SHA256 : $SHA256"
echo "============================================================"
echo ""
if [ "$GITLEAKS_RAN" -eq 1 ]; then
    echo "Safe to share. Both gitleaks and custom pattern scans passed."
else
    echo "Package created. Custom scan passed; gitleaks was not installed."
fi
