#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script settings
DRY_RUN=1
FORGE=0
MICRO=0
QUIET=0
JSON=0
YES=0
FORCE=0

# File paths to check for conda hooks
SHELL_CONFIG_FILES=(
    "$HOME/.zshrc"
    "$HOME/.zprofile"
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.profile"
    "$HOME/.config/fish/config.fish"
    "$HOME/.cshrc"
    "$HOME/.tcshrc"
)

# Fish configuration files
FISH_CONFIG_FILES=(
    "$HOME/.config/fish/conf.d/conda.fish"
    "$HOME/.config/fish/functions/conda.fish"
)

# System profile scripts
SYSTEM_PROFILE_SCRIPTS=(
    "/etc/profile.d/conda.sh"
    "/etc/profile.d/conda.csh"
    "/usr/local/etc/profile.d/conda.sh"
    "/opt/homebrew/etc/profile.d/conda.sh"
    "/etc/fish/conf.d/conda.fish"
    "/usr/share/fish/vendor_conf.d/conda.fish"
)

# Conda directories to remove
CONDA_DIRECTORIES=(
    "$HOME/anaconda3"
    "$HOME/miniconda3"
    "$HOME/.conda"
    "$HOME/.condarc"
    "$HOME/.continuum"
    "$HOME/Library/Caches/conda"
    "$HOME/Library/Application Support/conda"
    "/usr/share/conda"
)

# Forge directories (optional)
FORGE_DIRECTORIES=(
    "$HOME/mambaforge"
    "$HOME/miniforge3"
)

# Micromamba directories (optional)
MICROMAMBA_DIRECTORIES=(
    "$HOME/micromamba"
    "$HOME/.local/bin/micromamba"
)

# Homebrew casks to uninstall
HOMEBREW_CASKS=(
    "anaconda"
    "miniconda"
)

# JSON output tracking
JSON_ITEMS=()

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print() { 
    [[ $QUIET -eq 0 ]] && printf "%s\n" "$*"; 
}

doit() { 
    if [[ $DRY_RUN -eq 1 ]]; then 
        print "(dry) $*"; 
    else 
        eval "$@"; 
    fi; 
}

add_json() {
    if [[ $JSON -eq 1 ]]; then
        # naive JSON escape of " and \  (good enough for paths/filenames)
        local esc="${1//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        JSON_ITEMS+=("$esc")
    fi
}
log_success() {
    print "   ✅ $1"
}

log_warning() {
    print "   ⚠️ $1"
}

log_info() {
    print "📄 $1"
}

log_section() {
    print "🗑 $1"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes] [--force] [--quiet] [--json] [--include-forge] [--include-micromamba]
Default is dry-run. Pass --yes to actually modify the system.
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes) YES=1; DRY_RUN=0;;
            --force) FORCE=1;;
            --quiet) QUIET=1;;
            --json) JSON=1;;
            --include-forge) FORGE=1;;
            --include-micromamba) MICRO=1;;
            -h|--help) usage; exit 0;;
            *) print "Unknown arg: $1"; usage; exit 2;;
        esac; 
        shift
    done
}

# =============================================================================
# FILE OPERATIONS
# =============================================================================

backup_edit_file() {
    local file="$1"
    
    [[ -f "$file" ]] || { 
        log_info "Skipping $file (not found)"; 
        return; 
    }
    
    log_info "Checking $file..."
    
    if grep -nE 'conda initialize|/conda\.sh|conda init|micromamba shell hook' "$file" >/dev/null 2>&1; then
        log_warning "Matches:"
        grep -nE 'conda initialize|/conda\.sh|conda init|micromamba shell hook' "$file" || true
        
        if [[ $DRY_RUN -eq 0 ]]; then
            cp "$file" "$file.bak"
            # BSD sed syntax
            sed -i '' \
                -e '/# >>> conda initialize >>>/,/# <<< conda initialize <<</d' \
                -e '/conda init/d' \
                -e '/\/etc\/profile\.d\/conda\.sh/d' \
                -e '/conda\.sh/d' \
                -e '/micromamba shell hook/d' \
                "$file"
        fi
        
        log_success "Cleaned (backup: $file.bak)"
        add_json "{\"file\":\"$file\",\"action\":\"cleaned\"}"
    else
        log_success "No conda hooks"
    fi
}

