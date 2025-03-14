#!/bin/bash

# Version 1.0
# Made by: Edgar RP
# Updated: 2025_03_07 (AAAA_MM_DD)
# Script to replace the DEVICE_TYPE string in all scripts stored in /usr/local/bin folder

set -e # To avoid any non-zero output to stop the script

grep -RIl 'DEVICE_TYPE' /usr/local/bin/ | xargs sed -i 's/DEVICE_TYPE/<type>/g'
