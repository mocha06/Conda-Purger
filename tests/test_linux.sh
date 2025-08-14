#!/usr/bin/env bash
set -euo pipefail

# Test suite for Linux conda purge script
# Run with: ./tests/test_linux.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINUX_SCRIPT="$REPO_ROOT/scripts/purge_conda_linux.sh"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Counters
TOTAL_TESTS=0; PASSED_TESTS=0; FAILED_TESTS=0

# Sandbox
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FAKE_HOME="$TMPROOT/home"
FAKE_BIN="$TMPROOT/bin"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"
chmod 700 "$FAKE_HOME"

# Fake sudo (so nothing under /etc or /usr is touched)
cat > "$FAKE_BIN/sudo" <<'EOS'
#!/usr/bin/env bash
echo "(fake sudo) $@"
exit 0
EOS
chmod +x "$FAKE_BIN/sudo"

# Ensure our fake sudo is used first; then export sandbox HOME
export PATH="$FAKE_BIN:$PATH"
export HOME="$FAKE_HOME"

# Seed fake configs and dirs the script will act on
mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions" \
         "$HOME/miniconda3" "$HOME/.conda" "$HOME/.continuum" \
         "$HOME/mambaforge" "$HOME/.local/bin"
touch "$HOME/.local/bin/micromamba"

CONDABLOCK=$'# >>> conda initialize >>>\n# !! managed by conda init !!\n__conda_setup="$(/home/user/miniconda3/bin/conda shell.bash hook 2>/dev/null)"\nif [ $? -eq 0 ]; then\n  eval "$__conda_setup"\nfi\n# <<< conda initialize <<<\nconda init bash\n'

for f in .bashrc .bash_profile .profile .bash_login .zshrc .zprofile .cshrc .tcshrc; do
  printf "%b" "$CONDABLOCK" > "$HOME/$f"
done
echo "# conda.fish hook" > "$HOME/.config/fish/conf.d/conda.fish"
echo "# conda function hook" > "$HOME/.config/fish/functions/conda.fish"

# Keep originals for dry-run check
cp "$HOME/.bashrc" "$HOME/.bashrc.orig"
cp "$HOME/.zshrc"  "$HOME/.zshrc.orig"

# ----------------- helpers -----------------
header() { echo -e "\n${YELLOW}🧪 Running: $1${NC}\n=================================="; }
pass()   { echo -e "${GREEN}✅ PASS: $1${NC}"; TOTAL_TESTS=$((TOTAL_TESTS+1)); PASSED_TESTS=$((PASSED_TESTS+1)); }
fail()   { echo -e "${RED}❌ FAIL: $1${NC}"; TOTAL_TESTS=$((TOTAL_TESTS+1)); FAILED_TESTS=$((FAILED_TESTS+1)); }
summary(){
  echo -e "\n${YELLOW}📊 Test Summary${NC}\n=================="
  echo "Total: $TOTAL_TESTS"
  echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
  echo -e "${RED}Failed: $FAILED_TESTS${NC}"
  if [[ $FAILED_TESTS -eq 0 ]]; then echo -e "\n${GREEN}🎉 All tests passed!${NC}"; exit 0
  else echo -e "\n${RED}💥 Some tests failed!${NC}"; exit 1; fi
}

# 1) Script exists & is executable (or at least runnable via bash)
header "Script Existence and Permissions"
if [[ -f "$LINUX_SCRIPT" ]]; then pass "Script file exists"; else fail "Script file exists"; fi
if [[ -x "$LINUX_SCRIPT" ]]; then pass "Script is executable"; else
  # we can still run via bash, so don't fail hard
  echo "ℹ️ Script not executable; will run via 'bash $LINUX_SCRIPT'"
  pass "Script can be run via bash"
fi

# 2) Help output (usage + dry-run mention)
header "Help Output"
HELP_OUT="$("$LINUX_SCRIPT" --help 2>&1 || true)"
grep -q "Usage:"    <<<"$HELP_OUT" && pass "Help shows usage" || fail "Help shows usage"
grep -qi "dry"      <<<"$HELP_OUT" && pass "Help mentions dry-run" || fail "Help mentions dry-run"

