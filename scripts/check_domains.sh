#!/bin/bash
set -eo pipefail

RULES_FILE="../rules/rules_proxy"
TEMP_RULES_FILE="${RULES_FILE}.tmp"
COMMENT_TEXT="# not available"

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
        # echo "Checking domain: ${domain_to_check}..." # Keep commented for minimal log

        # 1. Try to resolve A record
        a_record_output=$(dig +short "$domain_to_check" A @8.8.8.8 2>/dev/null)

        # 2. If A record not found, try to resolve CNAME record
        cname_record_output="" # Initialize empty
        if [[ -z "$a_record_output" ]]; then
            cname_record_output=$(dig +short "$domain_to_check" CNAME @8.8.8.8 2>/dev/null)
        fi

        # 3. Consider domain "available" for the list if EITHER A or CNAME record exists
        if [[ -n "$a_record_output" || -n "$cname_record_output" ]]; then
            # Domain is considered available (either direct IP or CNAME exists)
            # Print a dot for progress
            echo -n "."
            ((DOTS_COUNT++))
            if [[ "$DOTS_COUNT" -ge "$DOTS_PER_LINE" ]]; then
                echo ""
                echo -n "Processing domains: "
                DOTS_COUNT=0
            fi

            # File modification logic: Only change if the "not available" comment needs removing
            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE"
                # Log removal if needed
                # echo -e "\n  [INFO] Removing '${COMMENT_TEXT}' for available domain (A/CNAME found): ${domain_to_check}."
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write the original line as is
            fi
        else
            # Domain is NOT available (neither A nor CNAME found)
            ((UNAVAILABLE_COUNT++))
            if [[ "$DOTS_COUNT" -gt 0 ]]; then
                 echo ""
                 DOTS_COUNT=0
                 echo -n "Processing domains: "
            fi
            echo "[WARN] Domain ${domain_to_check} is NOT available (No A or CNAME)."

            # File modification logic: Only change if the "not available" comment needs adding
            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                # Append the comment, preserving other potential comments
                # Check if # already exists in the original line
                existing_comment_part="${original_comment#\#}" # Delete the leading #
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE"
                # Log addition if needed
                # echo "  [INFO] Adding '${COMMENT_TEXT}' comment for: ${domain_to_check}"
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write the original line as is
            fi
        fi
    else
        # Line is not a candidate for checking (IP, wildcard, etc.), copy as is
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
    rm "$TEMP_RULES_FILE" # Delete the temporary file
    # Set output parameter 'changes_made' to 'false'
    echo "::set-output name=changes_made::false"
    echo "::endgroup::"
    exit 0 # 
else
    # File contents differ -> Update the original file
    echo "Changes detected in ${RULES_FILE}. Updating..."
    mv "$TEMP_RULES_FILE" "$RULES_FILE" # 
    echo "::notice file=${RULES_FILE}::${RULES_FILE} updated."
    # Set
    echo "::set-output name=changes_made::true"
    echo "::endgroup::"
    exit 0
fi