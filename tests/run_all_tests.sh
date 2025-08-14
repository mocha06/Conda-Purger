#!/usr/bin/env bash
set -euo pipefail

# Master test runner for all Conda-Purger scripts
# Run with: ./tests/run_all_tests.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TOTAL_PLATFORMS=0
PASSED_PLATFORMS=0
FAILED_PLATFORMS=0
SKIPPED_PLATFORMS=0

print_header() {
    echo -e "\n${BLUE}🧪 Conda-Purger Test Suite${NC}"
    echo "================================"
    echo "Testing all platform scripts..."
    echo ""
}

print_platform_header() {
    echo -e "${YELLOW}🔍 Testing $1${NC}"
    echo "========================"
}

print_platform_result() {
    local platform="$1"
    local result="$2"
    TOTAL_PLATFORMS=$((TOTAL_PLATFORMS + 1))
    
    case "$result" in
        "PASS")
            echo -e "${GREEN}✅ $platform: PASSED${NC}"
            PASSED_PLATFORMS=$((PASSED_PLATFORMS + 1))
            ;;
        "FAIL")
            echo -e "${RED}❌ $platform: FAILED${NC}"
            FAILED_PLATFORMS=$((FAILED_PLATFORMS + 1))
            ;;
        "SKIP")
            echo -e "${YELLOW}⏭️  $platform: SKIPPED${NC}"
            SKIPPED_PLATFORMS=$((SKIPPED_PLATFORMS + 1))
            ;;
    esac
}

print_final_summary() {
    echo -e "\n${BLUE}📊 Final Test Summary${NC}"
    echo "========================"
    echo -e "Platforms tested: $TOTAL_PLATFORMS"
    echo -e "${GREEN}Passed: $PASSED_PLATFORMS${NC}"
    echo -e "${RED}Failed: $FAILED_PLATFORMS${NC}"
    if [[ $SKIPPED_PLATFORMS -gt 0 ]]; then
        echo -e "${YELLOW}Skipped: $SKIPPED_PLATFORMS${NC}"
    fi
    echo ""
    
    if [[ $FAILED_PLATFORMS -eq 0 ]]; then
        if [[ $SKIPPED_PLATFORMS -eq 0 ]]; then
            echo -e "${GREEN}🎉 All platform tests passed!${NC}"
        else
            echo -e "${GREEN}🎉 All runnable platform tests passed!${NC}"
        fi
        exit 0
    else
        echo -e "${RED}💥 Some platform tests failed!${NC}"
        exit 1
    fi
}

# Test macOS script
test_macos() {
    print_platform_header "macOS"
    
    local test_script="$SCRIPT_DIR/test_mac_os.sh"
    
    if [[ ! -f "$test_script" ]]; then
        echo -e "${RED}Error: macOS test script not found: $test_script${NC}"
        print_platform_result "macOS" "FAIL"
        return
    fi
    
    if [[ ! -x "$test_script" ]]; then
        echo -e "${YELLOW}Making macOS test script executable...${NC}"
        chmod +x "$test_script"
    fi
    
    echo -e "${YELLOW}Running macOS tests...${NC}"
    if "$test_script" >/dev/null 2>&1; then
        print_platform_result "macOS" "PASS"
    else
        print_platform_result "macOS" "FAIL"
    fi
}

# Test Linux script
test_linux() {
    print_platform_header "Linux"
    
    local test_script="$SCRIPT_DIR/test_linux.sh"
    
    if [[ ! -f "$test_script" ]]; then
        echo -e "${RED}Error: Linux test script not found: $test_script${NC}"
        print_platform_result "Linux" "FAIL"
        return
    fi
    
    if [[ ! -x "$test_script" ]]; then
        echo -e "${YELLOW}Making Linux test script executable...${NC}"
        chmod +x "$test_script"
    fi
    
    echo -e "${YELLOW}Running Linux tests...${NC}"
    if "$test_script" >/dev/null 2>&1; then
        print_platform_result "Linux" "PASS"
    else
        print_platform_result "Linux" "FAIL"
    fi
}

# Test Windows script
test_windows() {
    print_platform_header "Windows"
    
    local test_script="$SCRIPT_DIR/test_windows.ps1"
    
    if [[ ! -f "$test_script" ]]; then
        echo -e "${RED}Error: Windows test script not found: $test_script${NC}"
        print_platform_result "Windows" "FAIL"
        return
    fi
    
    echo -e "${YELLOW}Checking for PowerShell availability...${NC}"
    
    # Try to run PowerShell test
    if command -v pwsh >/dev/null 2>&1; then
        echo -e "${YELLOW}Found pwsh (PowerShell Core), running Windows tests...${NC}"
        if pwsh -NoProfile -File "$test_script" >/dev/null 2>&1; then
            print_platform_result "Windows" "PASS"
        else
            print_platform_result "Windows" "FAIL"
        fi
    elif command -v powershell.exe >/dev/null 2>&1; then
        echo -e "${YELLOW}Found powershell.exe, running Windows tests...${NC}"
        if powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$test_script" >/dev/null 2>&1; then
            print_platform_result "Windows" "PASS"
        else
            print_platform_result "Windows" "FAIL"
        fi
    else
        echo -e "${YELLOW}PowerShell not found on this system${NC}"
        echo -e "${YELLOW}Windows tests require PowerShell (pwsh or powershell.exe)${NC}"
        print_platform_result "Windows" "SKIP"
    fi
}

# Check if scripts exist
check_scripts_exist() {
    echo -e "${YELLOW}🔍 Checking script files...${NC}"
    
    local scripts=(
        "$REPO_ROOT/scripts/purge_conda_macos.sh"
        "$REPO_ROOT/scripts/purge_conda_linux.sh"
        "$REPO_ROOT/scripts/Purge-CondaWindows.ps1"
    )
    
    local all_exist=true
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -e "${GREEN}  ✅ $(basename "$script")${NC}"
        else
            echo -e "${RED}  ❌ $(basename "$script") - NOT FOUND${NC}"
            all_exist=false
        fi
    done
    
    if [[ "$all_exist" == "false" ]]; then
        echo -e "${RED}Warning: Some scripts are missing!${NC}"
    fi
    echo ""
}

# Check current platform
check_platform() {
    echo -e "${YELLOW}🔍 Current Platform: $(uname -s)${NC}"
    echo -e "${YELLOW}   Architecture: $(uname -m)${NC}"
    echo ""
}

# Main test runner
main() {
    print_header
    check_platform
    check_scripts_exist
    
    # Run platform-specific tests
    test_macos
    test_linux
    test_windows
    
    print_final_summary
}

# Run tests
main "$@"
