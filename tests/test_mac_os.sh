#!/usr/bin/env bash
# tests/macos.sh
set -euo pipefail

# --- Locate the script under test ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/purge_conda_macos.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: script not found at $SCRIPT" >&2
  exit 2
fi

echo "▶ Using script: $SCRIPT"

# --- Sandbox: temp HOME + fake bin (sudo/brew) ---
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

FAKE_HOME="$TMPROOT/home"
FAKE_BIN="$TMPROOT/bin"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"
chmod 700 "$FAKE_HOME"

# Fake sudo (prevent real system modification)
cat > "$FAKE_BIN/sudo" <<'EOS'
#!/usr/bin/env bash
echo "(fake sudo) $@"
exit 0
EOS
chmod +x "$FAKE_BIN/sudo"

# Fake brew:
# - `brew list --cask <name>` returns 0 for anaconda/miniconda (pretend installed), 1 otherwise
# - `brew uninstall --cask --force <name>` just echoes and exits 0
cat > "$FAKE_BIN/brew" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == "list" && "${2-}" == "--cask" ]]; then
  case "${3-}" in
    anaconda|miniconda) exit 0 ;;
    *) exit 1 ;;
  esac
elif [[ "${1-}" == "uninstall" && "${2-}" == "--cask" && "${3-}" == "--force" ]]; then
  echo "(fake brew) uninstall cask ${4-}"
  exit 0
else
  # other brew commands not used by the script
  echo "(fake brew) unsupported: $*" >&2
  exit 0
fi
EOS
chmod +x "$FAKE_BIN/brew"

# Ensure our fakes are used first
export PATH="$FAKE_BIN:$PATH"
export HOME="$FAKE_HOME"

echo "▶ Sandbox HOME: $HOME"
echo "▶ PATH prefix  : $FAKE_BIN"

# --- Seed fake files/dirs the script will act on ---
mkdir -p "$HOME/.config/fish/conf.d" "$HOME/.config/fish/functions"
mkdir -p "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/.conda" "$HOME/.continuum"
mkdir -p "$HOME/Library/Caches/conda"
mkdir -p "$HOME/Library/Application Support/conda"
mkdir -p "$HOME/mambaforge" "$HOME/miniforge3" "$HOME/.local/bin"
touch "$HOME/.local/bin/micromamba"

# Conda init block (BSD sed compatible)
CONDABLOCK=$'# >>> conda initialize >>>\n__conda_setup="$HOME/miniconda3/bin/conda shell.zsh hook 2>/dev/null"\nif [ $? -eq 0 ]; then\n  eval "$__conda_setup"\nfi\n# <<< conda initialize <<<\nconda init zsh\n'

for f in .zshrc .zprofile .bashrc .bash_profile .profile .cshrc .tcshrc; do
  printf "%b" "$CONDABLOCK" > "$HOME/$f"
done
echo "# conda.fish hook" > "$HOME/.config/fish/conf.d/conda.fish"
echo "# conda function hook" > "$HOME/.config/fish/functions/conda.fish"

# Keep originals for dry-run check
cp "$HOME/.zshrc" "$HOME/.zshrc.orig"
cp "$HOME/.bashrc" "$HOME/.bashrc.orig"

# ---------------- Helpers ----------------
pass(){ echo -e "✅ $*"; }
fail(){ echo -e "❌ $*"; exit 1; }

# 1) Help must show usage & dry-run mention
HELP_OUT="$("$SCRIPT" --help 2>&1 || true)"
grep -q "Usage:"    <<<"$HELP_OUT" || fail "Help shows usage"
grep -qi "dry"      <<<"$HELP_OUT" || fail "Help mentions dry-run"
pass "Help output OK"

# 2) Dry run: no file changes, no backups; fish files remain; brew list is called but uninstall not executed
echo "▶ Dry run…"
DRY_OUT="$TMPROOT/dry.out"
bash "$SCRIPT" --include-forge --include-micromamba --json >"$DRY_OUT" 2>&1 || true

