#!/bin/bash

# Version 2026.04.24.2
# Made by: Josue Rodriguez de la Rosa & Edgar RP
# Script to enable a multi user environment in a single shared user organizing files into Users folder.

# --- Configuration ---
USER_DIR="$HOME/Users"

# Function to sanitize a username
# Converts to lowercase and removes characters that are invalid for filenames.
sanitize_username() {
    local username="$1"
    # Convert to lowercase
    local sanitized=$(echo "$username" | tr '[:upper:]' '[:lower:]')

    # Remove characters that are invalid for folder names (keeping only alphanumeric, -, _, .)
    sanitized=$(echo "$sanitized" | sed -E 's/[^a-z0-9._-]+//g')

    # Handle cases where sanitization results in an empty string
    if [ -z "$sanitized" ]; then
        echo ""
        return 1
    fi
    echo "$sanitized"
}

# Function to ensure the necessary user directory structure exists
setup_user_environment() {
    if [ ! -d "$USER_DIR" ]; then
        echo "Creating central user directory at $USER_DIR..."
        mkdir -p "$USER_DIR"
    fi
}

# Function to get the list of available users from the system
get_available_users() {
    # List directories under $HOME/Users
    find "$USER_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort
}

# Function to create and initialize a new user account folder
create_new_user() {
    local input_username="$1"
    local sanitized_username
    local user_path

    # 1. Sanitize the input name
    sanitized_username=$(sanitize_username "$input_username")

    if [ -z "$sanitized_username" ]; then
        echo "Error: The provided username '$input_username' is invalid after sanitization. Please use only letters, numbers, dashes, underscores, and periods."
        return 1
    fi

    user_path="$USER_DIR/$sanitized_username"

    if [ -d "$user_path" ]; then
        echo "Error: User directory '$user_path' already exists. Please use the menu to select it."
        return 1
    fi

    echo -e "\n======================================================="
    echo "Creating new user directory for: $sanitized_username"
    echo "======================================================="

    # 2. Create the directory
    if mkdir -p "$user_path"; then
        echo "Successfully created user directory: $user_path"
        return 0
    else
        echo "Error: Failed to create user directory. Check permissions."
        return 1
    fi
}

# Function to display the interactive user menu
display_menu() {
    echo -e "\n======================================================="
    echo "User Selection Menu"
    echo "======================================================="

    local user_list=()
    local index=1
    local user

    # Fetch the list of available users
    readarray -t user_list < <(get_available_users)

    if [ ${#user_list[@]} -eq 0 ]; then
        return 2 # Return code 2 indicates no users found. No users found in $USER_DIR. Run the script again to create a new user.
    fi

    echo "Please select a user from the list below by entering the number:"

    for user in "${user_list[@]}"; do
        echo "$index) $user"
        index=$((index + 1))
    done
    echo "-------------------------------------------------------"

    # Prompt the user for input
    read -rp "Enter selection number (1-${#user_list[@]})): " selection

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#user_list[@]} ]; then
        echo "Error: Invalid selection number. Please try again."
        return 1
    fi

    # Return the selected username (which is 1-indexed)
    local selected_index=$((selection - 1))
    echo "${user_list[selected_index]}"
    return 0
}

# Function to switch the user's environment
# Takes the sanitized username as input.
switch_user() {
    local username="$1"
    local user_path="$USER_DIR/$username"

    if [ ! -d "$user_path" ]; then
        echo "Error: User directory '$user_path' does not exist. Cannot switch user."
        return 1
    fi

    echo -e "\n======================================================="
    echo "Attempting to switch user environment to: $username"
    echo "======================================================="

    # CRITICAL: Update the environment variable for the current shell process.
    export HOME="$user_path"

    # Also update PATH, assuming new users might have their binaries here
    export PATH="$user_path/bin:$PATH"

    echo "SUCCESS: HOME variable has been updated for this session."
    echo "======================================================"
    echo "The new environment variables are set. Your current working directory is: $(pwd)"
    echo "To verify, run 'echo \$HOME' or 'pwd' in your next command."
    return 0
}

# Main execution block
main() {
    # 1. Setup directory structure
    setup_user_environment

    # 2. Display menu and get user selection
    echo "--- Running Multi-User Login Script ---"
    local SELECTED_USER=$(display_menu)
    local return_code=$?
    echo "display_menu return code $return_code"

    # 3. Handle user selection failure or new user creation
    if [ $return_code -eq 2 ]; then
        # No users found - prompt for creation
        echo -e "\n--- No users found. Please create one! ---"
        read -rp "Please enter the desired new username: " NEW_USERNAME

        if [ -n "$NEW_USERNAME" ]; then
            # Attempt to create the user directory
            NEW_USER_RESULT=$(create_new_user "$NEW_USERNAME")
            local create_return_code=$?

            if [ $create_return_code -eq 0 ]; then
                # If creation was successful, proceed to switch user
                echo "User directory created. Now switching environment..."
                switch_user "$sanitized_username" # Note: Using sanitized_username from the function scope
                # Re-evaluate the return code based on switch_user success
                local switch_return_code=$?
                if [ $switch_return_code -ne 0 ]; then
                    echo "FATAL: Failed to switch user after successful creation. Please check permissions."
                    return 1
                fi
            else
                echo "Failed to create user directory. Cannot proceed."
                return 1
            fi
        else
            echo "User creation cancelled. Exiting."
            return 1
        fi

    elif [ $return_code -eq 0 ]; then
        # User selected successfully
        switch_user "$SELECTED_USER"
    else
        # Other errors (e.g., invalid selection)
        echo "Exiting script due to user selection failure or directory error."
        return 1
    fi
}

# Execute the main function
main "$@"
