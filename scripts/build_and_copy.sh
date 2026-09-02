#!/usr/bin/env bash
# Build Snapzy and copy the .app to a local directory.
#
# Usage:
#   ./scripts/build_and_copy.sh
#   ./scripts/build_and_copy.sh --configuration Debug
#   ./scripts/build_and_copy.sh --output ~/Applications
#   ./scripts/build_and_copy.sh --signed
set -euo pipefail

APP_NAME="Snapzy"
DEBUG_BUNDLE_NAME="Snapzy Debug"
SCHEME="Snapzy"
PROJECT="Snapzy.xcodeproj"

CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
UNSIGNED=1
CLEAN=0
QUIET=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-derived-data}"

if [[ -t 1 ]]; then
  BLUE=$'\033[0;34m'
  GREEN=$'\033[0;32m'
  RED=$'\033[0;31m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
else
  BLUE=""
  GREEN=""
  RED=""
  BOLD=""
  NC=""
fi

info() { printf "%sinfo:%s %s\n" "$BLUE$BOLD" "$NC" "$1"; }
success() { printf "%ssuccess:%s %s\n" "$GREEN$BOLD" "$NC" "$1"; }
fail() {
  printf "%serror:%s %s\n" "$RED$BOLD" "$NC" "$1" >&2
  exit 1
}

usage() {
  cat <<USAGE
${BOLD}Usage:${NC} $0 [options]

Build Snapzy and copy the app bundle to a local directory.

${BOLD}Options:${NC}
  --configuration C   Debug or Release. Default: Release
  --output PATH       Destination directory. Default: ./dist
  --derived-data PATH Build DerivedData path. Default: .build/xcode-derived-data
  --unsigned          Skip code signing (default)
  --signed            Use the project's normal signing settings
  --clean             Clean before building
  --verbose           Show full xcodebuild output
  --help, -h          Show this help

${BOLD}Examples:${NC}
  $0
  $0 --configuration Debug --output ~/Applications
  $0 --signed --output ./dist
USAGE
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This script only supports macOS."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --configuration)
        [[ $# -ge 2 ]] || fail "--configuration requires a value."
        CONFIGURATION="$2"
        shift 2
        ;;
      --output)
        [[ $# -ge 2 ]] || fail "--output requires a path."
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --derived-data|--derived-data-path)
        [[ $# -ge 2 ]] || fail "--derived-data requires a path."
        DERIVED_DATA_PATH="$2"
        shift 2
        ;;
      --unsigned)
        UNSIGNED=1
        shift
        ;;
      --signed)
        UNSIGNED=0
        shift
        ;;
      --clean)
        CLEAN=1
        shift
        ;;
      --verbose)
        QUIET=0
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

bundle_name() {
  if [[ "$CONFIGURATION" == "Debug" ]]; then
    printf "%s" "$DEBUG_BUNDLE_NAME"
  else
    printf "%s" "$APP_NAME"
  fi
}

built_app_path() {
  printf "%s/Build/Products/%s/%s.app" "$DERIVED_DATA_PATH" "$CONFIGURATION" "$(bundle_name)"
}

run_xcodebuild() {
  local action="$1"
  local args=(
    xcodebuild
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED_DATA_PATH"
  )

  if [[ "$UNSIGNED" -eq 1 ]]; then
    args+=(
      CODE_SIGN_IDENTITY=""
      CODE_SIGNING_REQUIRED=NO
      CODE_SIGNING_ALLOWED=NO
    )
  fi

  if [[ "$QUIET" -eq 1 ]]; then
    args+=(-quiet)
  fi

  args+=("$action")
  "${args[@]}"
}

build_app() {
  cd "$ROOT_DIR"

  case "$CONFIGURATION" in
    Debug|Release) ;;
    *) fail "Unsupported configuration: $CONFIGURATION. Use Debug or Release." ;;
  esac

  if [[ "$CLEAN" -eq 1 ]]; then
    info "Cleaning $SCHEME ($CONFIGURATION)..."
    run_xcodebuild clean
  fi

  if [[ "$UNSIGNED" -eq 1 ]]; then
    info "Building $SCHEME ($CONFIGURATION, unsigned)..."
  else
    info "Building $SCHEME ($CONFIGURATION)..."
  fi
  run_xcodebuild build

  local app_bundle
  app_bundle="$(built_app_path)"
  [[ -d "$app_bundle" ]] || fail "Build finished but app bundle was not found: $app_bundle"
  success "Build ready: $app_bundle"
}

copy_app() {
  local source_app dest_dir dest_app
  source_app="$(built_app_path)"

  if [[ -z "$OUTPUT_DIR" ]]; then
    dest_dir="$ROOT_DIR/dist"
  else
    dest_dir="$OUTPUT_DIR"
    [[ "$dest_dir" == /* ]] || dest_dir="$ROOT_DIR/$dest_dir"
  fi

  mkdir -p "$dest_dir"
  dest_app="$dest_dir/$(bundle_name).app"

  info "Copying to $dest_app..."
  rm -rf "$dest_app"
  /usr/bin/ditto "$source_app" "$dest_app"
  [[ -d "$dest_app" ]] || fail "Copy finished but destination app was not found: $dest_app"
  success "Copied $APP_NAME to $dest_app"
}

main() {
  parse_args "$@"
  require_macos
  require_command xcodebuild
  require_command ditto

  build_app
  copy_app
}

main "$@"
