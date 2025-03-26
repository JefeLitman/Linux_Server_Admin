#!/bin/bash

# Version 1.0
# Made by: Edgar RP
# Updated: 2025_03_26 (AAAA_MM_DD)
# Script to link the scripts files into /usr/local/bin as root user to enable the update of scripts on the fly

set -e # To avoid any non-zero output to stop the script

# Check if the user is root
if [ "$EUID" -ne 0 ]; then 
    echo "WARNING! Only be executed by the root user"
    exit 1
fi
# Check if the folder scrips exists
if [ ! -d "${PWD}/scripts" ]; then
    echo "This script should be executed in the repository root folder where the folder scripts exists"
    exit 1
fi
# Iterate over the files in the scripts folder
echo "Linking the scripts files into /usr/local/bin"
for file in $(ls ${PWD}/scripts); do
    ln -s "${PWD}/scripts/${file}" "/usr/local/bin/${file}"
done
echo "Done!"
exit 0
