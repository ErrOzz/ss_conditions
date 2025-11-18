#!/bin/bash
set -euo pipefail # Enable strict mode

# --- Constants ---
RULES_FILE="../rules/rules_proxy"
OUTPUT_DIR=".."
CLASH_RULES_OUTPUT_FILE="${OUTPUT_DIR}/clash_proxy_rules.yaml"

# --- Input File Checks ---
if [[ ! -f "$RULES_FILE" ]]; then
    echo "::error file=$RULES_FILE::Error: Rules file not found!" >&2
    exit 1
fi

# --- Read and Filter Rules ---
echo "::group::Filtering Rules" # Start a collapsible group
mapfile -t filtered_lines < <(sed 's/#.*$//' "$RULES_FILE" | grep -vE '^\s*$')
if [[ ${#filtered_lines[@]} -eq 0 ]]; then
    # Use ::warning:: for non-critical issues
    echo "::warning file=$RULES_FILE::Rules file is empty or contains only comments/blank lines."
fi
echo "Found ${#filtered_lines[@]} rules to process."
echo "::endgroup::" # End the group

# Note: The script no longer builds PAC/ACL/CONF arrays —
# we only generate the Clash rule provider file from the filtered rules.

# --- Generate Clash Rule Provider File ---
echo "::group::Generating Clash Rule Provider file..."
{
    echo "payload:"
    for line in "${filtered_lines[@]}"; do
        # Check if it's a keyword (no dots)
        if [[ "$line" != *.* ]]; then
            echo "  - DOMAIN-KEYWORD,$line"
        # Check if it's an IP CIDR rule
        elif [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/.*)?$ ]]; then
            echo "  - IP-CIDR,$line"
            continue
        else # Otherwise, treat as DOMAIN-SUFFIX
            clash_line=${line#\*\.} # Remove leading *. if present
            echo "  - DOMAIN-SUFFIX,${clash_line}"
        fi
    done
} > "$CLASH_RULES_OUTPUT_FILE"
echo "::notice file=${CLASH_RULES_OUTPUT_FILE}::Created Clash Rule Provider file."
echo "::endgroup::"

# Final completion message
echo "::notice::Configuration file generation complete."