#!/bin/bash
set -eo pipefail

RULES_FILE="../rules/rules_proxy"
TEMP_RULES_FILE="${RULES_FILE}.tmp"
COMMENT_TEXT="# not available"
CHANGED=0
PROCESSED_COUNT=0
UNAVAILABLE_COUNT=0
DOTS_COUNT=0
DOTS_PER_LINE=60

echo "Starting domain availability check..."
echo "[DEBUG] Current directory: $(pwd)"
echo "[DEBUG] Checking source file: ${RULES_FILE}"

# 1. Проверяем существование и права на чтение исходного файла
if [[ ! -f "$RULES_FILE" ]]; then
    echo "::error::Source file '${RULES_FILE}' not found or is not a regular file!"
    ls -l "$(dirname "$RULES_FILE")" # Посмотрим содержимое директории
    exit 10 # Выход с уникальным кодом
elif [[ ! -r "$RULES_FILE" ]]; then
    echo "::error::Source file '${RULES_FILE}' is not readable!"
    ls -l "$RULES_FILE" # Посмотрим права файла
    exit 11 # Выход с уникальным кодом
else
    echo "[DEBUG] Source file '${RULES_FILE}' exists and is readable."
fi

echo "[DEBUG] Checking target directory for temp file: $(dirname "$TEMP_RULES_FILE")"
# 2. Проверяем права на запись в директорию для временного файла
TARGET_DIR=$(dirname "$TEMP_RULES_FILE")
if [[ ! -d "$TARGET_DIR" ]]; then
     echo "::error::Target directory '${TARGET_DIR}' for temp file does not exist!"
     ls -l "$(dirname "$TARGET_DIR")" # Посмотрим родительскую директорию
     exit 12
elif [[ ! -w "$TARGET_DIR" ]]; then
    echo "::error::Target directory '${TARGET_DIR}' for temp file is not writable!"
    ls -ld "$TARGET_DIR" # Посмотрим права самой директории
    exit 13 # Выход с уникальным кодом
else
    echo "[DEBUG] Target directory '${TARGET_DIR}' exists and is writable."
fi

echo "[DEBUG] Attempting to create/clear temp file: ${TEMP_RULES_FILE}"
# 3. Пытаемся создать временный файл (используем set +e временно для проверки)
set +e
> "$TEMP_RULES_FILE"
EXIT_CODE_TMP=$?
set -e # Возвращаем строгий режим
if [[ $EXIT_CODE_TMP -ne 0 ]]; then
     echo "::error::Failed to create/clear temp file '${TEMP_RULES_FILE}'. Exit code: ${EXIT_CODE_TMP}"
     ls -l "$TARGET_DIR" # Посмотрим содержимое директории
     exit 14
else
     echo "[DEBUG] Temp file '${TEMP_RULES_FILE}' created/cleared successfully."
fi

# --- Start Domain Checking Group ---
echo "::group::Checking Domains in ${RULES_FILE}"
echo -n "Processing domains: "

# Read the rules file line by line
# Добавим отладку перед циклом
echo "[DEBUG] Starting 'while read' loop..."
while IFS= read -r line || [[ -n "$line" ]]; do
    # И сразу внутри цикла для первой итерации
    echo "[DEBUG] Read line: '$line'"

    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^\s*# ]]; then
        echo "$line" >> "$TEMP_RULES_FILE"
        continue
    fi

    # ... (остальная часть вашего цикла как в предыдущем варианте с точками) ...
    # Extract the domain from the line
    clean_line=$(echo "$line" | sed -e 's/\s*#.*//' -e 's/\s*$//')
    # Extract the original comment if it exists
    original_comment=$(echo "$line" | grep -oP '#.*$' || true)

    # Check if the line is a candidate for checking
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
            echo -n "."
            ((DOTS_COUNT++))
            if [[ "$DOTS_COUNT" -ge "$DOTS_PER_LINE" ]]; then
                echo ""
                echo -n "Processing domains: "
                DOTS_COUNT=0
            fi

            if [[ "$original_comment" == *"$COMMENT_TEXT"* ]]; then
                echo "${clean_line}" >> "$TEMP_RULES_FILE"
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE"
            fi
        else
            # Domain is NOT available
            ((UNAVAILABLE_COUNT++))
            if [[ "$DOTS_COUNT" -gt 0 ]]; then
                 echo ""
                 DOTS_COUNT=0
            fi
            echo "[WARN] Domain ${domain_to_check} is NOT available."

            if [[ "$original_comment" != *"$COMMENT_TEXT"* ]]; then
                existing_comment_part="${original_comment#\#}"
                echo "${clean_line} ${COMMENT_TEXT}${existing_comment_part}" >> "$TEMP_RULES_FILE"
                echo "  [INFO] Adding '${COMMENT_TEXT}' comment for: ${domain_to_check}"
                CHANGED=1
            else
                echo "$line" >> "$TEMP_RULES_FILE"
            fi
            echo -n "Processing domains: "
        fi
    else
        echo "$line" >> "$TEMP_RULES_FILE"
    fi
done < "$RULES_FILE"


if [[ "$DOTS_COUNT" -gt 0 ]]; then
    echo ""
fi

echo "Total domains checked: ${PROCESSED_COUNT}"
echo "Unavailable domains found: ${UNAVAILABLE_COUNT}"

echo "::endgroup::"

# --- Start Finalizing Group ---
echo "::group::Finalizing Changes"

if [[ "$CHANGED" -eq 0 ]]; then
    echo "No changes detected in ${RULES_FILE}."
    rm "$TEMP_RULES_FILE"
    echo "::endgroup::"
    exit 0
else
    echo "Changes detected in ${RULES_FILE}. Updating..."
    # Добавим отладку перед сравнением/перемещением
    echo "[DEBUG] Comparing final files before move/exit..."
    echo "--- BEGIN Original ($RULES_FILE) ---"
    cat "$RULES_FILE"
    echo "--- END Original ($RULES_FILE) ---"
    echo "--- BEGIN Temporary ($TEMP_RULES_FILE) ---"
    cat "$TEMP_RULES_FILE"
    echo "--- END Temporary ($TEMP_RULES_FILE) ---"

    # Проверка еще раз, если вдруг файлы оказались идентичны из-за ошибки логики
    set +e
    cmp -s "$RULES_FILE" "$TEMP_RULES_FILE"
    CMP_RESULT=$?
    set -e
    if [[ "$CMP_RESULT" -eq 0 ]]; then
         echo "::warning::DEBUG: Flag CHANGED=1 but cmp reports files are identical! Check logic. Exiting 0."
         rm "$TEMP_RULES_FILE"
         echo "::endgroup::"
         exit 0
    else
         echo "[DEBUG] cmp reports files differ. Proceeding with mv and exit 1."
         mv "$TEMP_RULES_FILE" "$RULES_FILE"
         echo "::notice file=${RULES_FILE}::${RULES_FILE} updated."
         echo "::endgroup::"
         exit 1
    fi
fi