#!/usr/bin/env bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zenox"
PRIMARY_CONFIG_FILE="${CONFIG_DIR}/.zenox.config.json"
LEGACY_CONFIG_FILE="${CONFIG_DIR}/config.json"
CONFIG_FILE="$PRIMARY_CONFIG_FILE"

# --------------------------- ANSI CODES --------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ANSI helpers
CLEAR_LINE=$'\e[2K'
MOVE_LEFT=$'\e[D'
MOVE_RIGHT=$'\e[C'
CLEAR=$'\033[2J\033[H' # clear screen & move cursor home

# ------------------------ Global Vars ------------------------- #
debug_flag=0
interactive=0
template=""
dry_run=0
old_stty=$(stty -g)

# ------------------------ Utility ----------------------------- #
color_echo() {
    local color="$1"
    shift
    echo -e "${!color}$* ${NC}"
}

expand_path() {
    local input="$1"
    [[ "$input" == ~* ]] && input=$(eval echo "$input")
    realpath -m "$input"
}

validate_project_name() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    [[ "$name" == "." || "$name" == ".." ]] && return 1
    [[ "$name" == */* ]] && return 1
    [[ "$name" =~ [[:space:]] ]] && return 1
    [[ "$name" =~ [^A-Za-z0-9._-] ]] && return 1
    return 0
}

show_help() {
    echo -e "\n\n ${CYAN}Zenox - Interactive Project Initializer${NC}
    ${BLUE}---------------------------------------${NC}
    A Bash utility for quickly setting up new projects using a JSON-driven config,
    with an interactive TUI for selecting base directory, project type, and license.

    ${YELLOW}USAGE:${NC}
      zenox [OPTIONS]

    ${YELLOW}OPTIONS:${NC}
      ${GREEN}-h, --help${NC}                   Show this help message and exit.
      ${GREEN}-d, --debug${NC}                  Enable debug mode (static banner, extra logs).
      ${GREEN}-n, --dry-run${NC}                Show commands that would run without executing them.
      ${GREEN}-t, --template [Template]${NC}    Define Templates to use.
      ${GREEN}-i, --interactive${NC}            Force interactive TUI mode (default if no other mode is specified).

    ${YELLOW}FEATURES:${NC}
      • Config-driven templates with per-language commands.
      • TUI selection for base directory, project type, and license.
      • Automatic README.md, .gitignore, and LICENSE creation.
      • License templates fetched from GitHub API.
      • Optional tmux session creation.
      • Configurable defaults via ~/.config/zenox/.zenox.config.json (or legacy config.json).

    ${YELLOW}CONFIGURATION (~/.config/zenox/.zenox.config.json):${NC}
      {
        \"defaults\": {
          \"gitignore\": \"Y\",
          \"readme\": \"Y\",
          \"licence\": \"MIT\",
          \"base_dirs\": [\"~/Documents/Projects\", \"~/Documents\", \"~/Desktop\"]
        },
        \"templates\": {
          \"node\": { \"commands\": [\"npm init -y\"], \"licence\": \"MIT\" },
          \"go\": { \"commands\": [\"go mod init {{project_name}}\"], \"licence\": \"GPL-3.0\" }
        }
      }

    ${YELLOW}EXAMPLES:${NC}
      zenox -i             # Interactive flow
      zenox -t [Template]  # Add Template
      zenox -n             # Dry-run mode
      zenox --debug        # Debug mode

    ${YELLOW}DEPENDENCIES:${NC}
      zsh, fzf, fd, realpath, jq, tmux, tmux-sessionizer plus language-specific tools (npm, cargo, go, etc.)"
}

# --------------------- Flag Parser ---------------------------- #
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -d | --debug) debug_flag=1 ;;
        -h | --help)
            animate
            show_help
            exit 0
            ;;
        -n | --dry-run) dry_run=1 ;;
        -t | --template)
            if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then
                color_echo "RED" "Error: --template requires a value."
                exit 1
            fi
            template="$2"
            shift
            ;;
        -i | --interactive) interactive=1 ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        esac
        shift
    done

    # Default to interactive mode unless explicitly disabled in future flags.
    if [[ "${interactive:-0}" -ne 1 && -z "$template" ]]; then
        interactive=1
    fi
}

# ------------------ ASCII Banner ----------------------------- #
animate() {
    echo -e "${CYAN}"
    if [ "$debug_flag" -eq 1 ]; then
        cat <<"EOF"

        __________                          
        \____    /____   ____   _______  ___
          /     // __ \ /    \ /  _ \  \/  /
         /     /\  ___/|   |  (  <_> >    < 
        /_______ \___  >___|  /\____/__/\_ \
                \/   \/     \/            \/
EOF
    else
        while IFS= read -r line; do
            echo -n "      "
            for ((i = 0; i < ${#line}; i++)); do
                echo -n "${line:$i:1}"
                sleep 0.005
            done
            echo
        done <<"EOF"

            __________                          
            \____    /____   ____   _______  ___
              /     // __ \ /    \ /  _ \  \/  /
             /     /\  ___/|   |  (  <_> >    < 
            /_______ \___  >___|  /\____/__/\_ \
                    \/   \/     \/            \/
EOF
    fi
    echo -e "${NC}"
}

# ----------------------- Init Functions ------------------------ #

run_init() {
    local template="$1"

    # Run template-specific commands (config or built-in framework templates).
    if [[ -z "$template" ]]; then
        return
    fi

    local cmds=""
    local template_config

    template_config=$(get_config_value "$template" "commands")
    if [[ -n "$template_config" ]]; then
        cmds=$(jq -r '.[]?' <<<"$template_config")
    else
        cmds=$(get_builtin_template_commands "$template")
    fi

    if [[ -n "$cmds" ]]; then
        color_echo CYAN "Applying template commands for: $template"
        while IFS= read -r cmd; do
            [[ -z "$cmd" ]] && continue

            # Placeholder replacements
            local project_name_lower="${project_name,,}"
            cmd="${cmd//\{\{project_name\}\}/$project_name}"
            cmd="${cmd//\{\{project_name_lower\}\}/$project_name_lower}"
            cmd="${cmd//\{\{project_dir\}\}/$project_dir}"
            cmd="${cmd//\{\{base_path\}\}/$base_path}"

            if [[ "$dry_run" -eq 1 ]]; then
                echo "[Dry Run] Command: $cmd"
            else
                echo "$cmd"
                if ! (cd "$project_dir" && eval "$cmd"); then
                    exit_process "Template command failed: $cmd" "$project_dir"
                fi
            fi
        done <<<"$cmds"
    fi
}

initialize_project() {
    local type="$1"
    local gi="$2"
    local readme="$3"

    ensure_project_dir
    init_git_repo

    run_init "$type"

    [[ "$gi" =~ ^[Yy]$ ]] && create_gitignore "$type"
    if [[ "$readme" =~ ^[Yy]$ ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            echo "[Dry Run] echo '# $project_name' > README.md"
        else
            echo "# $project_name" >"$project_dir/README.md" || exit_process "Failed to create README.md" "$project_dir"
            color_echo GREEN "Created README.md"
        fi
    fi

}

init_git_repo() {
    color_echo CYAN "Initializing empty git repository..."
    ensure_project_dir

    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] git init"
    else
        git init || exit_process "Failed to initialize git repository." "$project_dir"
    fi

    add_remote=$(get_value "git_remote" "${YELLOW}Do you want to add a remote repository? (Y/N):${NC}" "N")
    if [[ "$add_remote" =~ ^[Yy]$ ]]; then
        remote_name=$(get_value "git_remote_name" "${YELLOW}Enter remote name: ${NC}" "origin")
        remote_name=${remote_name:-origin}
        [[ ! "$remote_name" =~ ^[A-Za-z0-9._-]+$ ]] && exit_process "Invalid remote name: '$remote_name'" "$project_dir"

        remote_uri=$(get_value "git_remote_uri" "${YELLOW}Enter remote URI: ${NC}" "")
        if [[ -z "$remote_uri" ]]; then
            color_echo RED "Remote URI cannot be empty. Skipping remote setup."
            return
        fi

        if [[ "$dry_run" -eq 1 ]]; then
            echo "[Dry Run] git remote add \"$remote_name\" \"$remote_uri\""
        else
            git remote add "$remote_name" "$remote_uri" || exit_process "Failed to add git remote '$remote_name'." "$project_dir"
            color_echo GREEN "Remote '$remote_name' added successfully."
        fi
    fi
}

create_gitignore() {
    local type="$1"
    ensure_project_dir

    if [[ -f "$project_dir/.gitignore" ]]; then
        color_echo YELLOW ".gitignore already exists; keeping existing file."
        return
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] Creating .gitignore for $type (GitHub templates first, fallback otherwise)"
    else
        local templates=()
        local config_templates_json
        local config_legacy_gitignore
        local builtins
        local fetched_any=0
        local output=""

        config_templates_json=$(jq -r --arg t "$type" '.templates[$t].gitignore_templates // empty' <<<"$CONFIG_JSON")
        if [[ -n "$config_templates_json" ]]; then
            mapfile -t templates < <(jq -r '.[]?' <<<"$config_templates_json")
        fi

        builtins=$(get_builtin_gitignore_templates "$type")
        if [[ -n "$builtins" ]]; then
            while IFS= read -r tmpl; do
                [[ -n "$tmpl" ]] && templates+=("$tmpl")
            done <<<"$builtins"
        fi

        if ((${#templates[@]} > 0)); then
            local seen=" "
            local uniq_templates=()
            local tmpl
            for tmpl in "${templates[@]}"; do
                if [[ "$seen" != *" $tmpl "* ]]; then
                    uniq_templates+=("$tmpl")
                    seen+=" $tmpl "
                fi
            done

            for tmpl in "${uniq_templates[@]}"; do
                local template_body
                template_body=$(fetch_github_gitignore_template "$tmpl")
                if [[ -n "$template_body" ]]; then
                    output+="# Source: github/gitignore/${tmpl}.gitignore"$'\n'
                    output+="$template_body"$'\n\n'
                    fetched_any=1
                fi
            done
        fi

        if [[ "$fetched_any" -eq 1 ]]; then
            printf "%s" "$output" >"$project_dir/.gitignore" || exit_process "Failed to write .gitignore." "$project_dir"
            color_echo GREEN "Created .gitignore from GitHub templates."
            return
        fi

        config_legacy_gitignore=$(jq -r --arg t "$type" '.templates[$t].gitignore // empty' <<<"$CONFIG_JSON")
        if [[ -n "$config_legacy_gitignore" && "$config_legacy_gitignore" != "null" ]]; then
            printf "%s\n" "$config_legacy_gitignore" >"$project_dir/.gitignore" || exit_process "Failed to write .gitignore fallback." "$project_dir"
            color_echo YELLOW "GitHub template unavailable; used template-config gitignore fallback."
            return
        fi

        generate_generic_gitignore "$type" >"$project_dir/.gitignore" || exit_process "Failed to write generic .gitignore fallback." "$project_dir"
        color_echo YELLOW "GitHub template unavailable; created generic fallback .gitignore."
    fi
}

fetch_github_gitignore_template() {
    local template="$1"
    [[ -z "$template" ]] && return 1
    [[ ! "$template" =~ ^[A-Za-z0-9._/-]+$ ]] && return 1

    curl -fsSL "https://raw.githubusercontent.com/github/gitignore/main/${template}.gitignore" 2>/dev/null
}

get_builtin_gitignore_templates() {
    local type="$1"
    case "$type" in
    react-vite | vue-vite | sveltekit | nextjs | nuxt | remix | t3-stack | express-api) printf "%s\n" "Node" ;;
    django | fastapi | flask-api) printf "%s\n" "Python" ;;
    spring-boot) printf "%s\n" "Java" ;;
    laravel | php-api) printf "%s\n" "PHP" ;;
    rails-api | rails-fullstack) printf "%s\n" "Ruby" ;;
    dotnet-webapi | aspnet-fullstack | maui) printf "%s\n" "VisualStudio" "CSharp" ;;
    rust-axum | tauri-app) printf "%s\n" "Rust" ;;
    go-fiber | go-gin) printf "%s\n" "Go" ;;
    flutter-app) printf "%s\n" "Dart" ;;
    react-express | vue-fastapi | go-react-stack) printf "%s\n" "Node" ;;
    *)
        # Fallback mapping for simple names that often match language templates.
        case "${type,,}" in
        *node* | *express* | *next* | *nuxt* | *react* | *vue* | *svelte* | *remix* | *js* | *ts*) printf "%s\n" "Node" ;;
        *python* | *django* | *flask* | *fastapi*) printf "%s\n" "Python" ;;
        *go*) printf "%s\n" "Go" ;;
        *rust*) printf "%s\n" "Rust" ;;
        *java* | *spring*) printf "%s\n" "Java" ;;
        *php* | *laravel*) printf "%s\n" "PHP" ;;
        *ruby* | *rails*) printf "%s\n" "Ruby" ;;
        *dotnet* | *csharp* | *aspnet*) printf "%s\n" "VisualStudio" "CSharp" ;;
        *flutter* | *dart*) printf "%s\n" "Dart" ;;
        *) ;;
        esac
        ;;
    esac
}

generate_generic_gitignore() {
    local type="$1"
    cat <<EOF
# Generic .gitignore fallback for ${type}
.DS_Store
Thumbs.db
*.log
*.tmp
*.swp
.env
.env.*
dist/
build/
coverage/
node_modules/
__pycache__/
.pytest_cache/
.venv/
target/
bin/
EOF
}

get_builtin_template_commands() {
    local type="$1"
    case "$type" in
    react-vite)
        cat <<'EOF'
npm create vite@latest . -- --template react
npm install
EOF
        ;;
    vue-vite)
        cat <<'EOF'
npm create vite@latest . -- --template vue
npm install
EOF
        ;;
    sveltekit)
        cat <<'EOF'
npm create svelte@latest .
npm install
EOF
        ;;
    nextjs)
        cat <<'EOF'
npx create-next-app@latest .
EOF
        ;;
    nuxt)
        cat <<'EOF'
npx nuxi@latest init .
npm install
EOF
        ;;
    remix)
        cat <<'EOF'
npx create-remix@latest .
EOF
        ;;
    t3-stack)
        cat <<'EOF'
npx create-t3-app@latest .
EOF
        ;;
    express-api)
        cat <<'EOF'
npm init -y
npm install express cors dotenv
EOF
        ;;
    fastapi)
        cat <<'EOF'
python -m venv .venv
. .venv/bin/activate && pip install fastapi uvicorn
EOF
        ;;
    django)
        cat <<'EOF'
python -m venv .venv
. .venv/bin/activate && pip install django && django-admin startproject config .
EOF
        ;;
    flask-api)
        cat <<'EOF'
python -m venv .venv
. .venv/bin/activate && pip install flask
EOF
        ;;
    spring-boot)
        cat <<'EOF'
curl -fsSL "https://start.spring.io/starter.zip?type=maven-project&language=java&name={{project_name}}&artifactId={{project_name_lower}}&dependencies=web,data-jpa,postgresql" -o starter.zip
unzip -oq starter.zip
rm -f starter.zip
shopt -s dotglob nullglob && mv {{project_name}}/* . 2>/dev/null || true
rm -rf {{project_name}}
EOF
        ;;
    laravel)
        cat <<'EOF'
composer create-project laravel/laravel .
EOF
        ;;
    rails-api)
        cat <<'EOF'
rails new . --api
EOF
        ;;
    php-api)
        cat <<'EOF'
composer init --name="{{project_name_lower}}/api" --no-interaction
EOF
        ;;
    dotnet-webapi)
        cat <<'EOF'
dotnet new webapi
EOF
        ;;
    go-fiber)
        cat <<'EOF'
go mod init {{project_name_lower}}
go get github.com/gofiber/fiber/v2
EOF
        ;;
    go-gin)
        cat <<'EOF'
go mod init {{project_name_lower}}
go get github.com/gin-gonic/gin
EOF
        ;;
    rust-axum)
        cat <<'EOF'
cargo init .
cargo add axum tokio --features tokio/full
EOF
        ;;
    react-express)
        cat <<'EOF'
mkdir -p frontend backend
(cd frontend && npm create vite@latest . -- --template react && npm install)
(cd backend && npm init -y && npm install express cors dotenv)
EOF
        ;;
    vue-fastapi)
        cat <<'EOF'
mkdir -p frontend backend
(cd frontend && npm create vite@latest . -- --template vue && npm install)
(cd backend && python -m venv .venv && . .venv/bin/activate && pip install fastapi uvicorn)
EOF
        ;;
    go-react-stack)
        cat <<'EOF'
mkdir -p frontend backend
(cd frontend && npm create vite@latest . -- --template react && npm install)
(cd backend && go mod init {{project_name_lower}}/backend && go get github.com/gin-gonic/gin)
EOF
        ;;
    rails-fullstack)
        cat <<'EOF'
rails new .
EOF
        ;;
    aspnet-fullstack)
        cat <<'EOF'
dotnet new mvc
EOF
        ;;
    tauri-app)
        cat <<'EOF'
npm create vite@latest . -- --template react
npm install
npm install -D @tauri-apps/cli
npm install @tauri-apps/api
EOF
        ;;
    flutter-app)
        cat <<'EOF'
flutter create .
EOF
        ;;
    maui)
        cat <<'EOF'
dotnet new maui
EOF
        ;;
    *) ;;
    esac
}

select_framework_template() {
    local category
    category=$(printf "%s\n" \
        "Frontend Frameworks" \
        "Backend Frameworks" \
        "Full-Stack (Frontend + Backend)" \
        "Cross-Platform & Native" |
        fzf --prompt="Select framework category: " --height=12 --border --reverse --ansi)

    [[ -z "$category" ]] && return 1

    local framework=""
    case "$category" in
    "Frontend Frameworks")
        framework=$(printf "%s\n" "react-vite" "vue-vite" "sveltekit" "nextjs" "nuxt" "remix" |
            fzf --prompt="Select frontend framework: " --height=12 --border --reverse --ansi)
        ;;
    "Backend Frameworks")
        framework=$(printf "%s\n" "express-api" "fastapi" "django" "flask-api" "spring-boot" "laravel" "rails-api" "dotnet-webapi" "go-fiber" "go-gin" "rust-axum" |
            fzf --prompt="Select backend framework: " --height=14 --border --reverse --ansi)
        ;;
    "Full-Stack (Frontend + Backend)")
        framework=$(printf "%s\n" "react-express" "vue-fastapi" "go-react-stack" "t3-stack" "rails-fullstack" "aspnet-fullstack" |
            fzf --prompt="Select full-stack preset: " --height=12 --border --reverse --ansi)
        ;;
    "Cross-Platform & Native")
        framework=$(printf "%s\n" "tauri-app" "flutter-app" "maui" |
            fzf --prompt="Select app framework: " --height=10 --border --reverse --ansi)
        ;;
    esac

    [[ -n "$framework" ]] && {
        printf "%s\n" "$framework"
        return 0
    }
    return 1
}

select_project_type() {
    local selected=""
    local config_options=()

    mapfile -t config_options < <(jq -r '.templates | keys[]?' <<<"$CONFIG_JSON")

    if [[ -n "$template" ]]; then
        if [[ -n "$(jq -r --arg t "$template" '.templates[$t] // empty' <<<"$CONFIG_JSON")" ]]; then
            printf "%s\n" "$template"
            return 0
        fi

        if [[ -n "$(get_builtin_template_commands "$template")" ]]; then
            printf "%s\n" "$template"
            return 0
        fi

        color_echo RED "Template '$template' was not found in config or built-in frameworks."
        return 1
    fi

    local selection_mode
    if ((${#config_options[@]} > 0)); then
        selection_mode=$(printf "%s\n" \
            "Template presets (Language Template defined in zenox config)" \
            "Framework presets (Built-in framework scaffolds and stacks)" |
            fzf --prompt="Select project source: " --height=8 --border --reverse --ansi)
    else
        selection_mode="Framework presets (Built-in framework scaffolds and stacks)"
    fi

    case "$selection_mode" in
    "Template presets (Language Template defined in zenox config)")
        selected=$(printf "%s\n" "${config_options[@]}" |
            fzf --prompt="Select project type: " --height=15 --border --reverse --ansi)
        ;;
    "Framework presets (Built-in framework scaffolds and stacks)")
        selected=$(select_framework_template)
        ;;
    *)
        selected=""
        ;;
    esac

    [[ -n "$selected" ]] && {
        printf "%s\n" "$selected"
        return 0
    }
    return 1
}

# -------------------- License Logic --------------------------- #
set_licence() {
    local selected_licence=$1

    declare -A licence_api_ids=(
        ["MIT"]="mit" ["Apache-2.0"]="apache-2.0" ["GPL-3.0"]="gpl-3.0"
        ["BSD-2-Clause"]="bsd-2-clause" ["BSD-3-Clause"]="bsd-3-clause"
        ["LGPL-3.0"]="lgpl-3.0" ["AGPL-3.0"]="agpl-3.0"
        ["MPL-2.0"]="mpl-2.0" ["Unlicense"]="unlicense"
        ["CC0-1.0"]="cc0-1.0" ["EPL-2.0"]="epl-2.0"
    )

    [[ "$selected_licence" == "None" || -z "$selected_licence" ]] && {
        color_echo YELLOW "No license applied."
        return
    }

    local api_id="${licence_api_ids[$selected_licence]}"
    [[ -z "$api_id" ]] && {
        color_echo RED "No API mapping found for '$selected_licence'."
        return
    }

    # Cache directory
    local cache_dir="${HOME}/.license_cache"
    mkdir -p "$cache_dir"
    local cache_file="$cache_dir/${api_id}.txt"

    # Check cache first
    if [[ -f "$cache_file" ]]; then
        license_text=$(<"$cache_file")
        color_echo CYAN "Loaded $selected_licence license from cache."
    else
        if [[ "$dry_run" -eq 1 ]]; then
            echo "[Dry Run] Would fetch license: $selected_licence from GitHub API"
            return
        fi

        color_echo CYAN "Fetching $selected_licence license from GitHub API..."
        license_text=$(curl -s "https://api.github.com/licenses/$api_id" | jq -r '.body')

        if [[ -n "$license_text" && "$license_text" != "null" ]]; then
            echo "$license_text" >"$cache_file"
            color_echo GREEN "Cached $selected_licence license to $cache_file"
        else
            color_echo RED "Failed to fetch license text for '$selected_licence'."
            return
        fi
    fi

    # Write LICENSE file
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] Would write LICENSE file for $selected_licence"
    else
        ensure_project_dir
        echo "$license_text" >"$project_dir/LICENSE" || exit_process "Failed to write LICENSE file." "$project_dir"
        color_echo GREEN "LICENSE file created using $selected_licence."
    fi
}

# -------------------- Error Exit Logic ------------------------ #
is_safe_relative_path() {
    local path="$1"
    local full_path
    full_path=$(realpath -m "$path" 2>/dev/null)
    [[ -z "$full_path" ]] && return 1

    local home_dir="$HOME"
    local forbidden=("$home_dir" "$home_dir/" "$home_dir/Desktop" "$home_dir/Documents")
    for bad in "${forbidden[@]}"; do [[ "$full_path" == "$bad" ]] && return 1; done
    return 0
}

exit_process() {
    local message="$1"
    if [[ -z "$message" ]]; then
        message="Did you press Ctrl+C??????"
    fi

    local project_dir="$2"

    # Clear screen
    printf "%b" "$CLEAR"

    # Restore terminal (if raw mode was active)
    if [[ -n "$old_stty" ]]; then
        stty "$old_stty" 2>/dev/null || true
    fi
    # Top border
    printf "%b" "${RED}════════════════════════════════════════════════════════════════════════${NC}\n"
    printf "%b" "${RED}EXITING PROCESS${NC}\n"
    printf "%b" "${RED}════════════════════════════════════════════════════════════════════════${NC}\n\n"

    # Delete project dir (if safe)
    if [[ "$#" -eq 2 && -d "$project_dir" ]] && is_safe_relative_path "$project_dir"; then
        cd ..
        printf "%b" "${YELLOW}Deleting project directory: ${CYAN}${project_dir}${NC}\n"
        rm -rf "$project_dir"
        echo
    fi

    # Display exit message
    printf "%b" "${RED}${message}${NC}\n\n"

    # Bottom border + exit
    printf "%b" "${RED}════════════════════════════════════════════════════════════════════════${NC}\n"
    printf "%b" "${GREEN}Exiting gracefully...${NC}\n\n"
    exit 1
}

ensure_project_dir() {
    if [[ "$dry_run" -eq 1 ]]; then
        return
    fi

    if [[ -z "${project_dir:-}" || ! -d "$project_dir" ]]; then
        exit_process "Project directory is not available: ${project_dir:-<unset>}"
    fi

    cd "$project_dir" || exit_process "Failed to enter project directory: $project_dir" "$project_dir"
}

special_read() {
    local prompt="$1"
    local __varname="$2"
    local default_value="${3:-}"
    local exit_on_esc="${4:-true}"

    # Decode escape sequences (\033 → ESC)
    prompt="$(echo -e "$prompt")"

    # Show prompt
    printf "%b" "$prompt " >/dev/tty

    # Save terminal settings
    old_stty=$(stty -g </dev/tty)

    trap 'stty "$old_stty" </dev/tty' EXIT

    # Set raw mode
    stty -icanon -echo </dev/tty

    # Set a trap for signals to call your exit function
    trap 'exit_process "Interrupted (Ctrl+C)." "$project_dir"' INT TERM

    local input=""
    local cursor_pos=${#input}

    # Show default value if any
    [[ -n "$input" ]] && printf "%s" "$input" >/dev/tty

    # --- Input loop ---
    while true; do
        local char
        IFS= read -r -n1 char </dev/tty
        [[ "$char" == $'\r' ]] && char=$'\n'
        # [[ "$char" == $'\0' ]] && continue
        #printf 'XXD: '
        #echo "$char" | xxd
        #printf 'OD: char='
        #echo -n "$char" | od -tx1 -a
        case "$char" in
        $'\e') # ESC or Arrow Key
            local seq
            IFS= read -r -n2 -t 0.01 seq </dev/tty

            case "$seq" in
            '[D') # Left
                [[ $cursor_pos -gt 0 ]] && {
                    printf "%s" "$MOVE_LEFT" >/dev/tty
                    ((cursor_pos--))
                }
                ;;
            '[C') # Right
                [[ $cursor_pos -lt ${#input} ]] && {
                    printf "%s" "$MOVE_RIGHT" >/dev/tty
                    ((cursor_pos++))
                }
                ;;
            '[H') # Home
                printf "\e[%dD" "$cursor_pos" >/dev/tty
                cursor_pos=0
                ;;
            '[F') # End
                local move_forward=$((${#input} - cursor_pos))
                ((move_forward > 0)) && printf "\e[%dC" "$move_forward" >/dev/tty
                cursor_pos=${#input}
                ;;
            '[3') # Delete
                if [[ $cursor_pos -lt ${#input} ]]; then
                    input="${input:0:$cursor_pos}${input:$((cursor_pos + 1))}"
                    printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
                    local move_back=$((${#input} - cursor_pos))
                    ((move_back > 0)) && printf "\e[%dD" "$move_back" >/dev/tty
                fi
                ;;
            '') # Just a plain ESC
                if [[ "$exit_on_esc" == "true" ]]; then
                    exit_process "Escape pressed." "$project_dir"
                else
                    printf -v "$__varname" ""
                    return 1 # trap EXIT will restore stty
                fi
                ;;
            esac
            ;;

        $'\x7f' | $'\b') # Backspace
            if [[ $cursor_pos -gt 0 ]]; then
                input="${input:0:$((cursor_pos - 1))}${input:$cursor_pos}"
                ((cursor_pos--))
                printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
                local move_back=$((${#input} - cursor_pos))
                ((move_back > 0)) && printf "\e[%dD" "$move_back" >/dev/tty
            fi
            ;;

        $'\n' | '') # Enter
            printf "\n" >/dev/tty
            echo >/dev/tty # Print newline
            while IFS= read -r -n1 -t 0.01; do :; done </dev/tty

            printf -v "$__varname" "%s" "${input:-$default_value}"
            return 0 # trap EXIT will restore stty
            ;;

        $'\x04') # Ctrl+D (Delete)
            if [[ $cursor_pos -lt ${#input} ]]; then
                input="${input:0:$cursor_pos}${input:$((cursor_pos + 1))}"
                printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
                local move_back=$((${#input} - cursor_pos))
                ((move_back > 0)) && printf "\e[%dD" "$move_back" >/dev/tty
            fi
            ;;

        $'\x01') # Ctrl+A (Home)
            printf "\e[%dD" "$cursor_pos" >/dev/tty
            cursor_pos=0
            ;;

        $'\x05') # Ctrl+E (End)
            local move_forward=$((${#input} - cursor_pos))
            ((move_forward > 0)) && printf "\e[%dC" "$move_forward" >/dev/tty
            cursor_pos=${#input}
            ;;

        $'\x0b') # Ctrl+K (Kill to end)
            input="${input:0:$cursor_pos}"
            printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
            ;;

        $'\x15') # Ctrl+U (Kill line)
            input="${input:$cursor_pos}"
            cursor_pos=0
            printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
            local move_back=${#input}
            ((move_back > 0)) && printf "\e[%dD" "$move_back" >/dev/tty
            ;;

        *) # Normal char
            [[ "$char" < $'\x20' ]] && continue
            # Filter out non-printable control characters
            if [[ "$char" > $'\x1f' ]]; then
                input="${input:0:$cursor_pos}${char}${input:$cursor_pos}"
                ((cursor_pos++))
                printf "%b%s%s" "${CLEAR_LINE}\r" "$prompt " "$input" >/dev/tty
                local move_back=$((${#input} - cursor_pos))
                ((move_back > 0)) && printf "\e[%dD" "$move_back" >/dev/tty
            fi
            ;;
        esac
    done
}

# ---------------------- Tmux Logic ---------------------------- #

sessionize() {
    local session_name
    session_name=$(basename "$1")
    session_name="${session_name//./_}"
    if command -v zsh >/dev/null 2>&1; then
        zsh -i -c "source ~/.zshrc; tn \"$session_name\" -t \"$2\""
    else
        echo "install zsh and tmux-sessionizer"
    fi

}

# ------------------------ Config Logic ------------------------ #

load_config() {
    if [[ -f "$PRIMARY_CONFIG_FILE" ]]; then
        CONFIG_FILE="$PRIMARY_CONFIG_FILE"
        CONFIG_JSON=$(/bin/cat "$CONFIG_FILE")
    elif [[ -f "$LEGACY_CONFIG_FILE" ]]; then
        CONFIG_FILE="$LEGACY_CONFIG_FILE"
        CONFIG_JSON=$(/bin/cat "$CONFIG_FILE")
    else
        CONFIG_JSON='{}'
    fi
}

get_config_value() {
    local template_name="$1"
    local key="$2"
    jq -r --arg tmpl "$template_name" --arg key "$key" \
        'if .templates[$tmpl][$key] != null then .templates[$tmpl][$key] else empty end' \
        <<<"$CONFIG_JSON"
}

get_default_value() {
    local key="$1"
    jq -r --arg key "$key" \
        'if .defaults[$key] != null then .defaults[$key] else empty end' \
        <<<"$CONFIG_JSON"
}

get_value() {
    local key="$1"
    local prompt="$2"
    local fallback="$3"
    local template_val=""
    local default_val=""
    local ans=""

    if [[ -n "$template" ]]; then
        template_val=$(get_config_value "$template" "$key")
    fi
    default_val=$(get_default_value "$key")

    if [[ "$interactive" -eq 1 ]]; then
        # TUI or full interactive mode
        hint="${template_val:-${default_val:-$fallback}}"
        special_read "$prompt [default: $hint]" ans "$hint"
        echo "$ans"
    elif [[ -n "$template_val" ]]; then
        # Use template config value if available
        echo "$template_val"
    elif [[ -n "$default_val" ]]; then
        # Use global default config if available
        echo "$default_val"
    else
        # Fallback: still prompt user (simple prompt, no fzf)
        special_read "$prompt" ans "$fallback"
        echo "$ans"
    fi
}

# --------------------- Main Function ----------------------- #

main() {
    # Load config
    load_config

    # Get base_dirs from config or fallback list
    if
        base_dirs_json=$(get_default_value "base_dirs")
        [[ -n "$base_dirs_json" ]]
    then
        # Parse array into space-separated list
        mapfile -t base_dirs < <(jq -r '.[]' <<<"$base_dirs_json")
    else
        base_dirs=(~/Documents ~/Desktop)
    fi

    # Expand and run fd across all base_dirs
    expanded_dirs=()
    for dir in "${base_dirs[@]}"; do
        expanded_dirs+=("$(expand_path "$dir")")
    done

    base_path=$(fd . "${expanded_dirs[@]}" --type=d --hidden --exclude .git --min-depth 0 --max-depth 3 | sort -u | fzf --height=20 --border --reverse --ansi)

    [[ -z "$base_path" ]] && exit_process "No base path selected."
    base_path=$(expand_path "$base_path")
    [[ ! -d "$base_path" ]] && exit_process "Selected base path does not exist: $base_path"
    [[ ! -w "$base_path" ]] && exit_process "Selected base path is not writable: $base_path"
    color_echo GREEN "Base Directory: $base_path"

    # Project name
    project_name=""
    special_read "${YELLOW}Enter the project name:${NC}" project_name ""
    if ! validate_project_name "$project_name"; then
        exit_process "Invalid project name '$project_name'. Allowed: letters, numbers, ., _, - and no spaces/slashes."
    fi
    project_dir="$base_path/$project_name"
    [[ -d "$project_dir" ]] && exit_process "Project already exists." "$project_dir"

    if [[ "$dry_run" -eq 1 ]]; then
        color_echo YELLOW "[Dry Run] Creating Directory"
    else
        mkdir -p "$project_dir" || exit_process "Failed to create project directory."
        cd "$project_dir" || exit_process "cd failed." "$project_dir"
    fi

    # Project type
    selected_type=$(select_project_type)
    if [[ -z "$selected_type" ]]; then
        selected_type=$(jq -r '.defaults.template // empty' <<<"$CONFIG_JSON")
    fi

    [[ -z "$selected_type" ]] && exit_process "No project type selected." "$project_dir"

    color_echo GREEN "Project Template : $selected_type"

    # README + Gitignore
    readme_choice=$(get_value "readme" "${YELLOW}Create README.md? (Y/N):${NC}" "N")
    gitignore_choice=$(get_value "gitignore" "${YELLOW}Create .gitignore? (Y/N):${NC}" "N")

    initialize_project "$selected_type" "$gitignore_choice" "$readme_choice"

    # License
    if [[ -n "$template" ]]; then
        selected_licence=$(get_config_value "$template" "licence")
    fi

    if [[ -z "$selected_licence" ]]; then
        selected_licence=$(get_default_value "licence")
    fi

    if [[ -z "$selected_licence" ]]; then
        licences=("MIT" "Apache-2.0" "GPL-3.0" "BSD-2-Clause" "BSD-3-Clause"
            "LGPL-3.0" "AGPL-3.0" "MPL-2.0" "Unlicense" "CC0-1.0" "EPL-2.0" "None")
        selected_licence=$(printf "%s\n" "${licences[@]}" |
            fzf --prompt="Select license: " --height=10 --border --reverse --ansi)
    fi

    [[ -z "$selected_licence" ]] && exit_process "No license selected."
    set_licence "$selected_licence"

    color_echo GREEN "Project setup complete at ${project_dir}."
    [[ "$dry_run" -eq 1 ]] && color_echo YELLOW "(Dry run mode: no files were written.)"

    # Tmux session
    session_choice=$(get_value "tmux_session" "${YELLOW}Create tmux session? (Y/N):${NC}" "N")
    if [[ "$dry_run" -eq 1 ]]; then
        color_echo YELLOW "[Dry Run] No Session Was Created"
    else
        if [[ "$session_choice" =~ ^[Yy]$ ]]; then
            sessionize "$project_dir" "$selected_type"
        fi
    fi

}

# --------------------- Script Execution ----------------------- #

parse_flags "$@"
animate
main
