#!/bin/bash

# Read rules_proxy once
mapfile -t rules_proxy_lines < ../rules/rules_proxy

# Filter out comments and empty lines
filtered_lines=()
for line in "${rules_proxy_lines[@]}"; do
    if [[ ! $line =~ ^#.*$ && -n $line ]]; then
        filtered_lines+=("$line")
    fi
done

# Use filtered_lines in all subsequent processing

# parse rules_proxy and make PAC files
for line in "${filtered_lines[@]}"; do
# mapfile -t lines < ../rules/rules_proxy
# for ((i=0; i<${#lines[@]}; i++)); do
    # line=${lines[i]}
    # Skip comments and empty lines
    # if [[ $line =~ ^#.*$ || -z $line ]]; then
        # continue
    # fi
    if [[ $line == *.* && $line != *.*.* && ${line:0:2} != '*.' ]]; then
        lines[i]="*.$line"
    fi
done

echo "var __BLOCKEDSITES__ = [" > ../ss_conditions_1080.pac
for line in "${lines[@]}"; do
    echo "  \"$line\"," >> ../ss_conditions_1080.pac
done
sed -i '$ s/,$//' ../ss_conditions_1080.pac
echo "];" >> ../ss_conditions_1080.pac

cat ../ss_conditions_1080.pac > ../ss_conditions_1081.pac
cat ../ss_conditions_1080.pac > ../ss_conditions_1082.pac

sed 's/PORT_NUM/1080/g' ../templates/ss_conditions_template.pac >> ../ss_conditions_1080.pac
sed 's/PORT_NUM/1081/g' ../templates/ss_conditions_template.pac >> ../ss_conditions_1081.pac
sed 's/PORT_NUM/1082/g' ../templates/ss_conditions_template.pac >> ../ss_conditions_1082.pac

# parse rules_proxy and make ACL file
echo "[bypass_all]" > ../ss_conditions.acl
echo "" >> ../ss_conditions.acl
echo "[proxy_list]" >> ../ss_conditions.acl

mapfile -t lines < ../rules/rules_proxy
for line in "${lines[@]}"; do
    # Skip comments and empty lines
    if [[ $line =~ ^#.*$ || -z $line ]]; then
        continue
    fi
    if [[ $line == *.*.*.* && ${line:0:2} != '*.' ]]; then
        transformed_line="$line"
    elif [[ $line == *.*.* && ${line:0:2} != '*.' ]]; then
        transformed_line="^${line//./\\.}$"
    elif [[ $line == *.* ]]; then
        transformed_line="(?:^|\\.)${line//./\\.}$"
    else
        transformed_line="$line"
    fi
    echo "$transformed_line" >> ../ss_conditions.acl
done

# parse rules_proxy and make .CONF file
cat ../templates/ss_conditions_template.conf > ../ss_conditions.conf
mapfile -t lines < ../rules/rules_proxy
for line in "${lines[@]}"; do
    # Skip comments and empty lines
    if [[ $line =~ ^#.*$ || -z $line ]]; then
        continue
    fi
    if [[ $line == *.*.*.* && ${line:0:2} != '*.' ]]; then
        transformed_line="IP-CIDR,$line,PROXY"
    else
        transformed_line="DOMAIN-SUFFIX,$line,PROXY"
    fi
    echo "$transformed_line" >> ../ss_conditions.conf
done
echo "FINAL,DIRECT" >> ../ss_conditions.conf

# parse rules_proxy and make .CONF file for Shadowlink
echo -n "" > ../ss_conditions_clash.conf
mapfile -t lines < ../rules/rules_proxy
for line in "${lines[@]}"; do
    # Skip comments and empty lines
    if [[ $line =~ ^#.*$ || -z $line ]]; then
        continue
    fi
    if [[ $line == *.*.*.* && ${line:0:2} != '*.' ]]; then
        transformed_line="IP-CIDR,$line,PROXY"
    else
        transformed_line="DOMAIN-SUFFIX,$line,PROXY"
    fi
    echo "$transformed_line" >> ../ss_conditions_clash.conf
done
echo "FINAL,DIRECT" >> ../ss_conditions_clash.conf
