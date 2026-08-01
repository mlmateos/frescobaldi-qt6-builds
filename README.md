⚠️ **Unofficial Builds** — These are NOT official Frescobaldi builds. This is an independent project providing custom, optimized builds with PyQt6 for modern Linux distributions. The official Frescobaldi project does not endorse or support these builds.
For official builds, visit: https://www.frescobaldi.org/

# Frescobaldi Qt6 Builds
[![Latest Release](https://img.shields.io/github/v/release/mlmateos/frescobaldi-qt6-builds?include_prereleases&label=latest)](https://github.com/mlmateos/frescobaldi-qt6-builds/releases)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/mlmateos/frescobaldi-qt6-builds)

Custom, optimized builds of [Frescobaldi](https://github.com/frescobaldi/frescobaldi) with **PyQt6** for modern Linux distributions.

### ✨ Features
- 🎨 **PyQt6 / Qt 6.8.x LTS** — Modern UI/UX with long-term stability.
- ⚡ **Optimization** — Python bytecode optimized (`-OO`) to remove docstrings while keeping all translations for international users.
- 🔐 **GPG-signed packages** — Cryptographic security verification for all releases and repository metadata.
- 📦 **Two distribution methods**: `.deb` packages for Debian/Ubuntu-based distributions, and `AppImage` for any Linux distribution.
- 🛠️ **Automated build scripts** — Compile your own optimized version easily.

---

### ⚠️ Important: LilyPond Engine
Frescobaldi is a score editor, not a compilation engine. **You must have LilyPond installed** to compile and preview scores.

**Option 1: Automatic Installation (Recommended)**  
Frescobaldi v4.0+ can download and install the latest stable version of LilyPond for you. Simply open Frescobaldi, go to *Preferences > LilyPond*, click **Add**, and select the latest version from the dropdown.

**Option 2: From your distribution's repositories**  
```bash
sudo apt install lilypond
```

---

### 🚀 Quick Install (Recommended)
The easiest and most secure way to install Frescobaldi and keep it automatically updated is via our GPG-signed APT repository.

#### Step 1: Import the GPG Key
Our repository is cryptographically signed to ensure package integrity and security.
```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://raw.githubusercontent.com/mlmateos/frescobaldi-qt6-builds/main/frescobaldi-qt6-key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/frescobaldi-qt6-key.gpg
sudo chmod a+r /etc/apt/keyrings/frescobaldi-qt6-key.gpg
```

#### Step 2: Choose Your Branch
Add the repository to your system. Choose one of the following options:

🟢 **Stable** (Recommended for most users) — Only stable releases:
```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/frescobaldi-qt6-key.gpg] https://mlmateos.github.io/frescobaldi-qt6-builds stable main" | \
  sudo tee /etc/apt/sources.list.d/frescobaldi-qt6-builds.list
```

🟡 **Alpha** — Development versions (alpha, beta, rc) + stable releases:
```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/frescobaldi-qt6-key.gpg] https://mlmateos.github.io/frescobaldi-qt6-builds alpha main" | \
  sudo tee /etc/apt/sources.list.d/frescobaldi-qt6-builds.list
```
*(💡 Tip: You can switch between branches at any time by running the corresponding command again).*

#### Step 3: Install Frescobaldi
```bash
sudo apt update
sudo apt install frescobaldi
```

#### Updating & Uninstalling
```bash
# To update:
sudo apt update && sudo apt upgrade frescobaldi

# To uninstall:
sudo apt remove frescobaldi
sudo rm /etc/apt/sources.list.d/frescobaldi-qt6-builds.list
```

---

### 📦 Alternative Installation Methods

#### Method 1: Direct `.deb` Download
If you prefer not to use the APT repository:
1. Go to [Releases](https://github.com/mlmateos/frescobaldi-qt6-builds/releases)
2. Download the latest `frescobaldi-*-qt6-all.deb`
3. Install with: `sudo apt install ./frescobaldi-*-qt6-all.deb`

#### Method 2: AppImage (Portable)
For a portable version that works on any Linux distribution (no installation required):
1. Download the latest `frescobaldi-*-qt6-x86_64.AppImage` from [Releases](https://github.com/mlmateos/frescobaldi-qt6-builds/releases)
2. Make it executable and run:
   ```bash
   chmod +x frescobaldi-*.AppImage
   ./frescobaldi-*.AppImage
   ```

---

### 🔨 Build from Source
This repository provides automated build scripts for both `.deb` packages and `AppImage`.

#### Step 1: Install Dependencies
Run the included dependency installer script:
```bash
cd ~/frescobaldi-qt6-builds/scripts
./install-deps-frescobaldi.sh
```

#### Step 2: Build
```bash
# Build optimized .deb package
./build-frescobaldi-deb.sh --clean --poppler --sign --publish

# Or build portable AppImage
./build-frescobaldi-appimage.sh --clean --poppler --sign --publish
```

### Complete Options Reference
Both build scripts support the following options for consistency with your workflow:
| Option | Description |
| --- | --- |
| `--clean` | Clean build directory before starting |
| `--branch NAME` | Branch or tag to compile (e.g., `4.0.7`, `master`) |
| `--poppler` | Ensures Poppler utilities are checked/included for PDF handling |
| `--sign` | Sign the resulting package with GPG |
| `--publish` | Publish the result to GitHub Releases |
| `--gpg-key ID` | Use a specific GPG key for signing |
| `--revision N` | Debian package revision (default: `1`) — `.deb` only |
| `--yes` | No confirmation prompts (automated mode) |
| `--no-keep-source` | Do not keep the source code after compiling |
| `--help`, `-h` | Show all available options |

### What the Scripts Do (Step by Step)
- 🔍 Verify dependencies
- 📥 Clone/update Frescobaldi source from upstream
- 🏷️ Detect version from git tags
- 🛠️ Apply custom patches (Add custom credits to the About dialog)
- 🔨 Build Python wheel and package the result (`.deb` or `AppImage`)
- ⚡ Python bytecode optimized (`-OO`) to remove docstrings while keeping all translations for international users.
- 🔐 Sign with GPG (if `--sign`)
- 🌐 Publish to GitHub Releases (if `--publish`)
- 🗄️ Update APT repository with proper branch classification (`.deb` only)

---

### 💻 System Requirements
| Component | Requirement |
| --- | --- |
| OS | Debian 12+, Ubuntu 22.04+, or compatible |
| Architecture | x86_64 (amd64) |
| Python | Python 3.10+ |
| Qt | PyQt6 / Qt 6.8.x LTS |

---

### 🔒 Security
All packages and repository metadata are signed with GPG. You can verify the signatures:
```bash
# Import the GPG key (if not done during installation)
curl -fsSL https://raw.githubusercontent.com/mlmateos/frescobaldi-qt6-builds/main/frescobaldi-qt6-key.asc | gpg --dearmor > frescobaldi-qt6-key.gpg

# Verify .deb signature
gpg --verify frescobaldi-*.deb.asc frescobaldi-*.deb

# Verify AppImage signature
gpg --verify frescobaldi-*.AppImage.asc frescobaldi-*.AppImage
```

---

### 📚 Resources
- [Frescobaldi Official Site](https://www.frescobaldi.org/)
- [Frescobaldi Source Code](https://github.com/frescobaldi/frescobaldi)
- [LilyPond Official Site](https://lilypond.org/)

### 📄 License
This project (build scripts and infrastructure) is licensed under the MIT License.  
Frescobaldi itself is licensed under GPL-3.0+.

### 🤖 Acknowledgments
This project was developed with the valuable assistance of **Qwen (Qwen3.7)**, a large language model by Alibaba Group, which contributed to the design, optimization strategies (bytecode optimization), and automation of the build scripts, ensuring best practices for packaging PyQt6 applications on Linux.

Special thanks to the original [Frescobaldi](https://github.com/frescobaldi/frescobaldi) developers and contributors.

<p align="center">
<i>Happy Engraving!</i> 🎵
</p>

