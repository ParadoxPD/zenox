# Zenox

                  __________
                  \____    /____   ____   _______  ___
                    /     // __ \ /    \ /  _ \  \/  /
                   /     /\  ___/|   |  (  <_> >    <
                  /_______ \___  >___|  /\____/__/\_ \
                          \/   \/     \/            \/

**Zenox** is a powerful, interactive **Bash utility** for initializing new projects with ease.  
It provides a guided, TUI-driven setup process that handles directory creation, starter code, licenses, git initialization, `.gitignore`, and even optional tmux session creation — all in one go.

---

## ✨ Features

- **Interactive TUI flow** powered by [`fzf`](https://github.com/junegunn/fzf):
  - Choose **base directory** from a searchable list.
  - Select **project type** from a pre-defined menu.
  - Pick a **license** from GitHub’s API.
  - Confirm creation of README, `.gitignore`, and tmux sessions.
- **Multi-language project templates**:
  - **Node.js**
  - **Python** (via `uv venv`)
  - **Java**
  - **Go**
  - **Zig**
  - **Rust**
  - **Assembly**
  - **React (Vite)**
  - **Elixir**
  - **OCaml**
  - **Flutter**
  - **PHP (Laravel)**
  - **JavaScript**
  - **Arduino**
- **Automatic `.gitignore` generation** for supported languages.
- **License auto-fetching** from GitHub’s license API:
  - Supports MIT, Apache-2.0, GPL-3.0, BSD variants, LGPL, AGPL, MPL, CC0, Unlicense, EPL-2.0, etc.
- **Configurable defaults** via `~/.config/zenox/config.json`:
  - Default project type
  - Default license
  - Default base path
- **Modes**:
  - **Interactive mode** (`-i` / `--interactive`) – TUI-driven setup (default if no mode is specified).
  - **Dry-run mode** (`-n` / `--dry-run`) – Preview commands without executing them.
  - **Debug mode** (`-d` / `--debug`) – Show static ASCII banner and extra logs.
- **Safety checks**:
  - Prevents accidental overwriting of existing projects.
  - Protects against dangerous deletions in home/documents directories.
- **Animated ASCII banner** for normal mode.
- **Custom colorized output** for better readability.
- **ESC key detection** to gracefully abort the process at any prompt.
- **Optional tmux session creation** after project setup.
- **Path expansion & normalization** (supports `~` and relative paths).

---

## 📦 Installation

Clone the repo and make the script executable:

```bash
git clone https://github.com/ParadoxPD/zenox.git
cd zenox
chmod +x zenox
```

(Optional) Add it to your `PATH`:

```bash
sudo mv zenox /usr/local/bin/zenox
```

---

## ⚡ Usage

### Basic

```bash
zenox
```

Starts the **interactive** project initialization flow (default mode).

### Flags

```bash
zenox [options]
```

| Option              | Description                                                         |
| ------------------- | ------------------------------------------------------------------- |
| `-i, --interactive` | Run in interactive TUI mode (default if no other mode is specified) |
| `-n, --dry-run`     | Show actions without making changes                                 |
| `-d, --debug`       | Enable debug mode (static banner, extra logs)                       |
| `-h, --help`        | Show help message and exit                                          |

---

## 🛠 Configuration

You can create a `$XDG_CONFIG_HOME/zenox/config.json` file to define defaults:

```json
{
  "defaults": {
    "gitignore": "Y",
    "readme": "Y",
    "licence": "MIT",
    "base_dirs": ["~/Documents/Projects", "~/Documents", "~/Desktop"]
  },
  "templates": {
    "node": {
      "commands": ["npm init -y"],
      "licence": "MIT"
    },
    "go": {
      "commands": ["go mod init {{project_name}}"],
      "licence": "GPL-3.0"
    }
  }
}
```

---

## 📄 Example Flow

**Run:**

```bash
zenox
```

**Steps:**

1. **Select base directory** (from recent locations via `fzf`).
2. **Enter project name**.
3. **Choose project type** (Node, Python, Rust, etc.).
4. **Confirm README.md creation**.
5. **Confirm `.gitignore` creation**.
6. **Initialize language-specific project structure**.
7. **Pick license** (auto-fetch from GitHub API).
8. **Optional tmux session** to start coding immediately.

---

## 📂 Example Output

```plaintext
Base Directory: /home/user/Documents/Projects
Enter the project name: myapp
Select project type: Rust
Create README.md? (Y/N): Y
Create .gitignore? (Y/N): Y
Initializing empty git repository...
Running init_rust...
LICENSE file created using MIT.
Project setup complete at /home/user/Documents/Projects/myapp.
Create tmux session? (Y/N): Y
```

**Resulting structure** (Rust example):

```
myapp/
├── Cargo.toml
├── LICENSE
├── README.md
├── .gitignore
└── src
    └── main.rs
```

---

## 🖥 Dependencies

- [`fzf`](https://github.com/junegunn/fzf) – interactive selection
- [`fd`](https://github.com/sharkdp/fd) – fast file finder
- `realpath` – path resolution
- `jq` – JSON parsing for GitHub API
- Language-specific tools (depending on your chosen project type):

  - `npm`, `uv`, `go`, `zig`, `cargo`, `flutter`, `laravel`, etc.

---

## 💡 Inspiration

Zenox was inspired by the need to **start coding faster** without repetitive setup.
It borrows the spirit of my obsession with tooling and automation, combined with safety-first design.

---

## 📜 License

[MIT](LICENSE)

```

```
