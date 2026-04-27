#!/bin/bash

# Version 2026.04.27.1
# Made by: Josue Rodriguez de la Rosa & Edgar RP
# This script allows a user to select their respective username from a shared user directory and export the $HOME environment variable accordingly. To enable its functionality you should have a shared user for multiple people and add `souce <path_2_script>/multiuser_login.sh` into user bashrc.
# TODO: Fix errors regarding the gitconfig and .ssh folder tring to be executed.

# Function to sanitize username
sanitize_username() {
    local user_name="$1"
    # Convert to lowercase
    local sanitized=$(echo "$user_name" | tr '[:upper:]' '[:lower:]')
    # Remove characters that are invalid for folder names (keeping only alphanumeric, -, _, .)
    sanitized=$(echo "$sanitized" | sed -E 's/[^a-z0-9._-]+//g')
    echo $sanitized
}

# --- Configurations ---
SHARED_USER="$(whoami)"
USERS_DIR="$HOME/Users"
HOST="$(hostname -s 2>/dev/null || hostname)"
if [ ! -d "$USERS_DIR" ]; then
    echo "Users directory not found at $USERS_DIR. Creating it now..."
    mkdir -p "$USERS_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Could not create $USERS_DIR. Exiting."
        exit 1
    fi
fi
# Get all directories, exclude system directories, and store them in an array
USERNAMES=($(find "$USERS_DIR" -mindepth 1 -maxdepth 1 -type d -not -wholename "$USERS_DIR/." -not -wholename "$USERS_DIR/.." | sort))
# Clean up the names by stripping the full path prefix
USERNAMES=($(for dir in "${USERNAMES[@]}"; do basename "$dir"; done))

main() {
    # Banner welcome screen
    echo "============================================================"
    echo "$SHARED_USER Login | Host: $HOST"
    echo "============================================================"

    # Display the selection menu
    PS3='Who are you? (Pick a number) '
    select USERNAME in "Add a new user" "${USERNAMES[@]}"; do
        # The selected value is stored in $NAME (the last argument passed to select)
        SELECTED_USER="$USERNAME"
        if [ "$SELECTED_USER" == "Add a new user" ]; then
            read -p "Please enter the desired new username: " NEW_USERNAME_INPUT
            # Sanitize the input
            SANITIZED_USERNAME=$(sanitize_username "$NEW_USERNAME_INPUT")

            if [ -z "$SANITIZED_USERNAME" ]; then
                echo "Error: Username cannot be empty or contains invalid characters (only a-z 0-9 . _ -). Exiting."
                exit 1
            fi

            # Create the directory for the new user
            NEW_USER_DIR="$USERS_DIR/$SANITIZED_USERNAME"
            if [ -d "$NEW_USER_DIR" ]; then
                echo "Error: Directory $NEW_USER_DIR already exists. Please try another creating another user or select that."
                # Re-run selection to allow user to pick the existing name
                # (A proper implementation would loop until success, but for now, we exit)
                exit 1
            fi

            echo "Your folder data will be: $NEW_USER_DIR"
            echo "(Note: Your username always be lowercase and without blank spaces.)"
            mkdir -p "$NEW_USER_DIR"
            if [ $? -ne 0 ]; then
                echo "Error: Could not create user directory $NEW_USER_DIR. Exiting."
                exit 1
            fi
            SELECTED_USER="$SANITIZED_USERNAME"
        fi
        # After selecting or creating a user, export the $HOME environment variable only when valid options are selected
        if [[ -d "$USERS_DIR/$SELECTED_USER" && -n "$SELECTED_USER" ]]; then
            # Creating required files and folders for the user
            if [ ! -d "$USERS_DIR/$SELECTED_USER/.ssh" ]; then
                echo "Creating $SELECTED_USER ssh folder..."
                mkdir -p -m 700 "$USERS_DIR/$SELECTED_USER/.ssh"
            fi
            if [[ ! -f "$USERS_DIR/$SELECTED_USER/.gitconfig" ]]; then
                echo "Creating $SELECTED_USER gitconfig template file..."
                install -m 755 /dev/null "$USERS_DIR/$SELECTED_USER/.gitconfig"
                echo -e "[user]\n    name = $SELECTED_USER\n    email = $SELECTED_USER@example.invalid\n" > "$USERS_DIR/$SELECTED_USER/.gitconfig"
            fi
            # Helpful note
            if [[ ! -f "$USERS_DIR/$SELECTED_USER/README.txt" ]]; then
                echo "Creating $SELECTED_USER recommendations file..."
                install -m 755 /dev/null "$USERS_DIR/$SELECTED_USER/README.txt"
                cat > "$USERS_DIR/$SELECTED_USER/README.txt" <<EOF
Personal workspace for: $SELECTED_USER
User: $SHARED_USER

Recommended practices:
- Keep your code sync with a Git service (Github, Gitlab, etc) and do pull/push frequently. The data can be lost sometimes due to disks failure.
- Your commit identification is defined by default in `$USERS_DIR/$SELECTED_USER/.gitconfig` with `user.name=$SELECTED_USER` and `user.email=$SELECTED_USER@example.invalid`. You can modify the file with valid parameters.
- Configure your SSH keys for git services in `$USERS_DIR/$SELECTED_USER/.ssh`.
EOF
            fi

            export HOME="$USERS_DIR/$SELECTED_USER"
            echo "Successfully set HOME to: $HOME"
            break
        fi
    done
}
main
