#!/usr/bin/env bash

# Parse the dotenv subset used by Docker Compose without executing its values.
load_dotenv_file() {
  local file="$1"
  local line key value first last

  [[ -f "$file" ]] || {
    printf 'ERROR: dotenv file not found: %s\n' "$file" >&2
    return 1
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
      printf 'ERROR: invalid dotenv assignment in %s\n' "$file" >&2
      return 1
    fi

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ -n "$value" ]]; then
      first="${value:0:1}"
      last="${value:${#value}-1:1}"
      if [[ "$first" == "'" || "$first" == '"' ]]; then
        [[ "$last" == "$first" ]] || {
          printf 'ERROR: unmatched quote for %s in %s\n' "$key" "$file" >&2
          return 1
        }
        value="${value:1:${#value}-2}"
      elif [[ "$value" =~ ^(.*[^[:space:]])[[:space:]]+#.*$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
    fi

    printf -v "$key" '%s' "$value"
    export "$key"
  done < "$file"
}

dotenv_value() (
  local file="$1"
  local name="$2"
  printf -v "$name" '%s' ''
  load_dotenv_file "$file" || exit 1
  printf '%s' "${!name}"
)
