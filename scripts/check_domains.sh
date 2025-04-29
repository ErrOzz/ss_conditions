#!/bin/bash
set -eo pipefail

RULES_FILE="../rules/rules_proxy"
TEMP_RULES_FILE="${RULES_FILE}.tmp"
COMMENT_TEXT="# not available"
CHANGED=0 # Flag to track if any changes were made

echo "Starting domain availability check for ${RULES_FILE}..."

> "$TEMP_RULES_FILE" # Create or clear the temporary rules file

# --- Start Domain Checking Group ---
echo "::group::Checking Domains in ${RULES_FILE}"

# Read the rules file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
        echo "$line" >> "$TEMP_RULES_FILE"
        continue
    fi

    # Extract the domain from the line
    # Remove comments and trailing spaces, keep leading spaces if any
    clean_line=$(echo "$line" | sed -e 's/\s*#.*//' -e 's/\s*$//')
    # Extract the original comment if it exists
    original_comment=$(echo "$line" | grep -oP '#.*$' || true)

    # Check if the line is a candidate for checking (not empty, not IP, not wildcard, contains dot)
    if [[ -n "$clean_line" ]] && \
       [[ ! "$clean_line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/.*)?$ ]] && \
       [[ ! "$clean_line" == *\** ]] && \
       [[ "$clean_line" == *.* ]]; then
        domain_to_check="$clean_line"
        echo "Checking domain: ${domain_to_check}..."

        # Trying to resolve the domain (A record). +short outputs only the IP address
        # stderr to /dev/null to suppress error messages
        # Check dig exit status and if output contains a dot (likely an IP)
        dig_output=$(dig +short "$domain_to_check" A @8.8.8.8 2>/dev/null)
        # Verify if dig_output is not empty
        if [[ -n "$dig_output" ]]; then
            # Output is not empty -> Domain is available
            # Add IP address to the comment if it exists
            echo "  Domain ${domain_to_check} is available (Resolved: ${dig_output})."
            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE" # Write the clean line without the comment
                echo "  Removing '${COMMENT_TEXT}' comment."
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write the original line as is
            fi
        else
            # Output is empty -> Domain is NOT available
            echo "  Domain ${domain_to_check} is NOT available."
            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                # Append the comment, preserving other potential comments
                # Check if # already exists in the original line
                existing_comment_part="${original_comment#\#}" # Delete the leading #
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE"
                echo "  Adding '${COMMENT_TEXT}' comment."
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write the original line as is
            fi
        fi
    else
        # If the line is not a domain to check, write it as is
        echo "$line" >> "$TEMP_RULES_FILE"
    fi

done < "$RULES_FILE"

# --- End Domain Checking Group ---
echo "::endgroup::"

# --- Start Finalizing Group ---
echo "::group::Finalizing Changes"

# Replace the original rules file with the temporary one if changes were made
if cmp -s "$RULES_FILE" "$TEMP_RULES_FILE"; then
    echo "No changes detected in ${RULES_FILE}."
    rm "$TEMP_RULES_FILE" # Remove the temporary file
    echo "::endgroup::" # End group here if no changes
    exit 0
else
    echo "Changes detected in ${RULES_FILE}. Updating..."
    mv "$TEMP_RULES_FILE" "$RULES_FILE" # Replace the original file with the updated one
    echo "::notice file=${RULES_FILE}::${RULES_FILE} updated."
    echo "::endgroup::" # End group here after changes
    exit 1 # Exit with 1 to indicate changes were made (useful for CI)
fi