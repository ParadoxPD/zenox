#!/bin/bash

CONFIG_FILE="$XDG_CONFIG_HOME/.projinitrc"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# --------------------------- Colors --------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ------------------------ Global Vars ------------------------- #
debug_flag=0
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

# --------------------- Flag Parser ---------------------------- #
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -d | --debug) debug_flag=1 ;;
        -h | --help)
            echo "Usage: $0 [-d | --debug]"
            exit 0
            ;;
        -n | --dry-run) dry_run=1 ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-d | --debug]"
            exit 1
            ;;
        esac
        shift
    done
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

init_node() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] npm init -y"
    else
        npm init -y
    fi
}

init_python() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] uv venv"
    else
        uv venv
    fi
}

init_java() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] mkdir -p src && echo ... > src/Main.java"
    else
        mkdir -p src
        echo 'public class Main { public static void main(String[] args) { System.out.println("Hello World"); } }' >src/Main.java
    fi
}

init_go() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] go mod init \"$project_name\""
    else
        go mod init "$project_name"
    fi
}

init_zig() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] zig init-exe"
    else
        zig init-exe
    fi
}

init_rust() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] cargo init"
    else
        cargo init
    fi
}

init_assembly() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] touch main.asm && echo ... > main.asm"
    else
        touch main.asm
        echo "; Assembly entry point" >main.asm
    fi
}

init_react() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] npm create vite@latest . -- --template react"
    else
        npm create vite@latest . -- --template react
    fi
}

init_elixir() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] mix new \"$project_name\""
    else
        mix new "$project_name"
    fi
}

init_ocaml() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] mkdir -p src && echo ... > src/main.ml"
    else
        mkdir -p src
        echo 'print_endline "Hello, OCaml!";;' >src/main.ml
    fi
}

init_flutter() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] flutter create ."
    else
        flutter create .
    fi
}

init_php() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] laravel new ."
    else
        laravel new .
    fi
}

init_javascript() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] npm init -y && touch index.js"
    else
        npm init -y
        touch index.js
    fi
}

init_arduino() {
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] mkdir -p \"$project_name\" && echo ... > \"$project_name/$project_name.ino\""
    else
        mkdir -p "$project_name"
        echo "// Arduino sketch" >"$project_name/$project_name.ino"
    fi
}

initialize_project() {
    local type="$1"
    local gi="$2"
    local readme="$3"

    color_echo CYAN "Initializing empty git repository..."
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] git init"
    else
        git init
    fi

    # Dynamic dispatch to language-specific init
    local func="init_${type,,}" # lowercase function
    if declare -f "$func" >/dev/null; then
        color_echo CYAN "Running $func..."
        "$func"
    else
        color_echo RED "No initializer found for $type."
    fi

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

create_gitignore() {
    local type="$1"
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] Creating .gitignore for $type"
    else
        case "$type" in
        node) echo -e "node_modules/\n.env" >.gitignore ;;
        python) echo -e "__pycache__/\n.env\n.venv/" >.gitignore ;;
        java) echo -e "bin/\n*.class" >.gitignore ;;
        *) touch .gitignore ;;
        esac
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
        color_echo RED "No API mapping found."
        return
    }

    license_text=$(curl -s "https://api.github.com/licenses/$api_id" | jq -r '.body')
    if [[ "$dry_run" -eq 1 ]]; then
        echo "[Dry Run] Would fetch and write license: $selected_licence"
    elif [[ -n "$license_text" && "$license_text" != "null" ]]; then
        echo "$license_text" >LICENSE
        color_echo GREEN "LICENSE file created using $selected_licence."
    else
        color_echo RED "Failed to fetch license text."
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
    local exit_on_esc="${4:-true}" # Fourth parameter: true=exit script, false=just return

    # Show prompt
    echo -e "$prompt   "

    # Save terminal settings
    local old_stty
    old_stty=$(stty -g)
    # Set terminal to capture escape sequences
    stty raw -echo

    # Read a single character to check for ESC
    local char
    IFS= read -r -n1 char

    # Check if ESC was pressed
    if [[ "$char" == $'\e' ]]; then
        # Reset terminal
        stty "$old_stty"
        echo

        if [[ "$exit_on_esc" == "true" ]]; then
            exit_process "Escape pressed. Exiting gracefully." $project_dir
        else
            printf -v "$__varname" ""
            return 1 # Just return from function
        fi
    else
        # Rest of the function remains the same...
        stty "$old_stty"

        local input
        if [[ -n "$char" && "$char" != $'\r' && "$char" != $'\n' ]]; then
            input="$char"
            read -e -i "$input" input
            printf -v "$__varname" "%s" "$input"
            return 0
        else
            printf -v "$__varname" "%s" "$default_value"
            echo
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

# --------------------- Script Execution ----------------------- #
parse_flags "$@"
animate

base_path=$(fd . ~/ ~/Documents ~/Desktop ~/Documents/Projects --type=d --hidden --exclude .git --min-depth 0 --max-depth 3 | uniq | sort | fzf --height=20 --border --reverse --ansi)
[[ -z "$base_path" ]] && exit_process "No base path selected."

base_path=$(expand_path "$base_path")
base_path="${base_path:-$DEFAULT_PROJECT_PATH}"
color_echo GREEN "Base Directory: $base_path"

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

# Select project type
types=(Node Python Java Go Zig Rust Assembly React Elixir OCaml Flutter PHP JavaScript Arduino)
selected_type=$(printf "%s\n" "${types[@]}" | fzf --prompt="Select project type: " --height=15 --border --reverse --ansi)
selected_type="${selected_type:-$DEFAULT_INIT_TYPE}"
[[ -z "$selected_type" ]] && exit_process "No project type selected." "$project_dir"

special_read "${YELLOW}Create README.md? (Y/N):${NC}" readme_choice "N"
special_read "${YELLOW}Create .gitignore? (Y/N):${NC}" gitignore_choice "N"

initialize_project "$selected_type" "$gitignore_choice" "$readme_choice"

# Select license
licences=("MIT" "Apache-2.0" "GPL-3.0" "BSD-2-Clause" "BSD-3-Clause" "LGPL-3.0" "AGPL-3.0" "MPL-2.0" "Unlicense" "CC0-1.0" "EPL-2.0" "None")
selected_licence=$(printf "%s\n" "${licences[@]}" | fzf --prompt="Select license: " --height=10 --border --reverse --ansi)
selected_licence="${selected_licence:-$DEFAULT_LICENSE}"
set_licence "$selected_licence"

color_echo GREEN "Project setup complete at ${project_dir}."
[[ "$dry_run" -eq 1 ]] && color_echo YELLOW "(Dry run mode: no files were written.)"

special_read "${YELLOW}Create tmux session? (Y/N):${NC}" session_choice "Y"
if [[ "$dry_run" -eq 1 ]]; then
    color_echo YELLOW "[Dry Run] No Session Was Created"
else
    [[ "$session_choice" =~ ^[Nn]$ ]] || sessionize "$project_dir"
fi