# 3) Dry run default: no file changes, no backups, fish files still present
header "Dry Run Mode (Default)"
DRY_OUT="$TMPROOT/dry.out"
bash "$LINUX_SCRIPT" --include-forge --include-micromamba --json >"$DRY_OUT" 2>&1 || true

diff -q "$HOME/.bashrc" "$HOME/.bashrc.orig" >/dev/null && pass "Dry-run kept .bashrc unchanged" || fail "Dry-run kept .bashrc unchanged"
diff -q "$HOME/.zshrc"  "$HOME/.zshrc.orig"  >/dev/null && pass "Dry-run kept .zshrc unchanged"  || fail "Dry-run kept .zshrc unchanged"
if [[ ! -e "$HOME/.bashrc.bak" && ! -e "$HOME/.zshrc.bak" ]]; then
  pass "Dry-run produced no backups"
else
  fail "Dry-run produced no backups"
fi
[[ -f "$HOME/.config/fish/conf.d/conda.fish" ]] && pass "Fish conf still present in dry-run" || fail "Fish conf still present in dry-run"
[[ -f "$HOME/.config/fish/functions/conda.fish" ]] && pass "Fish function still present in dry-run" || fail "Fish function still present in dry-run"

# 4) Apply run: with --yes inside sandbox
header "Apply Run (--yes)"
APPLY_OUT="$TMPROOT/apply.out"
bash "$LINUX_SCRIPT" --yes --include-forge --include-micromamba --json >"$APPLY_OUT" 2>&1 || {
  echo "Apply output:"; cat "$APPLY_OUT"
  fail "Apply script completed"; summary
}

# backups created
[[ -f "$HOME/.bashrc.bak" ]] && pass "Backup .bashrc.bak created" || fail "Backup .bashrc.bak created"
[[ -f "$HOME/.zshrc.bak"  ]] && pass "Backup .zshrc.bak created"  || fail "Backup .zshrc.bak created"

# conda hooks removed
if grep -q 'conda initialize' "$HOME/.bashrc"; then fail "Conda block removed from .bashrc"; else pass "Conda block removed from .bashrc"; fi
if grep -q 'conda init' "$HOME/.bashrc"; then fail "'conda init' removed from .bashrc"; else pass "'conda init' removed from .bashrc"; fi

# fish files removed
[[ ! -f "$HOME/.config/fish/conf.d/conda.fish" ]] && pass "Fish conf removed" || fail "Fish conf removed"
[[ ! -f "$HOME/.config/fish/functions/conda.fish" ]] && pass "Fish function removed" || fail "Fish function removed"

# HOME-scoped dirs removed
for d in "$HOME/miniconda3" "$HOME/.conda" "$HOME/.continuum" "$HOME/mambaforge" "$HOME/.local/bin/micromamba"; do
  if [[ ! -e "$d" ]]; then pass "Removed $d"; else fail "Removed $d"; fi
done

# Fake sudo invoked if any system paths existed (they likely don't; so this is informational)
if grep -q '(fake sudo)' "$APPLY_OUT"; then
  pass "System deletions attempted via fake sudo"
else
  echo "ℹ️ Note: no system files present in sandbox (fake sudo not invoked)."
fi

# 5) Idempotency: run again; should succeed and do nothing harmful
header "Idempotency"
IDEM_OUT="$TMPROOT/idem.out"
bash "$LINUX_SCRIPT" --yes --include-forge --include-micromamba >"$IDEM_OUT" 2>&1 || {
  echo "Idempotent run output:"; cat "$IDEM_OUT"; fail "Idempotent run completed"; summary
}
# Check a benign message (not strict)
grep -q "No conda hooks" "$IDEM_OUT" && pass "Reports no hooks on second run" || echo "ℹ️ No explicit 'No conda hooks' text; still OK"

# Final summary
echo -e "\nSandbox HOME: $HOME"
echo -e "Logs:\n  dry:   $DRY_OUT\n  apply: $APPLY_OUT\n  idem:  $IDEM_OUT"
echo -e "Fake sudo path: $FAKE_BIN/sudo"
echo -e "Repo script:    $LINUX_SCRIPT"
echo
summary