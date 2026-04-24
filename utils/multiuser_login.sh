#!/bin/bash

# Version 2026.04.24.1
# Made by: Josue Rodriguez de la Rosa & Edgar RP
# Script to enable a multi user environment in a single shared user organizing files into Users folder.


# Doc generate by ChatGPT
# Interactive "identity + mode" selector for shared cluster lanes (masters_1/2, phds_1/2)
# - Prompts for identity (creates new if needed)
# - Prompts for LOW/HIGH
# - Creates per-person HOME under ~/Users/<name_slug> with .ssh and .gitconfig
# - Shows current active sessions as COUNTS (no identities)
# - Logs session start/end + duration to a global CSV
# - Uses HOME isolation but preserves lane environment (e.g., rootless Docker) by sourcing REAL_HOME init
#
# IMPORTANT:
# - Hook from each lane user's ~/.bash_profile: exec /<path_to_scrip>/cluster_login.sh

set -euo pipefail

# =========================
# Config
# =========================
LANE="$(whoami)"                                # e.g., masters_1
LANES=("students" "masters_1" "masters_2" "phds_1" "phds_2") # Define here the shared users, by default are added the users for a research cluster
HOST="$(hostname -s 2>/dev/null || hostname)"

REAL_HOME="$HOME"                               # keep original HOME (lane home)

USERS_FILE="$REAL_HOME/.multiuser_profiles"          # display list (names) kept in lane home
BASE_DIR="$REAL_HOME/Users"                     # per-person dirs live under lane home


# Global-ish state & audit (recommended when script is centralized)
STATE_DIR="$REAL_HOME/.multiuser_usage"              # sessions state (sticky dir)
AUDIT_DIR="$REAL_HOME/.multiuser_audit"                    # audit logs (sticky dir)
AUDIT_LOG="$AUDIT_DIR/sessions.csv"             # persistent session log (csv)

mkdir -p "$BASE_DIR"
mkdir -p -m 755 "$STATE_DIR" "$AUDIT_DIR"

# =========================
# Helpers
# =========================
sanitize_name() {
  # Create a filesystem-safe slug:
  # - lowercase
  # - spaces -> underscore
  # - remove weird chars -> underscore
  local s="$1"
  s="$(echo "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(echo "$s" | sed -E 's/[[:space:]]+/_/g; s/[^a-z0-9._-]+/_/g; s/^_+|_+$//g')"
  echo "$s"
}

ensure_users_file() {
  if [[ ! -f "$USERS_FILE" ]]; then
    cat > "$USERS_FILE" <<EOF
# Identify file for $LANE (one per line).
# It updated when you add a new user from the menu.
EOF
  fi
}

load_users() {
  mapfile -t USERS < <(grep -v '^\s*#' "$USERS_FILE" | sed '/^\s*$/d' || true)
}

iso_from_epoch() {
  if date -d "@0" >/dev/null 2>&1; then
    date -d "@$1" '+%Y-%m-%d %H:%M:%S'
  else
    echo "$1"
  fi
}

ensure_audit_header() {
  if [[ ! -f "$AUDIT_LOG" ]]; then
    mkdir -p "$AUDIT_DIR"
    echo "start_iso,end_iso,duration_sec,lane,mode,name,host,pid,home" > "$AUDIT_LOG"
  fi
}

