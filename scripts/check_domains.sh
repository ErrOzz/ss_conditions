#!/bin/bash
set -eo pipefail

RULES_FILE="../rules/rules_proxy"
TEMP_RULES_FILE="${RULES_FILE}.tmp"
COMMENT_TEXT="# not available"
HTTP_CHECK_TIMEOUT=5

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

        available=false # Use a flag for clarity

        # 1. Try to resolve A record
        a_record_output=$(dig +short "$domain_to_check" A @8.8.8.8 2>/dev/null)

        if [[ -n "$a_record_output" ]]; then
            available=true
        else
        # 2. If A record not found, try to resolve CNAME record
            # Run dig CNAME and capture exit code
            set +e # Temporarily disable exit on error to capture exit code
            cname_record_output=$(dig +short "$domain_to_check" CNAME @8.8.8.8 2>/dev/null)
            dig_cname_exit_code=$? # Capture exit code of dig CNAME
            set -e # Re-enable exit on error
            
            # Consider available if dig CNAME succeeded (exit 0)
            if [[ $dig_cname_exit_code -eq 0 && -n "$cname_record_output" ]]; then
                available=true
                # echo "[DEBUG] DNS CNAME record found for ${domain_to_check}: ${cname_record_output}"
            fi
        fi
        # 3. If both A and CNAME records are not found, check HTTP/S availability
        if [[ "$available" == false ]]; then
            # echo "[INFO] DNS check failed for ${domain_to_check}. Attempting HTTP/S check..."
            # Try to access the domain via HTTP/S
            # curl: -s (silent), -I (HEAD request), -L (follow redirects), -f (fail on server errors 4xx, 5xx)
            #       --max-time (timeout), -o /dev/null (discard body)
            # &>/dev/null redirects both stdout and stderr to /dev/null
            if curl -s -I -L -f --max-time "$HTTP_CHECK_TIMEOUT" "https://${domain_to_check}" &>/dev/null || \
               curl -s -I -L -f --max-time "$HTTP_CHECK_TIMEOUT" "http://${domain_to_check}" &>/dev/null; then
                available=true
                # echo "[INFO] HTTP/S check successful for ${domain_to_check}."
            # else
                # echo "[DEBUG] HTTP/S check also failed for ${domain_to_check}."
            fi
        fi

        # Final decision and logging in the rules file
        if [[ "$available" == true ]]; then
            # Domain is considered available
            # Logging for available domains is skipped for brevity
            # echo "  Domain ${domain_to_check} is available (A/CNAME found)."

            # File modification logic: Remove comment if needed
            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE" # Write without comment
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Write original line
            fi
        else
            # Domain is NOT available
            echo "[WARN] Domain ${domain_to_check} is NOT available (DNS and HTTP/S checks failed)." # Keep log
            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                existing_comment_part="${original_comment#\#}" # Get original comment text after #
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE" # Add comment
            else
                echo "$line" >> "$TEMP_RULES_FILE" # Comment already exists, write original
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
    # Set output variable to indicate no changes
    echo "changes_made=false" >> "$GITHUB_OUTPUT"
    echo "::endgroup::"
else
    # File contents differ -> Update the original file
    echo "Changes detected in ${RULES_FILE}. Updating..."
    mv "$TEMP_RULES_FILE" "$RULES_FILE" # 
    echo "::notice file=${RULES_FILE}::${RULES_FILE} updated."
    # Set output variable to indicate changes
    echo "changes_made=true" >> "$GITHUB_OUTPUT"
    echo "::endgroup::"
fi
exit 0