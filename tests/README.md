# 🧪 Test Suite

This directory contains comprehensive tests for all Conda-Purger scripts.

## 📋 Test Coverage

### Platform-Specific Tests

| Platform | Test File | Description |
|----------|-----------|-------------|
| **macOS** | `test_mac_os.sh` | Tests the macOS conda purge script |
| **Linux** | `test_linux.sh` | Tests the Linux conda purge script |
| **Windows** | `test_windows.ps1` | Tests the Windows PowerShell script |

### Test Categories

Each platform test covers:

1. **Script Existence & Permissions** - Verifies scripts exist and are executable
2. **Help Output** - Tests help/usage information
3. **Dry Run Mode** - Confirms default safe mode
4. **Apply Mode (Sandboxed)** - Executes destructive actions only inside a temp sandbox with fake tools
5. **Idempotency** - Re-running apply does nothing harmful

## 🚀 Running Tests

### Run All Tests

```bash
# From repository root
./tests/run_all_tests.sh
```

### Run Individual Platform Tests

```bash
# macOS tests
./tests/test_macos.sh

# Linux tests
./tests/test_linux.sh

# Windows tests (requires PowerShell)
# On Windows:
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_windows.ps1
# Or with PowerShell Core on any OS:
pwsh -NoProfile -File ./tests/test_windows.ps1
```

### Test Output

Tests provide colored output with:
- 🟢 **Green** - Passed tests
- 🔴 **Red** - Failed tests
- 🟡 **Yellow** - Test headers and warnings
- 🔵 **Blue** - Summary information

## 🛠 Test Requirements

### macOS/Linux
- Bash shell
- No special requirements
- Tests run in a sandboxed temp HOME and use fake `sudo`/`brew` to avoid system changes

### Windows
- PowerShell 5+ (Windows 10+ includes it by default) or PowerShell Core (`pwsh`)
- Test will skip automatically if PowerShell is unavailable, or if your User PATH contains conda-like entries

## 📊 Test Results

The test suite provides:
- Individual test results
- Platform-specific summaries
- Overall pass/fail status
- Exit codes for CI/CD integration

## 🔧 Troubleshooting

### Permission Issues
```bash
# Make test scripts executable
chmod +x tests/*.sh
```

### PowerShell Execution Policy
```powershell
# Allow script execution
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Missing Scripts
If tests fail because scripts are missing, ensure:
1. All script files exist in `scripts/` directory
2. Scripts have correct permissions
3. Scripts are in the expected locations

## 🎯 What Tests Don't Cover

These tests are **non-destructive**:
- All file removals happen inside a temporary sandbox HOME
- System-level operations are routed through a fake `sudo` and never touch real `/etc` or `/usr`
- On macOS, Homebrew is faked so cask uninstalls are simulated only
- Windows test avoids touching your real profile/registry and will skip if it detects risk conditions

Tests exercise both dry-run and apply behavior, but only within the sandbox.

## 📝 Adding New Tests

To add new tests:

1. **For new platforms**: Create `test_<platform>.sh` or `test_<platform>.ps1`
2. **For new features**: Add test functions to existing platform files
3. **Update master runner**: Add platform to `run_all_tests.sh`

Follow the existing patterns for:
- Test function naming (`test_*`)
- Result reporting (`Write-TestResult` or `print_test_result`)
- Error handling
- Color coding