prune_and_count_sessions() {
  # Outputs counts in associative arrays: low_count[], high_count[]
  declare -gA low_count high_count
  low_count=()
  high_count=()

  shopt -s nullglob
  for user in $LANES; do
    state_dir="/home/$user/.multiuser_usage"
    for f in "$state_dir"/*.session; do
      # lane|mode|name|pid|start_epoch|home
      IFS='|' read -r lane mode name pid start_epoch userhome < "$f" || true

      # remove stale sessions
      if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$f" 2>/dev/null || true
        continue
      fi

      if [[ "$mode" == "LOW" ]]; then
        low_count["$lane"]=$(( ${low_count["$lane"]:-0} + 1 ))
      else
        high_count["$lane"]=$(( ${high_count["$lane"]:-0} + 1 ))
      fi
    done
  done
  shopt -u nullglob
}

print_status() {
  echo "============================================================"
  echo "$LANE LOGIN  | Host: $HOST"
  echo
  echo "Current users (counted by lane / mode):"
  echo

  prune_and_count_sessions

  # If you ever add more lanes, extend this list.
  for lane in $LANES; do
    printf "  - %-9s | LOW: %-2s | HIGH: %-2s\n" \
      "$lane" "${low_count["$lane"]:-0}" "${high_count["$lane"]:-0}"
  done

  echo "============================================================"
}

choose_identity() {
  ensure_users_file
  load_users

  echo
  echo "¿Who are you?"
  if ((${#USERS[@]} > 0)); then
    local i=1
    for u in "${USERS[@]}"; do
      echo "  [$i] $u"
      ((i++))
    done
    echo "  [0] Add a new user"
  else
    echo "  (There are not registered users)"
    echo "  [0] Add a new user"
  fi

  local choice
  read -rp "Select an option (number): " choice

  if [[ "$choice" == "0" ]]; then
    read -rp "Define your username to create the user: " RAW_NAME
    RAW_NAME="${RAW_NAME:-unknown}"

    SLUG="$(sanitize_name "$RAW_NAME")"
    if [[ -z "$SLUG" ]]; then
      echo "ERROR: Invalid characters in the username."
      exit 1
    fi

    echo
    echo "Your folder data will be: $BASE_DIR/$SLUG"
    echo "(Note: Your username always be lowercase and without blank spaces.)"
    echo

    if ! grep -Fxq "$RAW_NAME" "$USERS_FILE" 2>/dev/null; then
      echo "$RAW_NAME" >> "$USERS_FILE"
    fi

    NAME="$RAW_NAME"
  else
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1)) || ((choice > ${#USERS[@]})); then
      echo "Invalid option."
      exit 1
    fi
    NAME="${USERS[$((choice-1))]}"
    SLUG="$(sanitize_name "$NAME")"
    if [[ -z "$SLUG" ]]; then
      echo "ERROR: Invalid username."
      exit 1
    fi
  fi

  USER_DIR="$BASE_DIR/$SLUG"
  mkdir -p "$USER_DIR"
}

choose_mode() {
  echo
  echo "Select your estimated session development level:"
  echo "  [1] LOW  (writing code, review results; avoid dataset/GPU/long jobs)"
  echo "  [2] HIGH (training, inference; requires GPU booking in the calendar)"
  local m
  read -rp "Mode (1/2): " m
  case "$m" in
    1) MODE="LOW" ;;
    2) MODE="HIGH" ;;
    *) echo "Invalid option."; exit 1 ;;
  esac
}

bootstrap_person_home() {
  # Isolate identity by setting HOME to per-person dir
  export HOME="$USER_DIR"
  mkdir -p -m 700 "$HOME/.ssh"

  # Create .gitconfig if absent (so commits are attributed properly)
  if [[ ! -f "$HOME/.gitconfig" ]]; then
    cat > "$HOME/.gitconfig" <<EOF
[user]
    name = $NAME
    email = ${SLUG}@example.invalid
EOF
  fi

  # Helpful note
  if [[ ! -f "$HOME/README_SYNC.txt" ]]; then
    cat > "$HOME/README_SYNC.txt" <<EOF
Personal workspace for: $NAME
User: $LANE

Recommended practices:
- Keep your code sync with a Git service (Github, Gitlab, etc) and do pull/push frequently. The data can be lost sometimes due to disks failure.
- Your commit identification is defined by default in `$USER_DIR/.gitconfig` with `user.name=$NAME` and `user.email=${SLUG}@example.invalid`. You can modify the file with valid parameters.
- Configure your SSH keys for git services in `$USER_DIR/.ssh`.
EOF
  fi
}

register_session() {
  ensure_audit_header
  local start_epoch
  start_epoch="$(date +%s)"

  SESSION_FILE="$STATE_DIR/${LANE}.${MODE,,}.$$.session"
  echo "${LANE}|${MODE}|${NAME}|$$|${start_epoch}|${USER_DIR}" > "$SESSION_FILE"
}

cleanup() {
  if [[ -n "${SESSION_FILE:-}" ]] && [[ -f "$SESSION_FILE" ]]; then
    local end_epoch start_epoch duration start_iso end_iso lane mode name pid home
    end_epoch="$(date +%s)"
    IFS='|' read -r lane mode name pid start_epoch home < "$SESSION_FILE" || true
    duration=$(( end_epoch - start_epoch ))
    start_iso="$(iso_from_epoch "$start_epoch")"
    end_iso="$(iso_from_epoch "$end_epoch")"
    echo "$start_iso,$end_iso,$duration,$lane,$mode,$name,$HOST,$$,${home}" >> "$AUDIT_LOG"

    rm -f "$SESSION_FILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

enter_shell_preserve_lane_env() {
  export CLUSTER_IDENTITY="$NAME"
  export CLUSTER_LANE="$LANE"
  export CLUSTER_MODE="$MODE"

  cd "$HOME"

  echo
  echo ">>> Login sucessfull"
  echo "    Identity  : $NAME"
  echo "    Folder    : $HOME"
  echo "    User      : $LANE"
  echo "    Mode      : $MODE"
  echo
  echo "Tip Git: Your commit identity if on \$HOME/.gitconfig"
  echo

  UID_NUM="$(id -u)"

  if [[ -z "${XDG_RUNTIME_DIR:-}" ]] && [[ -d "/run/user/$UID_NUM" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$UID_NUM"
  fi

  if [[ -z "${DOCKER_HOST:-}" ]] && [[ -S "/run/user/$UID_NUM/docker.sock" ]]; then
    export DOCKER_HOST="unix:///run/user/$UID_NUM/docker.sock"
  fi

  # 3) Entrar a shell interactiva (NO login)
  exec "${SHELL:-/bin/bash}" --rcfile <(head -n -1 "$REAL_HOME/.bashrc") -i
}
# =========================
# Main
# =========================
print_status
choose_identity
choose_mode
bootstrap_person_home
register_session
enter_shell_preserve_lane_env
