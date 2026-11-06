#!/usr/bin/env bash

set -euo pipefail

TARGET=${1:-caddy/2.11.9}
declare -a DIRS=()

if [ "$TARGET" = all ]; then
  while IFS= read -r dockerfile; do
    dir=$(dirname "$dockerfile")
    [[ " ${DIRS[*]} " == *" $dir "* ]] || DIRS+=("$dir")
  done < <(find containers -mindepth 3 -maxdepth 3 -type f -name 'Dockerfile*' | sort)
elif [[ "$TARGET" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
  DIRS+=("containers/$TARGET")
else
  echo "Target inválido: $TARGET" >&2
  exit 1
fi

load_tags() {
  local file=$1 value
  [ -f "$file" ] || return 0
  value=$(sed -n 's/^TAGS=//p' "$file" | tail -n 1 | tr -d '\r')
  [ -z "$value" ] || TAGS=$value
}

entries='[]'

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || { echo "Diretório inexistente: $dir" >&2; exit 1; }
  app=$(echo "$dir" | cut -d/ -f2)
  version=$(echo "$dir" | cut -d/ -f3)
  TAGS=
  load_tags "containers/$app/build.conf"
  load_tags "$dir/build.conf"

  found=false
  while IFS= read -r dockerfile_path; do
    found=true
    dockerfile=$(basename "$dockerfile_path")
    variant=${dockerfile#Dockerfile}
    variant=${variant#.}
    suffix=${variant:+-$variant}
    variant_name=${variant:-default}
    image_tags="${version}${suffix},latest${suffix}"
    if [ "$dockerfile" = Dockerfile ] && [ -n "$TAGS" ]; then
      image_tags=$TAGS
    fi

    entries=$(node -e '
      const entries = JSON.parse(process.argv[1]);
      entries.push({
        app: process.argv[2], version: process.argv[3], dockerfile: process.argv[4],
        variant: process.argv[5], suffix: process.argv[6], tags: process.argv[7]
      });
      process.stdout.write(JSON.stringify(entries));
    ' "$entries" "$app" "$version" "$dockerfile" "$variant_name" "$suffix" "$image_tags")
  done < <(find "$dir" -maxdepth 1 -type f -name 'Dockerfile*' | sort)

  $found || { echo "Nenhum Dockerfile encontrado em $dir" >&2; exit 1; }
done

node -e 'process.stdout.write(JSON.stringify({include: JSON.parse(process.argv[1])}))' "$entries"
