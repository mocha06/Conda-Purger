# 🧪 Test Suite

This directory contains comprehensive tests for all Conda-Purger scripts.

## 📋 Test Coverage

### Platform-Specific Tests

| Platform | Test File | Description |
|----------|-----------|-------------|
| **macOS** | `test_macos.sh` | Tests the macOS conda purge script |
| **Linux** | `test_linux.sh` | Tests the Linux conda purge script |
| **Windows** | `test_windows.ps1` | Tests the Windows PowerShell script |

### Test Categories

Each platform test covers:

1. **Script Existence & Permissions** - Verifies scripts exist and are executable
2. **Help Output** - Tests help/usage information
3. **Dry Run Mode** - Confirms default safe mode
4. **Argument Parsing** - Tests all command-line flags
5. **Invalid Arguments** - Verifies error handling
6. **JSON Output** - Tests JSON formatting
7. **Quiet Mode** - Tests reduced output mode
8. **Force Mode** - Tests force flag handling
9. **Platform-Specific Features** - Tests unique functionality per platform

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
pwsh -File .\tests\test_windows.ps1
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

### Windows
- PowerShell 5+ (Windows 10+ includes it by default)
- Or PowerShell Core (`pwsh`)

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

These tests are **non-destructive** and don't:
- Actually modify system files
- Remove real conda installations
- Change environment variables
- Modify registry entries

They only test the **detection and reporting** functionality in dry-run mode.

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
