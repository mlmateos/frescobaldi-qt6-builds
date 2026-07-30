⚠️ **Unofficial Builds** — These are NOT official Frescobaldi builds. This is an independent project providing custom, optimized builds with PyQt6 for modern Linux distributions. The official Frescobaldi project does not endorse or support these builds.
For official builds, visit: https://www.frescobaldi.org/

# Frescobaldi Qt6 Builds
[![Latest Release](https://img.shields.io/github/v/release/mlmateos/frescobaldi-qt6-builds?include_prereleases&label=latest)](https://github.com/mlmateos/frescobaldi-qt6-builds/releases)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/mlmateos/frescobaldi-qt6-builds)

Custom, optimized builds of [Frescobaldi](https://github.com/frescobaldi/frescobaldi) with **PyQt6** for modern Linux distributions.

### ✨ Features
- 🎨 **PyQt6 / Qt 6.8.x LTS** — Modern UI/UX with long-term stability.
- ✂️ **Aggressive Optimization** — Locale pruning (only `es_ES`, `es_MX`, `en_US`, `en_GB`, `fr_FR`) and Python bytecode optimization (`-OO`) to remove docstrings, reducing package size significantly.
- 🔐 **GPG-signed packages** — Cryptographic security verification for all releases.
-  **Two distribution methods**: `.deb` packages for Debian/Ubuntu-based distributions, and `AppImage` for any Linux distribution.
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

### 🚀 Installation

#### Method 1: Direct `.deb` Download
Go to [Releases](https://github.com/mlmateos/frescobaldi-qt6-builds/releases), download the latest `.deb`, and install:
```bash
sudo apt install ./frescobaldi-*-qt6-all.deb
```

#### Method 2: AppImage (Portable)
For a portable version that works on any Linux distribution (no installation required):
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

#### Step 2: Clone the Repository
```bash
git clone https://github.com/mlmateos/frescobaldi-qt6-builds.git
cd frescobaldi-qt6-builds/scripts
```

#### Step 3: Build
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
- ️ Detect version from git tags
- 🛠️ Apply custom patches (Add custom credits to the About dialog)
- 🔨 Build Python wheel and package the result (`.deb` or `AppImage`)
- ✂️ Apply optimizations (Locale pruning, Python `-OO` bytecode)
- 🔐 Sign with GPG (if `--sign`)
- 🌐 Publish to GitHub Releases (if `--publish`)

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
All packages are signed with GPG. You can verify the signatures:
```bash
# Import the GPG key (exported from your keyring)
gpg --export --armor YOUR_KEY_ID > frescobaldi-qt6-key.asc
gpg --import frescobaldi-qt6-key.asc

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
This project was developed with the valuable assistance of **Qwen (Qwen3.7)**, a large language model by Alibaba Group, which contributed to the design, optimization strategies (locale pruning, bytecode optimization), and automation of the build scripts, ensuring best practices for packaging PyQt6 applications on Linux.

Special thanks to the original [Frescobaldi](https://github.com/frescobaldi/frescobaldi) developers and contributors.

<p align="center">
<i>Happy Engraving!</i> 🎵
</p>

