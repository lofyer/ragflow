#!/usr/bin/env bash
#
# image.sh - Export / import the Docker images referenced by docker-compose.yml
#
# Usage:
#   ./image.sh export [-f compose-file] [-d images-dir] [-p profile ...]
#   ./image.sh import [-d images-dir]
#   ./image.sh list   [-f compose-file] [-p profile ...]
#
# export : pull (if needed) and save every image used by the compose file into
#          tar archives under the images directory (default: ./images).
# import : load every *.tar archive found in the images directory.
# list   : print the resolved image list without saving anything.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
IMAGES_DIR="${SCRIPT_DIR}/images"
PROFILES=()

log()  { printf '\033[1;32m[image]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[image]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[image]\033[0m %s\n' "$*" >&2; }

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    err "Neither 'docker compose' nor 'docker-compose' is available."
    exit 1
  fi
}

resolve_images() {
  local pargs=()
  local p
  for p in ${PROFILES[@]+"${PROFILES[@]}"}; do
    [ -n "$p" ] && pargs+=(--profile "$p")
  done
  "${COMPOSE_CMD[@]}" ${pargs[@]+"${pargs[@]}"} -f "$COMPOSE_FILE" config --images 2>/dev/null \
    | grep -v '^$' | sort -u
}

# Turn an image reference into a safe tar filename.
image_to_filename() {
  echo "$1" | sed 's#[/:]#_#g'
}

cmd_list() {
  detect_compose
  local images
  images="$(resolve_images)"
  if [ -z "$images" ]; then
    warn "No images resolved from $COMPOSE_FILE"
    return 0
  fi
  echo "$images"
}

cmd_export() {
  detect_compose
  mkdir -p "$IMAGES_DIR"

  local images
  images="$(resolve_images)"
  if [ -z "$images" ]; then
    err "No images resolved from $COMPOSE_FILE"
    exit 1
  fi

  log "Images to export:"
  echo "$images" | sed 's/^/  - /'

  while IFS= read -r image; do
    [ -z "$image" ] && continue
    if ! docker image inspect "$image" >/dev/null 2>&1; then
      log "Pulling missing image: $image"
      if ! docker pull "$image"; then
        warn "Failed to pull $image, skipping."
        continue
      fi
    fi
    local out="${IMAGES_DIR}/$(image_to_filename "$image").tar"
    log "Saving $image -> $out"
    docker save -o "$out" "$image"
  done <<< "$images"

  log "Export complete. Archives are in: $IMAGES_DIR"
}

cmd_import() {
  if [ ! -d "$IMAGES_DIR" ]; then
    err "Images directory not found: $IMAGES_DIR"
    exit 1
  fi

  shopt -s nullglob
  local tars=("$IMAGES_DIR"/*.tar)
  shopt -u nullglob

  if [ ${#tars[@]} -eq 0 ]; then
    err "No .tar archives found in $IMAGES_DIR"
    exit 1
  fi

  local tar
  for tar in "${tars[@]}"; do
    log "Loading $tar"
    docker load -i "$tar"
  done

  log "Import complete."
}

main() {
  [ $# -lt 1 ] && usage 1
  local action="$1"; shift

  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--file)    COMPOSE_FILE="$2"; shift 2 ;;
      -d|--dir)     IMAGES_DIR="$2"; shift 2 ;;
      -p|--profile) PROFILES+=("$2"); shift 2 ;;
      -h|--help)    usage 0 ;;
      *) err "Unknown option: $1"; usage 1 ;;
    esac
  done

  case "$action" in
    export) cmd_export ;;
    import) cmd_import ;;
    list)   cmd_list ;;
    -h|--help|help) usage 0 ;;
    *) err "Unknown action: $action"; usage 1 ;;
  esac
}

main "$@"
