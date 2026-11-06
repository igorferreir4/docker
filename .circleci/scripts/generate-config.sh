#!/usr/bin/env bash

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

ALL=false
if [ "${1:-}" = "--all" ]; then
  ALL=true
  shift
fi
OUTPUT=${1:-/tmp/continue.yml}
TEMPLATE=.circleci/continue-template.yml

declare -A SELECTED=()

select_version_dir() {
  local dir=$1
  if find "$dir" -maxdepth 1 -type f -name 'Dockerfile*' -print -quit 2>/dev/null | grep -q .; then
    SELECTED["$dir"]=1
  fi
  return 0
}

select_app() {
  local app_dir=$1 dir
  [ -d "$app_dir" ] || return 0
  for dir in "$app_dir"/*; do
    if [ -d "$dir" ]; then
      select_version_dir "$dir"
    fi
  done
  return 0
}

select_all() {
  local dockerfile
  while IFS= read -r dockerfile; do
    SELECTED["$(dirname "$dockerfile")"]=1
  done < <(find containers -mindepth 3 -maxdepth 3 -type f -name 'Dockerfile*' | sort)
}

changed_files() {
  local base comparison
  if [ -n "${CIRCLE_COMPARE_URL:-}" ] && [[ "$CIRCLE_COMPARE_URL" == *'/compare/'* ]]; then
    comparison=${CIRCLE_COMPARE_URL##*/compare/}
    base=${comparison%%...*}
    git rev-parse "$base" >/dev/null 2>&1 || git fetch origin "$base" --depth=1 || true
    if git rev-parse "$base" >/dev/null 2>&1; then
      git diff --name-only "$base" HEAD
      return
    fi
  fi
  if [ -n "${CIRCLE_BRANCH:-}" ] && [ "$CIRCLE_BRANCH" != "main" ] && git rev-parse origin/main >/dev/null 2>&1; then
    base=$(git merge-base origin/main HEAD)
    git diff --name-only "$base" HEAD
  elif git rev-parse HEAD^ >/dev/null 2>&1; then
    git diff --name-only HEAD^ HEAD
  else
    git ls-files
  fi
}

if $ALL; then
  select_all
else
  while IFS= read -r path; do
    case "$path" in
      containers/0-run-all/*)
        ALL=true
        ;;
      containers/*/build.conf|containers/*/README.md)
        select_app "$(dirname "$path")"
        ;;
      containers/*/*/*)
        dir=$(echo "$path" | cut -d/ -f1-3)
        select_version_dir "$dir"
        ;;
    esac
  done < <(changed_files)
  $ALL && select_all
fi

cp "$TEMPLATE" "$OUTPUT"

if [ ${#SELECTED[@]} -eq 0 ]; then
  cat >> "$OUTPUT" <<'YAML'

workflows:
  no-container-changes:
    jobs:
      - no-changes
YAML
  exit 0
fi

cat >> "$OUTPUT" <<'YAML'

workflows:
  build-containers:
    jobs:
YAML

load_config() {
  local file=$1 key value
  [ -f "$file" ] || return 0
  while IFS='=' read -r key value; do
    key=${key//$'\r'/}
    value=${value//$'\r'/}
    case "$key" in
      RESOURCE_CLASS) RESOURCE_CLASS=$value ;;
      MACHINE_IMAGE) MACHINE_IMAGE=$value ;;
      TAGS) TAGS=$value ;;
      NOTIFY) NOTIFY=$value ;;
      SCAN) SCAN=$value ;;
    esac
  done < <(grep -E '^(RESOURCE_CLASS|MACHINE_IMAGE|TAGS|NOTIFY|SCAN)=' "$file" || true)
}

for dir in $(printf '%s\n' "${!SELECTED[@]}" | sort); do
  app=$(echo "$dir" | cut -d/ -f2)
  version=$(echo "$dir" | cut -d/ -f3)
  RESOURCE_CLASS=medium
  MACHINE_IMAGE=ubuntu-2204:current
  TAGS=
  NOTIFY=false
  SCAN=false
  load_config "containers/$app/build.conf"
  load_config "$dir/build.conf"

  while IFS= read -r dockerfile_path; do
    dockerfile=$(basename "$dockerfile_path")
    variant=${dockerfile#Dockerfile}
    variant=${variant#.}
    suffix=${variant:+-$variant}
    variant_tags="${version}${suffix},latest${suffix}"
    if [ "$dockerfile" = Dockerfile ] && [ -n "$TAGS" ]; then
      variant_tags=$TAGS
    fi

    slug=$(printf '%s-%s%s' "$app" "$version" "$suffix" | tr '._' '--' | tr -cd '[:alnum:]-')
    cache_base="${app}-${version}"
    cache_amd64="${cache_base}-amd64${suffix}"
    cache_arm64="${cache_base}-arm64${suffix}"
    arm_resource="arm.${RESOURCE_CLASS#arm.}"
    update_readme=false
    [ "$dockerfile" = Dockerfile ] && update_readme=true

    cat >> "$OUTPUT" <<YAML
      - cache-build:
          name: ${slug}-cache-amd64
          app: "${app}"
          version: "${version}"
          dockerfile: "${dockerfile}"
          cache-tag: "${cache_amd64}"
          platform: linux/amd64
          resource-class: "${RESOURCE_CLASS#arm.}"
          machine-image: "${MACHINE_IMAGE}"
      - cache-build:
          name: ${slug}-cache-arm64
          app: "${app}"
          version: "${version}"
          dockerfile: "${dockerfile}"
          cache-tag: "${cache_arm64}"
          platform: linux/arm64/v8
          resource-class: "${arm_resource}"
          machine-image: "${MACHINE_IMAGE}"
      - publish:
          name: ${slug}-publish
          app: "${app}"
          version: "${version}"
          dockerfile: "${dockerfile}"
          cache-amd64: "${cache_amd64}"
          cache-arm64: "${cache_arm64}"
          image-tags: "${variant_tags}"
          machine-image: "${MACHINE_IMAGE}"
          scan: ${SCAN}
          update-readme: ${update_readme}
          requires:
            - ${slug}-cache-amd64
            - ${slug}-cache-arm64
YAML
    if [ "$NOTIFY" = true ]; then
      cat >> "$OUTPUT" <<YAML
      - notify:
          name: ${slug}-notify
          message: "${app} v${version}${suffix}"
          requires:
            - ${slug}-publish
YAML
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name 'Dockerfile*' | sort)
done
