#!/bin/bash

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zenox/.zenox.config.json"

# --------------------------- Colors --------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
      • Configurable defaults via ~/.config/zenox/config.json.

    ${YELLOW}CONFIGURATION (~/.config/zenox/config.json):${NC}
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
      fzf, fd, realpath, jq, plus language-specific tools (npm, cargo, go, etc.)"
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

    # Require at least interactive mode, a template, or both
    if [[ "${interactive:-0}" -ne 1 && -z "$template" ]]; then
        color_echo "RED" "\n\nError: You must specify either --interactive (-i) or --template (-t), or both.\n\n"
        exit 1
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
    local type="$1"

    # 2) Run template-specific commands (if template used)
    if [[ -n "$template" ]]; then
        local cmds
        template_config=$(get_config_value "$template" "commands")
        cmds=$(jq -r '.[]?' <<<"$template_config")

        if [[ -n "$cmds" ]]; then
            color_echo CYAN "Applying template commands for: $template"
            while IFS= read -r cmd; do
                [[ -z "$cmd" ]] && continue

                # Placeholder replacements
                cmd="${cmd//\{\{project_name\}\}/$project_name}"
                cmd="${cmd//\{\{project_dir\}\}/$project_dir}"
                cmd="${cmd//\{\{base_path\}\}/$base_path}"

                if [[ "$dry_run" -eq 1 ]]; then
                    echo "[Dry Run] $cmd"
                else
                    bash -c "$cmd"
                fi
            done <<<"$cmds"
        fi
    fi
}

