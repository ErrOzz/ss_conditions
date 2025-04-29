#!/bin/bash
set -eo pipefail

RULES_FILE="../rules/rules_proxy"
TEMP_RULES_FILE="${RULES_FILE}.tmp"
COMMENT_TEXT="# not available"
CHANGED=0 # Flag to track if any changes were made
PROCESSED_COUNT=0
UNAVAILABLE_COUNT=0
DOTS_COUNT=0 # Счетчик точек на строке
DOTS_PER_LINE=60 # Сколько точек выводить на одной строке

echo "Starting domain availability check for ${RULES_FILE}..."

> "$TEMP_RULES_FILE" # Create or clear the temporary rules file

# --- Start Domain Checking Group ---
echo "::group::Checking Domains in ${RULES_FILE}"

# Выводим начальное сообщение для точек
echo -n "Processing domains: " # -n не добавляет перевод строки

# Read the rules file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
        echo "$line" >> "$TEMP_RULES_FILE"
        continue
    fi

    # Extract the domain from the line
    clean_line=$(echo "$line" | sed -e 's/\s*#.*//' -e 's/\s*$//')
    # Extract the original comment if it exists
    original_comment=$(echo "$line" | grep -oP '#.*$' || true)

    # Check if the line is a candidate for checking (not empty, not IP, not wildcard, contains dot)
    if [[ -n "$clean_line" ]] && \
       [[ ! "$clean_line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/.*)?$ ]] && \
       [[ ! "$clean_line" == *\** ]] && \
       [[ "$clean_line" == *.* ]]; then

        ((PROCESSED_COUNT++))
        domain_to_check="$clean_line"

        # Trying to resolve the domain (A record).
        dig_output=$(dig +short "$domain_to_check" A @8.8.8.8 2>/dev/null)

        if [[ -n "$dig_output" ]]; then
            # Domain is available
            # Print a dot for progress, without newline
            echo -n "."
            ((DOTS_COUNT++))
            # Check if we need to wrap the line of dots
            if [[ "$DOTS_COUNT" -ge "$DOTS_PER_LINE" ]]; then
                echo "" # New line
                echo -n "Processing domains: " # Start new line of dots
                DOTS_COUNT=0
            fi

            # Only update file if comment needs removing
            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE"
                # Optionally log removal (uncomment if needed)
                # echo -e "\n  [INFO] Removing '${COMMENT_TEXT}' for available domain: ${domain_to_check}."
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write the original line as is
            fi
        else
            # Domain is NOT available
            ((UNAVAILABLE_COUNT++))
            # Ensure we start on a new line before printing error message
            # If the last output was a dot (no newline), print a newline first
            if [[ "$DOTS_COUNT" -gt 0 ]]; then
                 echo "" # Print newline to clear the dot line
                 DOTS_COUNT=0 # Reset dot counter for the next line
            fi
            # Print the unavailable domain info
            echo "[WARN] Domain ${domain_to_check} is NOT available."

            # Only update file if comment needs adding
            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                # Append the comment, preserving other potential comments
                # Check if # already exists in the original line
                existing_comment_part="${original_comment#\#}" # Delete the leading #
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE"
                echo "  [INFO] Adding '${COMMENT_TEXT}' comment for: ${domain_to_check}"
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Comment already exists
            fi
             # Start new line for dots after printing unavailable domain info
            echo -n "Processing domains: "
        fi
    else
        # If the line is not a domain to check, write it as is
        echo "$line" >> "$TEMP_RULES_FILE"
    fi

done < "$RULES_FILE"

# Print a final newline if the last output was dots
if [[ "$DOTS_COUNT" -gt 0 ]]; then
    echo ""
fi

echo "Total domains checked: ${PROCESSED_COUNT}"
echo "Unavailable domains found: ${UNAVAILABLE_COUNT}"

# --- End Domain Checking Group ---
echo "::endgroup::"

# --- Start Finalizing Group ---
echo "::group::Finalizing Changes"

# Replace the original rules file with the temporary one if changes were made
if [[ "$CHANGED" -eq 0 ]]; then
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