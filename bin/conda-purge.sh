#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

MAC_SCRIPT="$REPO_ROOT/scripts/purge_conda_macos.sh"
LINUX_SCRIPT="$REPO_ROOT/scripts/purge_conda_linux.sh"
WIN_SCRIPT_PS="$REPO_ROOT/scripts/Purge-CondaWindows.ps1"

require() {
    local p="$1"
    [[ -f "$p" ]] || { echo "Error: missing script: $p" >&2; exit 2; }
}

run_or_bash() {
    local script="$1"
    shift
    if [[ -x "$script" ]]; then 
        exec "$script" "$@"
    else 
        exec bash "$script" "$@"
    fi
}

translate_args_for_windows() {
    local out=()
    for a in "$@"; do
        case "$a" in
            --yes) out+=("-Yes");;
            --force) out+=("-Force");;
            --quiet) out+=("-Quiet");;
            --json) out+=("-Json");;
            --include-forge) out+=("-IncludeForge");;
            --include-micromamba) out+=("-IncludeMicromamba");;
            --system) out+=("-System");;
            --dry-run) ;; # PS is dry-run by default
            -h|--help) out+=("-?");;
            *) out+=("$a");;
        esac
    done
    printf '%s\n' "${out[@]}"
}

detect_platform() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"
    
    case "$uname_s" in
        Darwin) echo "macos";;
        Linux) echo "linux";;
        MINGW*|MSYS*|CYGWIN*) echo "windows";;
        *) echo "unknown";;
    esac
}

main() {
    local platform
    platform="$(detect_platform)"
    
    case "$platform" in
        macos)
            require "$MAC_SCRIPT"
            run_or_bash "$MAC_SCRIPT" "$@"
            ;;
        linux)
            # WSL hint (optional)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "ℹ️  WSL detected. This cleans Linux env only. To clean Windows PATH/profiles, run bin/conda-purge.ps1 in Windows PowerShell." >&2
            fi
            require "$LINUX_SCRIPT"
            run_or_bash "$LINUX_SCRIPT" "$@"
            ;;
        windows)
            require "$WIN_SCRIPT_PS"
            # Prefer PowerShell 7 if present, else Windows PowerShell
            ps_exe=""
            if command -v pwsh.exe >/dev/null 2>&1; then
              ps_exe="pwsh.exe"
            elif command -v powershell.exe >/dev/null 2>&1; then
              ps_exe="powershell.exe"
            fi

            if [[ -n "$ps_exe" ]]; then
              mapfile -t MAPPED < <(translate_args_for_windows "$@")
              exec "$ps_exe" -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT_PS" "${MAPPED[@]}"
            else
              echo "Error: pwsh.exe/powershell.exe not found. Use bin/conda-purge.ps1 from Windows PowerShell." >&2
              exit 1
            fi
            ;;
        *)
            # fallback try
            if [[ -f "$MAC_SCRIPT" ]]; then 
                run_or_bash "$MAC_SCRIPT" "$@"
            elif [[ -f "$LINUX_SCRIPT" ]]; then 
                run_or_bash "$LINUX_SCRIPT" "$@"
            else
                echo "Unsupported OS ($(uname -s)). Could not locate a platform script." >&2
                exit 2
            fi
            ;;
    esac
}

main "$@"