initialize_project() {
    local type="$1"
    local gi="$2"
    local readme="$3"

    init_git_repo

    run_init "$type"

    [[ "$gi" =~ ^[Yy]$ ]] && create_gitignore "$type"
    if [[ "$readme" =~ ^[Yy]$ ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            echo "[Dry Run] echo '# $project_name' > README.md"
        else
            echo "# $project_name" >README.md
            color_echo GREEN "Created README.md"
        fi
    fi

}

init_git_repo() {
    color_echo CYAN "Initializing empty git repository..."

    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] git init"
    else
        git init
    fi

    add_remote=$(get_value "git_remote" "${YELLOW}Do you want to add a remote repository? (Y/N):${NC}" "N")
    if [[ "$add_remote" =~ ^[Yy]$ ]]; then
        remote_name=$(get_value "git_remote_name" "${YELLOW}Enter remote name: ${NC}" "origin")
        remote_name=${remote_name:-origin}

        remote_uri=$(get_value "git_remote_uri" "${YELLOW}Enter remote URI: ${NC}" "")
        if [[ -z "$remote_uri" ]]; then
            color_echo RED "Remote URI cannot be empty. Skipping remote setup."
            return
        fi

        if [[ "$dry_run" -eq 1 ]]; then
            echo "[Dry Run] git remote add \"$remote_name\" \"$remote_uri\""
        else
            git remote add "$remote_name" "$remote_uri"
            color_echo GREEN "Remote '$remote_name' added successfully."
        fi
    fi
}

create_gitignore() {
    local type="$1"
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] Creating .gitignore for $type"
    else
        # Get template from config
        local template
        template=$(jq -r --arg t "$type" '.templates[$t].gitignore // empty' "$CONFIG_FILE")

        if [[ -n "$template" && "$template" != "null" ]]; then
            echo -e "$template" >.gitignore
        else
            # Generic default if config doesn't have template
            echo -e "# Generic .gitignore\n*.log\n*.tmp\n.DS_Store\n.env*" >.gitignore
        fi

        color_echo GREEN "Created .gitignore"
    fi
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
        echo "$license_text" >LICENSE
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

function exit_process() {
    echo
    echo -e "${RED}"
    if [[ "$#" -eq 2 && -d "$2" ]] && is_safe_relative_path "$2"; then
        cd ..
        echo "Deleting project directory : $2"
        #SCARY!!!!!
        rm -r $2
    fi
    echo -e "$1"
    echo -e "${NC}"
    stty "$old_stty"
    exit 1

}

# --------------------- Terminal Read Logic -------------------- #
# Function for reading input with ESC key detection
special_read() {
    local prompt="$1"
    local __varname="$2"
    local default_value="${3:-}"
    local exit_on_esc="${4:-true}" # true = exit script, false = just return

    # Show prompt
    echo -ne "$prompt   " >/dev/tty

    # Save terminal settings
    local old_stty
    old_stty=$(stty -g </dev/tty)
    stty raw -echo </dev/tty

    # Read a single character to check for ESC
    local char
    IFS= read -r -n1 char </dev/tty

    # Check if ESC was pressed
    if [[ "$char" == $'\e' ]]; then
        stty "$old_stty" </dev/tty
        echo >/dev/tty

        if [[ "$exit_on_esc" == "true" ]]; then
            exit_process "Escape pressed. Exiting gracefully." "$project_dir"
        else
            printf -v "$__varname" ""
            return 1
        fi
    else
        # Restore settings before reading full input
        stty "$old_stty" </dev/tty

        local input
        if [[ -n "$char" && "$char" != $'\r' && "$char" != $'\n' ]]; then
            input="$char"
            read -e -i "$input" input </dev/tty
            printf -v "$__varname" "%s" "$input"
            return 0
        else
            printf -v "$__varname" "%s" "$default_value"
            echo >/dev/tty
            return 0
        fi
    fi
}

# ---------------------- Tmux Logic ---------------------------- #
tmux_create() {
    local session="$1"
    if tmux has-session -t "$session" 2>/dev/null; then
        [[ -n "$TMUX" ]] && tmux switch-client -t "$session" || tmux attach-session -t "$session"
    else
        tmux new-session -A -ds "$session"
        tmux new-window -dt "$session":
        tmux new-window -dt "$session":
        [[ -n "$TMUX" ]] && tmux switch-client -t "$session" || tmux attach-session -t "$session"
    fi
}

sessionize() {
    local session_name=$(basename "$1")
    session_name="${session_name//./_}"
    tmux_create "$session_name"
}

# ------------------------ Config Logic ------------------------ #

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        CONFIG_JSON=$(cat "$CONFIG_FILE")
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

    base_path=$(fd . "${expanded_dirs[@]}" --type=d --hidden --exclude .git --min-depth 0 --max-depth 3 |
        uniq | sort |
        fzf --height=20 --border --reverse --ansi)

    [[ -z "$base_path" ]] && exit_process "No base path selected."
    base_path=$(expand_path "$base_path")
    color_echo GREEN "Base Directory: $base_path"

    # Project name
    project_name=""
    special_read "${YELLOW}Enter the project name:${NC}" project_name ""
    [[ -z "$project_name" ]] && exit_process "Project name cannot be empty."
    project_dir="$base_path/$project_name"
    [[ -d "$project_dir" ]] && exit_process "Project already exists." "$project_dir"

    if [[ "$dry_run" -eq 1 ]]; then
        color_echo YELLOW "[Dry Run] Creating Directory"
    else
        mkdir -p "$project_dir" || exit_process "Failed to create project directory."
        cd "$project_dir" || exit_process "cd failed." "$project_dir"
    fi

    # Project type
    if [[ -n "$template" && -n "$(jq -r --arg t "$template" '.templates[$t] // empty' <<<"$CONFIG_JSON")" ]]; then
        # Template exists — use its key name as the type
        selected_type="$template"
    fi

    if [[ -z "$selected_type" ]]; then
        selected_type=$(jq -r '.defaults.template // empty' <<<"$CONFIG_JSON")
    fi

    if [[ -z "$selected_type" ]]; then
        types=($(jq -r '.templates | keys[]' <<<"$CONFIG_JSON"))
        selected_type=$(printf "%s\n" "${types[@]}" |
            fzf --prompt="Select project type: " --height=15 --border --reverse --ansi)
    fi

    [[ -z "$selected_type" ]] && exit_process "No project type selected." "$project_dir"

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
        [[ "$session_choice" =~ ^[Nn]$ ]] || sessionize "$project_dir"
    fi

}

# --------------------- Script Execution ----------------------- #

parse_flags "$@"
animate
main
