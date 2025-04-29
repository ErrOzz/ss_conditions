#!/bin/bash
set -eo pipefail # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
RULES_FILE="../rules/rules_proxy" # Path to the input/output rules file
TEMP_RULES_FILE="${RULES_FILE}.tmp" # Temporary file for processing
COMMENT_TEXT="# not available" # Comment to add for unavailable domains
DOTS_PER_LINE=60 # How many dots to print before a newline

# --- State Variables ---
CHANGED=0 # Flag to track if any changes were made (1 = yes, 0 = no)
PROCESSED_COUNT=0 # Counter for checked domains
UNAVAILABLE_COUNT=0 # Counter for unavailable domains
DOTS_COUNT=0 # Counter for dots printed on the current line

echo "Starting domain availability check for ${RULES_FILE}..."

# Create or clear the temporary rules file safely
# Check permissions before trying to write
TARGET_DIR=$(dirname "$TEMP_RULES_FILE")
if [[ ! -w "$TARGET_DIR" ]]; then
    echo "::error::Target directory '${TARGET_DIR}' for temp file is not writable!"
    ls -ld "$TARGET_DIR" # Show directory permissions
    exit 13
fi
> "$TEMP_RULES_FILE" # Clear/create temp file

# --- Start Domain Checking Group ---
echo "::group::Checking Domains in ${RULES_FILE}"
echo -n "Processing domains: " # Initial prompt for progress dots, -n suppresses newline

# Read the rules file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and lines that are already comments
    if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
        echo "$line" >> "$TEMP_RULES_FILE"
        continue
    fi

    # Extract the clean part of the line (before any # comment) and trim trailing whitespace
    clean_line=$(echo "$line" | sed -e 's/\s*#.*//' -e 's/\s*$//')
    # Extract the original comment part (including #), if it exists
    original_comment=$(echo "$line" | grep -oP '#.*$' || true)

    # Check if the line is a candidate for checking (simple domain, not IP, not wildcard)
    if [[ -n "$clean_line" ]] && \
       [[ ! "$clean_line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/.*)?$ ]] && \
       [[ ! "$clean_line" == *\** ]] && \
       [[ "$clean_line" == *.* ]]; then

        # This is a domain to check
        ((PROCESSED_COUNT++))
        domain_to_check="$clean_line"

        # Try to resolve the domain's A record using Google's DNS
        # +short returns only the IP(s), stderr is discarded (2>/dev/null)
        dig_output=$(dig +short "$domain_to_check" A @8.8.8.8 2>/dev/null)

        # Check if dig returned any output (i.e., resolved to an IP)
        if [[ -n "$dig_output" ]]; then
            # Domain is available
            # Print a dot for progress indication, without a newline
            echo -n "."
            ((DOTS_COUNT++))
            # Check if we need to wrap the line of dots
            if [[ "$DOTS_COUNT" -ge "$DOTS_PER_LINE" ]]; then
                echo "" # Print newline
                echo -n "Processing domains: " # Start new line prompt for dots
                DOTS_COUNT=0
            fi

            # File modification logic: Only change if the "not available" comment needs removing
            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE" # Write the clean line without the old comment
                # Log the removal if needed (currently commented out)
                # echo -e "\n  [INFO] Removing '${COMMENT_TEXT}' for available domain: ${domain_to_check}."
                CHANGED=1 # Mark that a change occurred
            else
                # Domain available, no wrong comment present, write the original line
                echo "$line" >> "$TEMP_RULES_FILE"
            fi
        else
            # Domain is NOT available (dig returned empty output)
            ((UNAVAILABLE_COUNT++))

            # Ensure the warning message starts on a new line if dots were being printed
            if [[ "$DOTS_COUNT" -gt 0 ]]; then
                 echo "" # Print newline to go below the dots
                 DOTS_COUNT=0 # Reset dot counter
                 echo -n "Processing domains: " # Re-print prompt for next potential dots
            fi
            # Print the warning message for the unavailable domain
            echo "[WARN] Domain ${domain_to_check} is NOT available."

            # File modification logic: Only change if the "not available" comment needs adding
            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                # Append the comment, preserving other potential comments after the first #
                existing_comment_part="${original_comment#\#}" # Get comment text after the first #
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE"
                # Log the addition if needed (currently commented out)
                # echo "  [INFO] Adding '${COMMENT_TEXT}' comment for: ${domain_to_check}"
                CHANGED=1 # Mark that a change occurred
            else
                # Domain unavailable, but correct comment already exists, write original line
                echo "$line" >> "$TEMP_RULES_FILE"
            fi
        fi
    else
        # Line is not a candidate for checking (IP, wildcard, etc.), copy as is
        echo "$line" >> "$TEMP_RULES_FILE"
    fi

done < "$RULES_FILE" # Feed the rules file into the while loop

# Print a final newline if the last output was a line of dots
if [[ "$DOTS_COUNT" -gt 0 ]]; then
    echo ""
fi

# Print summary statistics
echo "Total domains checked: ${PROCESSED_COUNT}"
echo "Unavailable domains found: ${UNAVAILABLE_COUNT}"

# --- End Domain Checking Group ---
echo "::endgroup::"

# --- Start Finalizing Group ---
echo "::group::Finalizing Changes"

# Decide final exit code based on whether changes were made (tracked by CHANGED flag)
# This is slightly more robust than relying only on cmp if file operations had issues
if [[ "$CHANGED" -eq 0 ]]; then
    # No changes were flagged
    echo "No changes required for ${RULES_FILE} based on checks."
    # Verify with cmp just in case the CHANGED logic was flawed
    if ! cmp -s "$RULES_FILE" "$TEMP_RULES_FILE"; then
         echo "::warning:: Flag CHANGED=0 but cmp reports files differ! Check script logic."
         # Decide how to handle this: either force update (exit 1) or trust the flag (exit 0)
         # For safety, let's trust the comparison if files differ unexpectedly
         mv "$TEMP_RULES_FILE" "$RULES_FILE"
         echo "::notice file=${RULES_FILE}::${RULES_FILE} updated (due to cmp mismatch)."
         echo "::endgroup::"
         exit 1
    fi
    # Files are identical according to cmp and flag
    rm "$TEMP_RULES_FILE" # Remove the temporary file
    echo "::endgroup::"
    exit 0 # Exit with 0 (success, no changes)
else
    # Changes were flagged
    echo "Changes detected in ${RULES_FILE}. Updating..."
    # Optional: Verify with cmp before moving, though CHANGED should be reliable
    # if cmp -s "$RULES_FILE" "$TEMP_RULES_FILE"; then
    #     echo "::warning:: Flag CHANGED=1 but cmp reports files are identical! Check script logic."
    #     rm "$TEMP_RULES_FILE"
    #     echo "::endgroup::"
    #     exit 0 # Exit 0 if files ended up being the same
    # fi
    # Proceed with update
    mv "$TEMP_RULES_FILE" "$RULES_FILE" # Replace the original file
    echo "::notice file=${RULES_FILE}::${RULES_FILE} updated."
    echo "::endgroup::"
    exit 1 # Exit with 1 (indicates changes were made)
fi