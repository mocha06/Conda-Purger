# 🧹 Conda-Purger
**Easily and completely uninstall Anaconda, Miniconda, Mambaforge, Miniforge, or Micromamba from macOS, Linux, and Windows.**

---

## 📖 Overview
When you uninstall Conda via normal means, traces often remain in:

- Shell configuration files (`.zshrc`, `.bashrc`, etc.)
- System profile scripts
- Homebrew casks (macOS)
- Hidden configuration folders
- PATH variables
- Fish shell configs

**`Conda-Purger`** automates the process of finding and removing all those remnants, with a **safe dry-run by default** so you can review changes before applying them.

---

## ✨ Features
- ✅ Cross-platform: **macOS**, **Linux**, and **Windows**
- ✅ Removes:
  - Anaconda, Miniconda, Mambaforge, Miniforge
  - Micromamba (optional)
- ✅ Cleans:
  - Shell startup files (Zsh, Bash, Fish, Csh, Tcsh)
  - System `/etc/profile.d` scripts
  - Homebrew installations
  - Hidden Conda config/cache folders
- ✅ **Dry-run mode** (default) – see what would be removed before deleting
- ✅ JSON output option for scripting/integration
- ✅ Optional `--force` to continue even if some steps fail

---

## 📋 Requirements

### macOS
- **Bash** or **Zsh** (pre-installed)
- (Optional) **Homebrew** if you want to remove Homebrew-installed Conda

### Linux
- **Bash** (pre-installed on most distros)
- `sudo` access for removing system profile scripts

### Windows
- **PowerShell 5+** (Windows 10+ includes it by default)

---

## 🚀 Installation

You can run it directly from the repository without installing anything globally.

```bash
git clone https://github.com/mocha06/Conda-Purger.git
cd Conda-Purger
```

---

## 📦 Usage

### Cross-Platform (Recommended)

From the repository root, use the dispatcher script:

```bash
# Dry-run (default)
./scripts/purge_conda_macos.sh

# Actually remove everything
./scripts/purge_conda_macos.sh --yes

# Full cleanup including Miniforge/Mambaforge & Micromamba
./scripts/purge_conda_macos.sh --yes --include-forge --include-micromamba
```

### Platform-Specific Scripts

#### macOS & Linux

```bash
# macOS
./scripts/purge_conda_macos.sh --yes --include-forge --include-micromamba

# Linux
./scripts/purge_conda_linux.sh --yes --include-forge --include-micromamba
```

#### Windows

From Windows PowerShell (not WSL):

```powershell
# Dry-run
.\scripts\Purge-CondaWindows.ps1

# Actually remove everything
.\scripts\Purge-CondaWindows.ps1 -Yes -IncludeForge -IncludeMicromamba

# With JSON output
.\scripts\Purge-CondaWindows.ps1 -Yes -Json | ConvertFrom-Json | Format-List
```

Or from Git Bash / WSL:

```bash
./scripts/purge_conda_linux.sh --yes
```
_(WSL mode cleans the Linux environment only.)_

---

### Options

| Flag | macOS/Linux | Windows PowerShell | Description |
|------|-------------|-------------------|-------------|
| `--yes` | `--yes` | `-Yes` | Actually perform deletions |
| `--force` | `--force` | `-Force` | Continue even if a removal fails |
| `--quiet` | `--quiet` | `-Quiet` | Suppress non-error output |
| `--json` | `--json` | `-Json` | Output changes in JSON format |
| `--include-forge` | `--include-forge` | `-IncludeForge` | Also remove Mambaforge/Miniforge |
| `--include-micromamba` | `--include-micromamba` | `-IncludeMicromamba` | Also remove Micromamba |
| `--system` | (not implemented) | `-System` | On Windows, clean for all system users |

---

## 🛡 Safety Notes
- **Dry-run is ON by default** — no changes are made until you add `--yes` (or `-Yes` in PowerShell).
- The script makes backups of shell configuration files before modifying them.
- On macOS/Linux, `--force` skips aborting on permission errors (e.g., `/etc/profile.d`).
- Always review the dry-run output carefully before running with `--yes`.

---

## 🧑‍💻 Examples

### Preview what would be removed:
```bash
./scripts/purge_conda_macos.sh
```

### Full cleanup, including Miniforge/Mambaforge & Micromamba:
```bash
./scripts/purge_conda_macos.sh --yes --include-forge --include-micromamba
```

### Windows, cleaning user + system:
```powershell
.\scripts\Purge-CondaWindows.ps1 -Yes -IncludeForge -IncludeMicromamba -System
```

### Get JSON summary of changes:
```bash
./scripts/purge_conda_macos.sh --yes --json
```

---

## 🔧 Troubleshooting

### Permission Issues
If you get permission errors on macOS/Linux:
```bash
# Make scripts executable
chmod +x scripts/purge_conda_macos.sh
chmod +x scripts/purge_conda_linux.sh
```

### PowerShell Execution Policy
If PowerShell blocks script execution:
```powershell
# Allow execution for current session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### WSL Users
If you're using WSL, the Linux script will clean your Linux environment. To clean Windows:
1. Open Windows PowerShell (not WSL)
2. Navigate to the repository
3. Run the Windows PowerShell script

---

## ⚠️ Disclaimers

- This will permanently delete Conda installations and related configuration files.
- **Review the dry-run output carefully before running with `--yes`.**
- The Windows PowerShell script is not totally tested, due to my limited knowledge of PowerShell and was mostly written by ChatGPT based on the Linux and Mac scripts. Use at your own risk. Feel free to submit a PR if you find any issues.

---

## 📝 License

MIT (do whatever, just don't hold me liable)
