#!/usr/bin/env bash
# Build Snapzy and copy the .app to a local directory.
#
# Usage:
#   ./scripts/build_and_copy.sh
#   ./scripts/build_and_copy.sh --configuration Debug
#   ./scripts/build_and_copy.sh --output ~/Applications
#   ./scripts/build_and_copy.sh --ad-hoc
#   ./scripts/build_and_copy.sh --unsigned
set -euo pipefail

APP_NAME="Snapzy"
DEBUG_BUNDLE_NAME="Snapzy Debug"
SCHEME="Snapzy"
PROJECT="Snapzy.xcodeproj"
DEFAULT_CERT_NAME="Snapzy Self-Signed"

CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
# self-signed | ad-hoc | unsigned | automatic
SIGNING_MODE="${SIGNING_MODE:-self-signed}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$DEFAULT_CERT_NAME}"
CLEAN=0
QUIET=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/xcode-derived-data}"
ENTITLEMENTS="$ROOT_DIR/Snapzy/Snapzy.entitlements"

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

Default signing uses a persistent self-signed certificate so Screen
Recording / Microphone permissions survive rebuilds. Create it once:

  ./scripts/create-signing-cert.sh

${BOLD}Options:${NC}
  --configuration C   Debug or Release. Default: Release
  --output PATH       Destination directory. Default: ./dist
  --derived-data PATH Build DerivedData path. Default: .build/xcode-derived-data
  --identity NAME     Self-signed identity. Default: $DEFAULT_CERT_NAME
  --ad-hoc            Sign with ad-hoc identity "-" (permissions reset each build)
  --unsigned          Skip code signing entirely
  --signed            Use the project's Automatic signing settings
  --clean             Clean before building
  --verbose           Show full xcodebuild output
  --help, -h          Show this help

${BOLD}Examples:${NC}
  $0
  $0 --configuration Debug --output ~/Applications
  $0 --ad-hoc --output ./dist
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
      --identity)
        [[ $# -ge 2 ]] || fail "--identity requires a certificate name."
        SIGNING_IDENTITY="$2"
        SIGNING_MODE="self-signed"
        shift 2
        ;;
      --ad-hoc|--adhoc)
        SIGNING_MODE="ad-hoc"
        SIGNING_IDENTITY="-"
        shift
        ;;
      --unsigned)
        SIGNING_MODE="unsigned"
        shift
        ;;
      --signed)
        SIGNING_MODE="automatic"
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

require_self_signed_identity() {
  if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    return
  fi

  fail "Signing identity '$SIGNING_IDENTITY' was not found.

Create it once, then rebuild:

  ./scripts/create-signing-cert.sh

After that, Screen Recording / Microphone grants persist across local rebuilds.
Ad-hoc signing (--ad-hoc) still resets those grants every build."
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

  if [[ "$SIGNING_MODE" != "automatic" ]]; then
    args+=(
      CODE_SIGN_IDENTITY="-"
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

sign_nested_item() {
  local identity="$1"
  local path="$2"
  shift 2
  if [[ -e "$path" ]]; then
    codesign --force --sign "$identity" --timestamp=none "$@" "$path"
  fi
}

sign_app() {
  local app_path="$1"
  local identity="$2"
  local sparkle="$app_path/Contents/Frameworks/Sparkle.framework"
  local processed entitlements_dir bundle_id

  info "Signing $app_path with identity '$identity'..."

  sign_nested_item "$identity" "$sparkle/Versions/B/XPCServices/Installer.xpc" -o runtime
  sign_nested_item "$identity" "$sparkle/Versions/B/XPCServices/Downloader.xpc" -o runtime --preserve-metadata=entitlements
  sign_nested_item "$identity" "$sparkle/Versions/B/Autoupdate" -o runtime
  sign_nested_item "$identity" "$sparkle/Versions/B/Updater.app" -o runtime
  sign_nested_item "$identity" "$sparkle" -o runtime

  bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")"
  entitlements_dir="$(mktemp -d)"
  processed="$entitlements_dir/processed-entitlements.plist"
  sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$bundle_id/g" "$ENTITLEMENTS" > "$processed"

  codesign \
    --force \
    --sign "$identity" \
    --entitlements "$processed" \
    --timestamp=none \
    "$app_path"

  rm -rf "$entitlements_dir"
  codesign --verify --deep --strict "$app_path"
  success "Signed $app_path"
}

build_app() {
  cd "$ROOT_DIR"

  case "$CONFIGURATION" in
    Debug|Release) ;;
    *) fail "Unsupported configuration: $CONFIGURATION. Use Debug or Release." ;;
  esac

  if [[ "$SIGNING_MODE" == "self-signed" ]]; then
    require_self_signed_identity
  fi

  if [[ "$CLEAN" -eq 1 ]]; then
    info "Cleaning $SCHEME ($CONFIGURATION)..."
    run_xcodebuild clean
  fi

  case "$SIGNING_MODE" in
    self-signed)
      info "Building $SCHEME ($CONFIGURATION, self-signed as '$SIGNING_IDENTITY')..."
      ;;
    ad-hoc)
      info "Building $SCHEME ($CONFIGURATION, ad-hoc signed)..."
      ;;
    unsigned)
      info "Building $SCHEME ($CONFIGURATION, unsigned)..."
      ;;
    automatic)
      info "Building $SCHEME ($CONFIGURATION, Automatic signing)..."
      ;;
    *)
      fail "Unsupported signing mode: $SIGNING_MODE"
      ;;
  esac

  run_xcodebuild build

  local app_bundle
  app_bundle="$(built_app_path)"
  [[ -d "$app_bundle" ]] || fail "Build finished but app bundle was not found: $app_bundle"

  case "$SIGNING_MODE" in
    self-signed|ad-hoc)
      sign_app "$app_bundle" "$SIGNING_IDENTITY"
      ;;
  esac

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
  require_command codesign

  build_app
  copy_app
}

main "$@"