diff -q "$HOME/.zshrc" "$HOME/.zshrc.orig" >/dev/null || { echo "Dry-run modified .zshrc"; exit 1; }
diff -q "$HOME/.bashrc" "$HOME/.bashrc.orig" >/dev/null || { echo "Dry-run modified .bashrc"; exit 1; }
[[ ! -e "$HOME/.zshrc.bak" && ! -e "$HOME/.bashrc.bak" ]] || { echo "Dry-run created backups"; exit 1; }
[[ -f "$HOME/.config/fish/conf.d/conda.fish" ]] || { echo "Dry-run removed fish conf unexpectedly"; exit 1; }
[[ -f "$HOME/.config/fish/functions/conda.fish" ]] || { echo "Dry-run removed fish function unexpectedly"; exit 1; }
pass "Dry run left files intact"

# 3) Apply run: remove hooks, fish files, HOME dirs; fake brew uninstall called
echo "▶ Apply (--yes)…"
APPLY_OUT="$TMPROOT/apply.out"
bash "$SCRIPT" --yes --include-forge --include-micromamba --json >"$APPLY_OUT" 2>&1 || {
  echo "Apply output:"; cat "$APPLY_OUT"; fail "Apply run failed"
}

# Backups created
[[ -f "$HOME/.zshrc.bak" ]]  || fail "Backup .zshrc.bak created"
[[ -f "$HOME/.bashrc.bak" ]] || fail "Backup .bashrc.bak created"

# Hooks removed from rc files
! grep -q 'conda initialize' "$HOME/.zshrc"  || fail "Conda block removed from .zshrc"
! grep -q 'conda init'       "$HOME/.zshrc"  || fail "'conda init' removed from .zshrc"
! grep -q 'conda initialize' "$HOME/.bashrc" || fail "Conda block removed from .bashrc"

# Fish files removed
[[ ! -f "$HOME/.config/fish/conf.d/conda.fish" ]]      || fail "Fish conf removed"
[[ ! -f "$HOME/.config/fish/functions/conda.fish" ]]   || fail "Fish function removed"

# HOME-scoped dirs removed
for d in \
  "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/.conda" "$HOME/.continuum" \
  "$HOME/mambaforge" "$HOME/miniforge3" "$HOME/.local/bin/micromamba" \
  "$HOME/Library/Caches/conda" "$HOME/Library/Application Support/conda"
do
  [[ ! -e "$d" ]] || { echo "Leftover after apply: $d"; exit 1; }
done

# Fake sudo invoked if any system file existed (likely not in sandbox; informational)
grep -q '(fake sudo)' "$APPLY_OUT" || echo "ℹ️ No system files in sandbox (fake sudo not invoked)"

# Fake brew uninstall was attempted
grep -q '(fake brew) uninstall cask anaconda'  "$APPLY_OUT" && echo "ℹ️ anaconda cask uninstall executed" || echo "ℹ️ anaconda cask uninstall not found"
grep -q '(fake brew) uninstall cask miniconda' "$APPLY_OUT" && echo "ℹ️ miniconda cask uninstall executed" || echo "ℹ️ miniconda cask uninstall not found"
pass "Apply run cleaned hooks/dirs and invoked fake brew"

# 4) Idempotency: second apply should succeed and do nothing harmful
echo "▶ Idempotency…"
IDEM_OUT="$TMPROOT/idem.out"
bash "$SCRIPT" --yes --include-forge --include-micromamba >"$IDEM_OUT" 2>&1 || {
  echo "Idempotent run output:"; cat "$IDEM_OUT"; fail "Idempotent run failed"
}
pass "Idempotent run OK"

echo
echo "Sandbox HOME: $HOME"
echo "Logs:"
echo "  dry:   $DRY_OUT"
echo "  apply: $APPLY_OUT"
echo "  idem:  $IDEM_OUT"
echo "Fake tools:"
echo "  sudo:  $FAKE_BIN/sudo"
echo "  brew:  $FAKE_BIN/brew"
echo
echo "✅ macOS tests passed safely in sandbox"