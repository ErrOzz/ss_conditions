#!/bin/bash
set -euo pipefail # Enable strict mode

# Read rules_proxy once
mapfile -t rules_proxy_lines < ./rules/rules_proxy

# --- Constants ---
RULES_FILE="../rules/rules_proxy"
TEMPLATE_DIR="../templates"
OUTPUT_DIR=".."

PAC_TEMPLATE="${TEMPLATE_DIR}/ss_conditions_template.pac"
CONF_TEMPLATE="${TEMPLATE_DIR}/ss_conditions_template.conf"

PORTS=(1080 1081 1082) # List of ports for PAC

PAC_BASE_NAME="ss_conditions"
ACL_OUTPUT_FILE="${OUTPUT_DIR}/ss_conditions.acl"
CONF_OUTPUT_FILE="${OUTPUT_DIR}/ss_conditions.conf"
CLASH_CONF_OUTPUT_FILE="${OUTPUT_DIR}/ss_conditions_clash.conf"
CLASH_RULES_OUTPUT_FILE="${OUTPUT_DIR}/clash_proxy_rules.yaml"

# --- Input File Checks ---
if [[ ! -f "$RULES_FILE" ]]; then
  echo "::error file=$RULES_FILE::Error: Rules file not found!" >&2
  exit 1
fi
if [[ ! -f "$PAC_TEMPLATE" ]]; then
  echo "::error file=$PAC_TEMPLATE::Error: PAC template not found!" >&2
  exit 1
fi
if [[ ! -f "$CONF_TEMPLATE" ]]; then
  echo "::error file=$CONF_TEMPLATE::Error: CONF template not found!" >&2
  exit 1
fi

# --- Read and Filter Rules ---
echo "::group::Filtering Rules" # Start a collapsible group
mapfile -t filtered_lines < <(grep -vE '^#|^$' "$RULES_FILE")
if [[ ${#filtered_lines[@]} -eq 0 ]]; then
    # Use ::warning:: for non-critical issues
    echo "::warning file=$RULES_FILE::Rules file is empty or contains only comments/blank lines."
fi
echo "Found ${#filtered_lines[@]} rules to process."
echo "::endgroup::" # End the group

# --- Prepare arrays for different formats ---
pac_rules=()
acl_rules=()
conf_rules=() # Use one array for both CONF and Clash CONF

# --- Single Loop for Rule Processing ---
echo "::group::Processing Rules into Formats"
# ... (the loop content remains the same) ...
for line in "${filtered_lines[@]}"; do
    # PAC logic
    # If it looks like a 2nd level domain (x.y) and doesn't start with '*.', prepend '*.'
    if [[ $line == *.* && $line != *.*.* && ${line:0:2} != '*.' ]]; then
        pac_rules+=("*.$line"); else pac_rules+=("$line")
    fi
    # ACL logic
    if [[ $line == *.*.*.* && ${line:0:2} != '*.' ]]; then
        acl_rules+=("$line")  # IP CIDR - no changes
    elif [[ $line == *.*.* && ${line:0:2} != '*.' ]]; then
        # Exact 3rd level domain: escape dots, add anchors ^$
        acl_rules+=("^${line//./\\.}")
    elif [[ $line == *.* ]]; then
        # 2nd level domain or wildcard: escape dots, add non-capturing group for start or dot, add end anchor $
        acl_rules+="(?:^|\\.)${line//./\\.}"
    else
        acl_rules+=("$line")
    fi
    # CONF logic
    if [[ $line == *.*.*.* && ${line:0:2} != '*.' ]]; then
        conf_rules+=("IP-CIDR,$line,PROXY") # IP CIDR rule
    else
        conf_rules+=("DOMAIN-SUFFIX,$line,PROXY") # Domain rule
    fi
done
echo "Rule processing complete."
echo "::endgroup::"

# --- Generate PAC Files ---
echo "::group::Generating PAC Files"
# Create JS array lines efficiently, handling the trailing comma
pac_rules_json_array=""
if [[ ${#pac_rules[@]} -gt 0 ]]; then
    pac_rules_json_array=$(printf '  "%s",\n' "${pac_rules[@]}") # Create JS array lines
    pac_rules_json_array=${pac_rules_json_array%,*} # Remove the trailing comma
fi

for port in "${PORTS[@]}"; do
    output_pac_file="${OUTPUT_DIR}/${PAC_BASE_NAME}_${port}.pac"
    echo "Writing $output_pac_file..."
    # Start PAC file
    echo "var __BLOCKEDSITES__ = [" > "$output_pac_file"
    # Add processed rules if any exist
    if [[ -n "$pac_rules_json_array" ]]; then
        echo "$pac_rules_json_array" >> "$output_pac_file"
    fi
    # Close the array
    echo "];" >> "$output_pac_file"
    # Append template with port substitution
    sed "s/PORT_NUM/${port}/g" "$PAC_TEMPLATE" >> "$output_pac_file"
    # Use ::notice:: to highlight file creation
    echo "::notice file=${output_pac_file}::Created PAC file."
done
echo "::endgroup::"

# --- Generate ACL File ---
echo "::group::Generating ACL File"
# ... (ACL generation logic) ...
{   
    echo "[bypass_all]"
    echo ""
    echo "[proxy_list]"
    printf '%s\n' "${acl_rules[@]}" # Print rules efficiently, one per line
} > "$ACL_OUTPUT_FILE"
echo "::notice file=${ACL_OUTPUT_FILE}::Created ACL file."
echo "::endgroup::"

# --- Generate CONF File ---
echo "::group::Generating CONF File"
# Copy the template first
cp "$CONF_TEMPLATE" "$CONF_OUTPUT_FILE"
# Append processed rules
printf '%s\n' "${conf_rules[@]}" >> "$CONF_OUTPUT_FILE"
# Append final rule
echo "FINAL,DIRECT" >> "$CONF_OUTPUT_FILE"
echo "::notice file=${CONF_OUTPUT_FILE}::Created CONF file."
echo "::endgroup::"

# --- Generate Clash CONF File ---
echo "::group::Generating Clash CONF File"
# Note: This uses the same rule logic as the standard CONF file
{
    printf '%s\n' "${conf_rules[@]}" # Print processed rules directly
    echo "FINAL,DIRECT" # Append final rule
} > "$CLASH_CONF_OUTPUT_FILE"
echo "::notice file=${CLASH_CONF_OUTPUT_FILE}::Created Clash CONF file."
echo "::endgroup::"

# Final completion message
echo "::notice::Configuration file generation complete."

# --- Generate Clash Rule Provider File ---
echo "::group::Generating Clash Rule Provider file..."
{
    echo "payload:"
    for line in "${filtered_lines[@]}"; do
        # IP CIDR rule
        if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/.*)?$ ]]; then
            echo "  - IP-CIDR,$line,PROXY" >> "$CLASH_RULES_OUTPUT_FILE"
            continue
        else
            # DOMAIN-SUFFIX rule
            local clash_line=${line#\*\.}
            echo "  - DOMAIN-SUFFIX,${clash_line},PROXY"
        fi
    done
} > "$CLASH_RULES_OUTPUT_FILE"
echo "::notice file=${CLASH_RULES_OUTPUT_FILE}::Created Clash Rule Provider file."
echo "::endgroup::"