#!/bin/bash

# Version 1.1
# Made by: Edgar RP
# Updated: 2025_03_26 (AAAA_MM_DD)
# Script to replace the DEVICE_TYPE string in all scripts stored in /usr/local/bin folder

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

echo "Replacing the DEVICE_TYPE string in all scripts stored in ${PWD}/scripts folder"
grep -RIl 'DEVICE_TYPE' ${PWD}/scripts/ | xargs sed -i 's/DEVICE_TYPE/<type>/g'
echo "Done!"
exit 0