clean_shell_config_files() {
    log_section "Shell configuration files"
    for file in "${SHELL_CONFIG_FILES[@]}"; do 
        backup_edit_file "$file"; 
    done
}

clean_fish_config_files() {
    log_section "Fish configuration files"
    for fish_config in "${FISH_CONFIG_FILES[@]}"; do
        if [[ -f "$fish_config" ]]; then
            log_warning "Removing $fish_config"
            doit "rm -f '$fish_config'"
            add_json "{\"file\":\"$fish_config\",\"action\":\"removed\"}"
        fi
    done
}

# =============================================================================
# SYSTEM OPERATIONS
# =============================================================================

clean_system_profile_scripts() {
    log_section "System profile scripts"
    for profile_script in "${SYSTEM_PROFILE_SCRIPTS[@]}"; do
        if [[ -f "$profile_script" ]]; then
            log_warning "Removing $profile_script"
            if ! doit "sudo rm -f '$profile_script'"; then 
                [[ $FORCE -eq 1 ]] || exit 1; 
            fi
            add_json "{\"file\":\"$profile_script\",\"action\":\"removed\"}"
        else
            log_success "Not found: $profile_script"
        fi
    done
}

clean_directories() {
    log_section "Directories"

    local all_directories=("${CONDA_DIRECTORIES[@]}")

    if [[ $FORGE -eq 1 ]]; then
        all_directories+=("${FORGE_DIRECTORIES[@]}")
    fi
    if [[ $MICRO -eq 1 ]]; then
        all_directories+=("${MICROMAMBA_DIRECTORIES[@]}")
    fi

    for directory in "${all_directories[@]}"; do
        if [[ -e "$directory" ]]; then
            log_warning "Removing $directory"
            # Use sudo for anything outside $HOME
            if [[ "$directory" == "$HOME"* ]]; then
                if ! doit "rm -rf '$directory'"; then [[ $FORCE -eq 1 ]] || exit 1; fi
            else
                if ! doit "sudo rm -rf '$directory'"; then [[ $FORCE -eq 1 ]] || exit 1; fi
            fi
            add_json "{\"path\":\"$directory\",\"action\":\"removed\"}"
        else
            log_success "Not found: $directory"
        fi
    done
}


# =============================================================================
# HOMEBREW OPERATIONS
# =============================================================================

clean_homebrew_casks() {
    log_section "Homebrew casks"

    if ! command -v brew >/dev/null 2>&1; then
        log_info "Homebrew not found, skipping cask cleanup"
        return
    fi

    local removed_any=0
    for cask in "${HOMEBREW_CASKS[@]}"; do
        if brew list --cask "$cask" >/dev/null 2>&1; then
            log_warning "Uninstalling Homebrew cask: $cask"
            doit "brew uninstall --cask --force '$cask'"
            add_json "{\"brew_cask\":\"$cask\",\"action\":\"uninstalled\"}"
            removed_any=1
        fi
    done
    [[ $removed_any -eq 0 ]] && log_success "No anaconda/miniconda casks installed"
}

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

output_json() {
    if [[ $JSON -eq 1 ]]; then
        printf '[\n  %s\n]\n' "$(IFS=$',\n'; echo "${JSON_ITEMS[*]}")"
    fi
}

print_completion_message() {
    print "➡️  Restart your terminal (e.g., exec zsh)."
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    parse_arguments "$@"
    
    print "🧹 macOS conda cleanup (dry-run=$DRY_RUN)"
    
    clean_shell_config_files
    clean_fish_config_files
    clean_system_profile_scripts
    clean_directories
    clean_homebrew_casks
    
    output_json

    print "🔎 Post-check:"
    # Show what (if anything) still resolves to conda in this shell
    if command -v type >/dev/null 2>&1; then
        type -a conda || true
    else
        which conda || true
    fi

    print_completion_message
}

main "$@"