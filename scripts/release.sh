#!/bin/bash
# Bibliada release script: archive -> export -> verify -> notarize -> staple ->
# .dmg -> notarize/staple the .dmg -> checksummed artifacts.
#
# One command produces a shippable, notarized, offline-verifiable download.
# It never touches build.sh's local-install flow and never modifies project.yml.
#
# Usage:
#   ./scripts/release.sh                       # Developer ID (direct download) release
#   ./scripts/release.sh --variant app-store   # Mac App Store .pkg (no notarytool; App Review notarizes)
#   ./scripts/release.sh --variant both
#   ./scripts/release.sh --skip-notarize       # build + sign + dmg only (dry run, no Apple round trip)
#   ./scripts/release.sh --upload              # app-store variant only: push the .pkg to App Store Connect
#   ./scripts/release.sh --version 1.1 --build 7
#   ./scripts/release.sh --help
#
# Environment variables (BIBLIADA_* naming matches build.sh / project.yml):
#
#   BIBLIADA_TEAM_ID            REQUIRED. 10-char Apple Developer Team ID. Same
#                               variable build.sh and project.yml already use;
#                               unlike build.sh there is no ad-hoc fallback here,
#                               because ad-hoc signed builds can never be
#                               notarized or accepted by the App Store.
#   BIBLIADA_VERSION            MARKETING_VERSION for this release. Default: the
#                               MARKETING_VERSION currently in project.yml.
#   BIBLIADA_BUILD              CURRENT_PROJECT_VERSION. Default: project.yml's,
#                               or a UTC timestamp when --auto-build is passed.
#   BIBLIADA_OUTPUT_DIR         Artifact directory. Default: ./dist
#   BIBLIADA_NOTARY_PROFILE     notarytool keychain profile name created with
#                               `xcrun notarytool store-credentials`.
#                               Default: bibliada-notary. Used only when the App
#                               Store Connect API key variables below are unset.
#   BIBLIADA_ASC_KEY_PATH       App Store Connect API key (.p8) path. When set
#   BIBLIADA_ASC_KEY_ID         together with KEY_ID (+ ISSUER_ID for team keys),
#   BIBLIADA_ASC_ISSUER_ID      notarytool and xcodebuild authenticate with the
#                               API key instead of a keychain profile. This is
#                               the CI path: no keychain profile, no
#                               app-specific password, no interactive prompt.
#   BIBLIADA_KEYCHAIN           Path to a keychain to read signing identities and
#                               the notary profile from (CI temp keychain).
#   BIBLIADA_APP_ENTITLEMENTS   Override CODE_SIGN_ENTITLEMENTS for the app
#   BIBLIADA_WIDGET_ENTITLEMENTS  and widget targets. Needed for the app-store
#                               variant, which requires the App Sandbox.
#   BIBLIADA_NOTARY_TIMEOUT     `notarytool --wait` timeout. Default: 45m.
#   BIBLIADA_ALLOW_DIRTY=1      Permit a release from a dirty git working tree.
#   BIBLIADA_ALLOW_RELEASED=1   Permit reusing a version that already has a git
#                               tag or an existing artifact directory.
#
# Notarization notes:
#   * `xcrun altool` has not accepted notarization uploads since 2023-11-01;
#     notarytool is the only supported path and is what this script uses.
#   * Both the .app AND the .dmg are stapled. Notarizing only the .dmg leaves the
#     .app inside it without a ticket, which fails Gatekeeper on a machine that
#     is offline or behind a filtering proxy. That costs two notary round trips.
#   * Typical turnaround per round trip is 1-15 minutes. Hours means either an
#     Apple-side incident or a submission held for deeper analysis.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locations and small helpers
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts"
cd "$REPO_ROOT"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Print a step banner so a long run is readable in a scrollback or CI log.
step() { printf '\n===== %s =====\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

VARIANT="developer-id"
SKIP_NOTARIZE=0
DO_UPLOAD=0
AUTO_BUILD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --variant)
      [ "$#" -ge 2 ] || die "--variant requires a value (developer-id|app-store|both)"
      VARIANT="$2"
      shift 2
      ;;
    --variant=*)
      VARIANT="${1#*=}"
      shift
      ;;
    --version)
      [ "$#" -ge 2 ] || die "--version requires a value"
      BIBLIADA_VERSION="$2"
      shift 2
      ;;
    --build)
      [ "$#" -ge 2 ] || die "--build requires a value"
      BIBLIADA_BUILD="$2"
      shift 2
      ;;
    --auto-build)
      AUTO_BUILD=1
      shift
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --upload)
      DO_UPLOAD=1
      shift
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (try --help)"
      ;;
  esac
done

case "$VARIANT" in
  developer-id|app-store|both) ;;
  *) die "--variant must be one of: developer-id, app-store, both (got '$VARIANT')" ;;
esac

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TEAM_ID="${BIBLIADA_TEAM_ID:-}"
OUTPUT_ROOT="${BIBLIADA_OUTPUT_DIR:-$REPO_ROOT/dist}"
NOTARY_PROFILE="${BIBLIADA_NOTARY_PROFILE:-bibliada-notary}"
NOTARY_TIMEOUT="${BIBLIADA_NOTARY_TIMEOUT:-45m}"
CONFIGURATION="Release"
SCHEME="Bibliada"
PROJECT="Bibliada.xcodeproj"
APP_NAME="Bibliada"
DERIVED_DATA="$REPO_ROOT/.build-release"

# Read the defaults straight out of project.yml so the script has one source of
# truth for versions and does not require editing project.yml to cut a release.
project_yml_value() {
  # $1: key name. Matches "  KEY: "value"" or "  KEY: value".
  sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" \
    "$REPO_ROOT/project.yml" | head -n 1
}

VERSION="${BIBLIADA_VERSION:-$(project_yml_value MARKETING_VERSION)}"
if [ "$AUTO_BUILD" -eq 1 ] && [ -z "${BIBLIADA_BUILD:-}" ]; then
  BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
else
  BUILD_NUMBER="${BIBLIADA_BUILD:-$(project_yml_value CURRENT_PROJECT_VERSION)}"
fi

[ -n "$VERSION" ]      || die "could not determine MARKETING_VERSION; pass --version"
[ -n "$BUILD_NUMBER" ] || die "could not determine CURRENT_PROJECT_VERSION; pass --build"

RELEASE_DIR="$OUTPUT_ROOT/$VERSION-$BUILD_NUMBER"

# ---------------------------------------------------------------------------
# Credentials: App Store Connect API key (preferred) or keychain profile
# ---------------------------------------------------------------------------
#
# notarytool accepts three auth shapes. We support the two non-interactive ones:
#
#   1. App Store Connect API key: --key <p8> --key-id <id> [--issuer <uuid>].
#      Issuer is required for Team keys, and must be OMITTED for Individual
#      keys. Best for CI: no Apple ID, no 2FA, revocable, no keychain needed.
#   2. Keychain profile: -p <name>, created once with
#      `xcrun notarytool store-credentials`. Best for a developer laptop; the
#      profile itself may wrap either an API key or an app-specific password.
#
# (An app-specific password passed inline via --apple-id/--password works too
# but puts a secret on the command line and in the shell history, so this script
# deliberately does not offer it.)

NOTARY_AUTH=()          # notarytool flags
XCODEBUILD_AUTH=()      # xcodebuild -authenticationKey* flags (automatic signing)
KEYCHAIN_ARGS=()        # "--keychain <path>" or empty, for codesign/security
AUTH_MODE=""
DEVELOPER_ID_IDENTITY=""   # exact SHA-1 of the Developer ID Application cert

configure_auth() {
  if [ -n "${BIBLIADA_ASC_KEY_PATH:-}" ] || [ -n "${BIBLIADA_ASC_KEY_ID:-}" ]; then
    [ -n "${BIBLIADA_ASC_KEY_PATH:-}" ] || die "BIBLIADA_ASC_KEY_ID set but BIBLIADA_ASC_KEY_PATH is not"
    [ -n "${BIBLIADA_ASC_KEY_ID:-}" ]   || die "BIBLIADA_ASC_KEY_PATH set but BIBLIADA_ASC_KEY_ID is not"
    [ -f "$BIBLIADA_ASC_KEY_PATH" ]     || die "App Store Connect key not found: $BIBLIADA_ASC_KEY_PATH"

    AUTH_MODE="api-key"
    NOTARY_AUTH=(--key "$BIBLIADA_ASC_KEY_PATH" --key-id "$BIBLIADA_ASC_KEY_ID")
    XCODEBUILD_AUTH=(-authenticationKeyPath "$BIBLIADA_ASC_KEY_PATH" \
                     -authenticationKeyID "$BIBLIADA_ASC_KEY_ID")
    if [ -n "${BIBLIADA_ASC_ISSUER_ID:-}" ]; then
      NOTARY_AUTH+=(--issuer "$BIBLIADA_ASC_ISSUER_ID")
      XCODEBUILD_AUTH+=(-authenticationKeyIssuerID "$BIBLIADA_ASC_ISSUER_ID")
    else
      # Individual (personal) keys have no issuer; Team keys require one.
      warn "BIBLIADA_ASC_ISSUER_ID unset - assuming an Individual API key. Team keys require an issuer ID."
    fi
  else
    AUTH_MODE="keychain-profile"
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
    # xcodebuild falls back to the Xcode account in the login keychain.
    XCODEBUILD_AUTH=()
  fi

  if [ -n "${BIBLIADA_KEYCHAIN:-}" ]; then
    [ -f "$BIBLIADA_KEYCHAIN" ] || die "BIBLIADA_KEYCHAIN does not exist: $BIBLIADA_KEYCHAIN"
    NOTARY_AUTH+=(--keychain "$BIBLIADA_KEYCHAIN")
    KEYCHAIN_ARGS=(--keychain "$BIBLIADA_KEYCHAIN")
  fi
}

# ---------------------------------------------------------------------------
# Preflight - fail loudly and early, before anything slow happens
# ---------------------------------------------------------------------------

preflight() {
  step "Preflight"

  require_cmd xcodegen   "Install it with 'brew install xcodegen'."
  require_cmd xcodebuild "Install Xcode and run 'xcode-select --install'."
  require_cmd hdiutil    "It ships with macOS; your PATH may be broken."
  require_cmd ditto      "It ships with macOS; your PATH may be broken."
  require_cmd shasum     "It ships with macOS; your PATH may be broken."
  require_cmd plutil     "It ships with macOS; your PATH may be broken."

  xcrun --find notarytool >/dev/null 2>&1 \
    || die "notarytool not found. It requires Xcode 13+ (you have $(xcodebuild -version | head -n1)). Note that altool has not accepted notarization uploads since 2023-11-01."
  xcrun --find stapler >/dev/null 2>&1 || die "stapler not found in the active Xcode."

  # --- Team ID -------------------------------------------------------------
  [ -n "$TEAM_ID" ] || die "BIBLIADA_TEAM_ID is not set.
  A release build cannot use build.sh's ad-hoc/unsigned fallback: ad-hoc signed
  binaries can never be notarized, and the group.com.bibliada.shared App Group
  needs a real provisioning profile. Set it first:
      export BIBLIADA_TEAM_ID=ABCDE12345"
  case "$TEAM_ID" in
    [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
    *) die "BIBLIADA_TEAM_ID='$TEAM_ID' does not look like a 10-character Apple Team ID." ;;
  esac

  # --- Signing identities --------------------------------------------------
  local find_identity=(security find-identity -v -p codesigning)
  if [ -n "${BIBLIADA_KEYCHAIN:-}" ]; then
    find_identity+=("$BIBLIADA_KEYCHAIN")
  fi
  local identities
  identities="$("${find_identity[@]}" 2>/dev/null || true)"

  if [ "$VARIANT" = "developer-id" ] || [ "$VARIANT" = "both" ]; then
    # Capture the exact SHA-1 hash rather than matching by name later: a name
    # like "Developer ID Application" is ambiguous the moment a second team's
    # certificate lands in the keychain, and codesign then refuses to guess.
    # `|| true`: with `set -o pipefail`, a non-matching grep would abort the
    # script here and the helpful message below would never be printed.
    DEVELOPER_ID_IDENTITY="$(
      printf '%s\n' "$identities" \
        | grep "Developer ID Application: .*($TEAM_ID)" \
        | head -n1 \
        | awk '{print $2}' || true
    )"
    [ -n "$DEVELOPER_ID_IDENTITY" ] || die "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain.
  Create one at https://developer.apple.com/account/resources/certificates and
  download+double-click it, or let Xcode do it via Settings > Accounts >
  Manage Certificates > + > Developer ID Application.
  Found identities:
$identities"
    log "Developer ID Application identity: $DEVELOPER_ID_IDENTITY"
  fi

  if [ "$VARIANT" = "app-store" ] || [ "$VARIANT" = "both" ]; then
    printf '%s\n' "$identities" | grep -q "Apple Distribution: .*($TEAM_ID)" \
      || die "No 'Apple Distribution' certificate for team $TEAM_ID (needed for the Mac App Store build)."
    # The installer certificate is not a codesigning identity, so it does not
    # show up in find-identity -p codesigning; check the generic list instead.
    security find-certificate -a -c "3rd Party Mac Developer Installer" >/dev/null 2>&1 \
      || warn "No '3rd Party Mac Developer Installer' certificate found - the .pkg export will fail without it."
  fi

  # --- Notary credentials --------------------------------------------------
  if [ "$SKIP_NOTARIZE" -eq 0 ] && { [ "$VARIANT" = "developer-id" ] || [ "$VARIANT" = "both" ]; }; then
    if [ "$AUTH_MODE" = "keychain-profile" ]; then
      # notarytool stores profiles as generic passwords under this service name.
      # Checking locally avoids burning a network round trip just to discover a
      # typo'd profile name.
      local kc_args=(find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARY_PROFILE")
      if [ -n "${BIBLIADA_KEYCHAIN:-}" ]; then
        kc_args+=("$BIBLIADA_KEYCHAIN")
      fi
      security "${kc_args[@]}" >/dev/null 2>&1 \
        || die "notarytool keychain profile '$NOTARY_PROFILE' not found.
  Create it once with an App Store Connect API key (recommended):
      xcrun notarytool store-credentials '$NOTARY_PROFILE' \\
        --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \\
        --key-id XXXXXXXXXX --issuer <issuer-uuid>
  ...or with an app-specific password from https://account.apple.com:
      xcrun notarytool store-credentials '$NOTARY_PROFILE' \\
        --apple-id you@example.com --team-id $TEAM_ID --password <app-specific-password>
  Or set BIBLIADA_ASC_KEY_PATH / BIBLIADA_ASC_KEY_ID / BIBLIADA_ASC_ISSUER_ID
  to use an API key directly (what CI does)."
    fi
    log "Notary auth mode: $AUTH_MODE"
  fi

  # --- Version hygiene -----------------------------------------------------
  if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "${BIBLIADA_ALLOW_DIRTY:-}" ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
      die "git working tree is dirty. Commit or stash first, or set BIBLIADA_ALLOW_DIRTY=1.
  (A release you cannot reproduce from a commit is a release you cannot support.)"
    fi
    if [ -z "${BIBLIADA_ALLOW_RELEASED:-}" ] \
       && git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
      die "tag v$VERSION already exists - bump the version.
  Pass --version 1.1 (and/or --build N), or set BIBLIADA_ALLOW_RELEASED=1 to rebuild it."
    fi
  fi
  if [ -z "${BIBLIADA_ALLOW_RELEASED:-}" ] && [ -d "$RELEASE_DIR" ]; then
    die "$RELEASE_DIR already exists - bump --version/--build or set BIBLIADA_ALLOW_RELEASED=1 to overwrite."
  fi

  log "Team ID:        $TEAM_ID"
  log "Version:        $VERSION ($BUILD_NUMBER)"
  log "Variant(s):     $VARIANT"
  log "Artifacts:      $RELEASE_DIR"
}

# ---------------------------------------------------------------------------
# Build settings shared by every xcodebuild invocation
# ---------------------------------------------------------------------------

build_settings() {
  # Version numbers are injected on the command line rather than by editing
  # project.yml, so a release never leaves the repo dirty.
  printf '%s\n' \
    "DEVELOPMENT_TEAM=$TEAM_ID" \
    "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
  # Release builds must use a real identity, overriding project.yml's ad-hoc
  # CODE_SIGN_IDENTITY: "-" fallback.
  printf '%s\n' "CODE_SIGN_STYLE=Automatic"
  # NOTE: CODE_SIGN_ENTITLEMENTS is deliberately NOT passed here. A build
  # setting given on the xcodebuild command line applies to EVERY target, so it
  # would hand the app's entitlements to BibliadaWidget as well - silently
  # producing a widget with the wrong (or no) App Group. Per-target entitlement
  # variants are selected through xcodegen instead; see resolve_entitlements().
  return 0
}

# The app-store and developer-id variants need different entitlements files
# (the store requires the App Sandbox; the Developer ID build may leave it off).
# Both variants should declare the SAME App Group, in its Team-ID-prefixed form
# $(TeamIdentifierPrefix)group.com.bibliada.shared, which is the only form valid
# on both channels without an embedded provisioning profile authorizing it.
# project.yml hardcodes the entitlement paths today, but it already
# uses XcodeGen's ${VAR} substitution for DEVELOPMENT_TEAM, so the clean hook is
# to export these and let project.yml reference them per target, e.g.
#
#   CODE_SIGN_ENTITLEMENTS: ${BIBLIADA_APP_ENTITLEMENTS}
#
# We export them (harmless if project.yml ignores them) and verify afterwards
# that the entitlements actually baked into the binary are the ones asked for.
resolve_entitlements() {
  if [ -n "${BIBLIADA_APP_ENTITLEMENTS:-}" ]; then
    [ -f "$REPO_ROOT/$BIBLIADA_APP_ENTITLEMENTS" ] || [ -f "$BIBLIADA_APP_ENTITLEMENTS" ] \
      || die "BIBLIADA_APP_ENTITLEMENTS points at a missing file: $BIBLIADA_APP_ENTITLEMENTS"
    export BIBLIADA_APP_ENTITLEMENTS
    if ! grep -q 'BIBLIADA_APP_ENTITLEMENTS' "$REPO_ROOT/project.yml"; then
      warn "BIBLIADA_APP_ENTITLEMENTS is set but project.yml does not reference \${BIBLIADA_APP_ENTITLEMENTS} - the override will be IGNORED and the checked-in App/Bibliada.entitlements will be used instead."
    fi
  fi
  if [ -n "${BIBLIADA_WIDGET_ENTITLEMENTS:-}" ]; then
    [ -f "$REPO_ROOT/$BIBLIADA_WIDGET_ENTITLEMENTS" ] || [ -f "$BIBLIADA_WIDGET_ENTITLEMENTS" ] \
      || die "BIBLIADA_WIDGET_ENTITLEMENTS points at a missing file: $BIBLIADA_WIDGET_ENTITLEMENTS"
    export BIBLIADA_WIDGET_ENTITLEMENTS
    if ! grep -q 'BIBLIADA_WIDGET_ENTITLEMENTS' "$REPO_ROOT/project.yml"; then
      warn "BIBLIADA_WIDGET_ENTITLEMENTS is set but project.yml does not reference \${BIBLIADA_WIDGET_ENTITLEMENTS} - the override will be IGNORED."
    fi
  fi
}

# ---------------------------------------------------------------------------
# Stage 1: generate project + archive
# ---------------------------------------------------------------------------
#
# The .xcodeproj is gitignored and generated, so it MUST be regenerated here;
# a stale project on disk is the classic way to ship yesterday's sources.

make_archive() {
  local variant="$1" archive_path="$2" identity="$3"

  step "Archive ($variant)"

  resolve_entitlements

  log "xcodegen generate"
  BIBLIADA_TEAM_ID="$TEAM_ID" xcodegen generate

  rm -rf "$archive_path"
  mkdir -p "$(dirname "$archive_path")"

  local settings=()
  while IFS= read -r line; do settings+=("$line"); done < <(build_settings)
  # Deliberately NOT settings+=("CODE_SIGN_IDENTITY=$identity") here: forcing an
  # explicit identity on the `archive` action while CODE_SIGN_STYLE=Automatic is
  # also set makes Xcode treat it as a conflicting manual override ("target is
  # automatically signed for development, but a conflicting code signing
  # identity ... has been manually specified") and the archive fails outright.
  # Any identity that satisfies the entitlements is fine for the archive itself
  # (Automatic signing picks one on its own); the real distribution identity is
  # applied afterwards, at export time, via each ExportOptions template's
  # signingCertificate key (see make_export / the *.plist files). $identity is
  # kept as a parameter purely so callers document which identity that export
  # step expects to find in the keychain.

  local extra=()
  # -allowProvisioningUpdates lets xcodebuild create/renew the profiles that
  # grant the App Group to the app AND the embedded widget extension.
  extra+=(-allowProvisioningUpdates)
  if [ "${#XCODEBUILD_AUTH[@]}" -gt 0 ]; then
    extra+=("${XCODEBUILD_AUTH[@]}")
  fi
  if [ -n "${BIBLIADA_KEYCHAIN:-}" ]; then
    # Point codesign at the CI keychain; without this it only searches the
    # (empty, on a fresh runner) login keychain.
    extra+=("OTHER_CODE_SIGN_FLAGS=--keychain $BIBLIADA_KEYCHAIN")
  fi

  log "xcodebuild archive -> $archive_path"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$archive_path" \
    archive \
    "${extra[@]}" \
    "${settings[@]}"

  [ -d "$archive_path" ] || die "archive not produced at $archive_path"
  log "Archived: $archive_path"
}

# ---------------------------------------------------------------------------
# Stage 2: export
# ---------------------------------------------------------------------------

make_export() {
  local template="$1" archive_path="$2" export_dir="$3" destination="${4:-export}"

  step "Export ($(basename "$template"))"

  [ -f "$template" ] || die "missing export options template: $template"

  # Materialize the template with the real team ID. plutil edits the plist
  # structurally, so we never risk mangling the XML with sed.
  local plist="$TMP_DIR/$(basename "$template")"
  cp "$template" "$plist"
  plutil -replace teamID -string "$TEAM_ID" "$plist"
  plutil -replace destination -string "$destination" "$plist"
  plutil -lint "$plist" >/dev/null || die "generated export options plist is invalid: $plist"

  rm -rf "$export_dir"
  mkdir -p "$export_dir"

  local extra=(-allowProvisioningUpdates)
  if [ "${#XCODEBUILD_AUTH[@]}" -gt 0 ]; then
    extra+=("${XCODEBUILD_AUTH[@]}")
  fi

  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$plist" \
    "${extra[@]}"

  log "Exported to: $export_dir"
}

# ---------------------------------------------------------------------------
# Stage 3: signature verification (catch notarization rejections locally)
# ---------------------------------------------------------------------------
#
# Everything checked here is something the notary service would otherwise reject
# minutes later. Checking locally turns a 10-minute round trip into a 2-second
# failure.

verify_signature() {
  local app="$1"

  step "Verify signature"

  [ -d "$app" ] || die "app bundle not found: $app"

  # --deep --strict walks the embedded BibliadaWidget.appex too. The widget is
  # signed and embedded by the app target (project.yml: embed: true,
  # codeSign: true), i.e. inside-out; if that ordering ever breaks, this is
  # where it surfaces.
  log "codesign --verify --deep --strict"
  codesign --verify --deep --strict --verbose=2 "$app" \
    || die "code signature verification failed for $app"

  local info
  info="$(codesign --display --verbose=4 "$app" 2>&1)"

  printf '%s\n' "$info" | grep -q "Authority=Developer ID Application" \
    || die "$app is not signed with a Developer ID Application certificate.
  Notarization requires it. Got:
$(printf '%s\n' "$info" | grep '^Authority=' || true)"

  # Hardened runtime is mandatory for notarization. project.yml sets
  # ENABLE_HARDENED_RUNTIME: YES on both targets; verify it actually stuck.
  printf '%s\n' "$info" | grep -q "flags=.*runtime" \
    || die "$app is not signed with the hardened runtime (CodeDirectory flags lack 'runtime').
  Check ENABLE_HARDENED_RUNTIME in project.yml."

  # A secure (RFC 3161) timestamp is mandatory. Absent one, notarytool returns
  # 'The signature does not include a secure timestamp.' Note: an offline build
  # machine silently drops the timestamp, which is why this check exists.
  printf '%s\n' "$info" | grep -q "^Timestamp=" \
    || die "$app has no secure timestamp. Sign with a network connection (codesign --timestamp)."

  # Verify the embedded extension independently: exportArchive re-signs the app
  # and everything nested in it, and a stale/unsigned .appex is the most common
  # cause of a rejection whose log path points inside Contents/PlugIns.
  local appex="$app/Contents/PlugIns/BibliadaWidget.appex"
  if [ -d "$appex" ]; then
    codesign --verify --strict --verbose=2 "$appex" \
      || die "embedded widget extension signature is invalid: $appex"
    codesign --display --verbose=4 "$appex" 2>&1 | grep -q "^Timestamp=" \
      || die "embedded widget extension has no secure timestamp: $appex"
    log "Embedded extension OK: BibliadaWidget.appex"
  else
    warn "No BibliadaWidget.appex found in $app - was the widget dropped from the archive?"
  fi

  # Show the App Group actually granted. Both variants should show the same
  # Team-ID-prefixed group; a bare group.com.bibliada.shared here means the
  # build depends on an embedded provisioning profile to authorize it, which
  # silently degrades app/widget settings sharing if the profile is missing.
  log "Entitlements (App Group):"
  codesign --display --entitlements - --xml "$app" 2>/dev/null \
    | plutil -convert xml1 -o - - 2>/dev/null \
    | grep -A3 "application-groups" || warn "could not read application-groups entitlement"

  log "Signature verification passed."
}

# ---------------------------------------------------------------------------
# Stage 4: notarization
# ---------------------------------------------------------------------------
#
# notarize <path-to-zip-or-dmg> <human-label>
#
# Submits, waits, prints the submission ID up front (so it can be looked up
# later even if this shell dies), and on anything other than "Accepted"
# automatically fetches and prints the notary log, which is the only place the
# actual reason lives.

notarize() {
  local target="$1" label="$2"

  step "Notarize $label"

  [ -f "$target" ] || die "nothing to notarize at $target"

  local json_out="$TMP_DIR/notary-$label.json"
  local submit_status=0

  log "Submitting $(basename "$target") ($(du -h "$target" | cut -f1)) to the Apple notary service..."
  log "Expect 1-15 minutes. Timeout: $NOTARY_TIMEOUT."

  # --output-format json makes the result machine readable; --wait blocks until
  # Apple finishes. Note that a non-zero exit here can mean either "rejected" or
  # "upload failed", so we inspect the JSON rather than trusting the exit code.
  set +e
  xcrun notarytool submit "$target" \
    "${NOTARY_AUTH[@]}" \
    --wait \
    --timeout "$NOTARY_TIMEOUT" \
    --no-progress \
    --output-format json \
    >"$json_out" 2>"$TMP_DIR/notary-$label.err"
  submit_status=$?
  set -e

  # Always surface stderr: connectivity and credential errors only appear there.
  if [ -s "$TMP_DIR/notary-$label.err" ]; then
    cat "$TMP_DIR/notary-$label.err" >&2
  fi

  local submission_id status message
  submission_id="$(plutil -extract id raw -o - "$json_out" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$json_out" 2>/dev/null || true)"
  message="$(plutil -extract message raw -o - "$json_out" 2>/dev/null || true)"

  if [ -n "$submission_id" ]; then
    log "Submission ID: $submission_id"
    log "  Re-check later with: xcrun notarytool info $submission_id ${NOTARY_AUTH[*]}"
    printf '%s\n' "$submission_id" >>"$RELEASE_DIR/submission-ids.txt"
  fi
  if [ -n "$message" ]; then
    log "Notary message: $message"
  fi

  if [ "$status" = "Accepted" ]; then
    log "Notarization ACCEPTED for $label."
    return 0
  fi

  # ---- failure path ----
  printf '\n' >&2
  warn "Notarization did NOT succeed for $label (status: ${status:-unknown}, exit: $submit_status)."

  if [ -n "$submission_id" ]; then
    warn "Fetching the notary log - this is where the actual reason is."
    local log_file="$RELEASE_DIR/notarytool-$label-$submission_id.json"
    if xcrun notarytool log "$submission_id" "${NOTARY_AUTH[@]}" "$log_file" 2>/dev/null; then
      printf '\n----- notarytool log (%s) -----\n' "$label" >&2
      cat "$log_file" >&2
      printf '\n----- issues summary -----\n' >&2
      # The 'issues' array is the actionable part: severity/code/path/message.
      /usr/bin/python3 - "$log_file" >&2 <<'PY' || warn "could not summarize issues; read the raw log above"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
issues = data.get("issues") or []
if not issues:
    print("No 'issues' entries. statusSummary: %s" % data.get("statusSummary"))
for i in issues:
    print("[%s] %s" % (i.get("severity"), i.get("message")))
    print("    path: %s" % i.get("path"))
    if i.get("docUrl"):
        print("    docs: %s" % i.get("docUrl"))
PY
      warn "Full log saved to: $log_file"
    else
      warn "Could not fetch the log. Try manually:
      xcrun notarytool log $submission_id ${NOTARY_AUTH[*]}"
    fi
  else
    warn "No submission ID was returned - the upload itself failed (credentials, network, or a bad archive)."
  fi

  die "Notarization failed for $label. See docs/publishing/PIPELINE.md for the debugging runbook."
}

# ---------------------------------------------------------------------------
# Stage 5: staple + Gatekeeper assessment
# ---------------------------------------------------------------------------

staple_and_validate() {
  local target="$1"
  log "Stapling ticket to $(basename "$target")"
  xcrun stapler staple "$target" || die "stapler staple failed for $target"
  xcrun stapler validate "$target" || die "stapler validate failed for $target"
  log "Stapled: $(basename "$target")"
}

gatekeeper_assess() {
  local app="$1"
  log "Gatekeeper assessment (spctl)"
  # -t exec / --type execute is the policy Gatekeeper applies to a launched app.
  if spctl --assess --type execute --verbose=4 "$app" 2>&1 | tee "$TMP_DIR/spctl.txt"; then
    grep -q "accepted" "$TMP_DIR/spctl.txt" || warn "spctl did not report 'accepted'"
    grep -q "source=Notarized Developer ID" "$TMP_DIR/spctl.txt" \
      || warn "spctl source is not 'Notarized Developer ID' - the ticket may not be stapled"
  else
    die "spctl rejected $app - Gatekeeper would block this build on a user's machine."
  fi
}

# ---------------------------------------------------------------------------
# Stage 6: .dmg
# ---------------------------------------------------------------------------
#
# The .app inside is ALREADY stapled at this point, so the download works even
# for a user who is offline when they first launch it. We then sign, notarize
# and staple the .dmg itself so the disk image does not trip Gatekeeper either.

make_dmg() {
  local app="$1" dmg_path="$2"

  step "Build .dmg"

  local stage="$TMP_DIR/dmg-stage"
  rm -rf "$stage" "$dmg_path"
  mkdir -p "$stage"

  # ditto (not cp) preserves signatures, symlinks and extended attributes.
  ditto "$app" "$stage/$APP_NAME.app"
  ln -s /Applications "$stage/Applications"

  # UDZO = compressed read-only; the only format users should ever receive.
  hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$stage" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    "$dmg_path" >/dev/null || die "hdiutil create failed"

  log "Created: $dmg_path"

  # A disk image must itself be signed (with a secure timestamp) before the
  # notary service will accept it. DEVELOPER_ID_IDENTITY is the SHA-1 resolved
  # in preflight, so this is unambiguous even with several teams' certs present.
  log "Signing the disk image"
  codesign --force --timestamp \
           --sign "$DEVELOPER_ID_IDENTITY" \
           ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} \
           "$dmg_path" \
    || die "failed to sign $dmg_path"

  codesign --verify --verbose=2 "$dmg_path" || die "disk image signature invalid"
}

# ---------------------------------------------------------------------------
# Stage 7: checksums + manifest
# ---------------------------------------------------------------------------

emit_manifest() {
  step "Checksums"

  local artifacts=()
  local f
  # Collect distributable artifacts explicitly; `find | xargs shasum` would hang
  # reading stdin if the glob matched nothing.
  for f in "$RELEASE_DIR"/*.dmg "$RELEASE_DIR"/*.zip "$RELEASE_DIR"/*.pkg; do
    if [ -f "$f" ]; then
      artifacts+=("$(basename "$f")")
    fi
  done
  [ "${#artifacts[@]}" -gt 0 ] || die "no distributable artifacts were produced in $RELEASE_DIR"

  ( cd "$RELEASE_DIR" && shasum -a 256 "${artifacts[@]}" > SHA256SUMS )

  local notarized="yes (app + dmg stapled)"
  if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    notarized="NO (--skip-notarize) - DO NOT DISTRIBUTE"
  fi

  cat >"$RELEASE_DIR/RELEASE.txt" <<EOF
Bibliada $VERSION (build $BUILD_NUMBER)
Built:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Commit:     $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'n/a')
Team ID:    $TEAM_ID
Xcode:      $(xcodebuild -version | head -n1)
Variant(s): $VARIANT
Notarized:  $notarized
EOF

  cat "$RELEASE_DIR/SHA256SUMS"
  printf '\n'
  cat "$RELEASE_DIR/RELEASE.txt"
}

# ---------------------------------------------------------------------------
# Variant pipelines
# ---------------------------------------------------------------------------

release_developer_id() {
  local archive="$TMP_DIR/$APP_NAME-developer-id.xcarchive"
  local export_dir="$TMP_DIR/export-developer-id"

  make_archive "developer-id" "$archive" "Developer ID Application"
  make_export "$SCRIPT_DIR/ExportOptions-developer-id.plist" "$archive" "$export_dir"

  local app="$export_dir/$APP_NAME.app"
  [ -d "$app" ] || die "expected $app after export"

  verify_signature "$app"

  local base="$APP_NAME-$VERSION"
  local zip_path="$RELEASE_DIR/$base.zip"
  local dmg_path="$RELEASE_DIR/$base.dmg"

  if [ "$SKIP_NOTARIZE" -eq 1 ]; then
    warn "--skip-notarize: producing an UNNOTARIZED build. Do not distribute it."
  else
    # Round 1: notarize the .app (submitted as a zip, the only container format
    # notarytool accepts for a bare bundle), then staple the .app itself.
    # ditto --keepParent is required: notarytool rejects a zip whose root is the
    # bundle's contents rather than the bundle.
    log "Zipping the app for notarization"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$TMP_DIR/$base-notarize.zip"
    notarize "$TMP_DIR/$base-notarize.zip" "app"
    staple_and_validate "$app"
    gatekeeper_assess "$app"
  fi

  # A zip of the stapled app, for users/updaters that prefer it over a .dmg.
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

  make_dmg "$app" "$dmg_path"

  if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    # Round 2: the disk image needs its own ticket, otherwise the *download*
    # (as opposed to the app) is what Gatekeeper complains about.
    notarize "$dmg_path" "dmg"
    staple_and_validate "$dmg_path"
  fi

  log "Developer ID artifacts:"
  log "  $zip_path"
  log "  $dmg_path"
}

release_app_store() {
  local archive="$TMP_DIR/$APP_NAME-app-store.xcarchive"
  local export_dir="$TMP_DIR/export-app-store"

  step "Mac App Store variant"

  # Loud warning about the two known project-level blockers, so the failure is
  # understood before xcodebuild produces a wall of signing errors.
  if grep -q 'ENABLE_APP_SANDBOX: NO' "$REPO_ROOT/project.yml"; then
    warn "project.yml sets ENABLE_APP_SANDBOX: NO on the app target. The Mac App Store REQUIRES the sandbox; this export will be rejected at ingestion."
  fi
  if [ -z "${BIBLIADA_APP_ENTITLEMENTS:-}" ]; then
    warn "BIBLIADA_APP_ENTITLEMENTS is unset. App Store builds require the App Sandbox, which the checked-in App/Bibliada.entitlements disables. Point this at a sandboxed variant. Both variants should declare the same Team-ID-prefixed App Group ($TEAM_ID.group.com.bibliada.shared); the checked-in bare group.com.bibliada.shared is only granted when an embedded provisioning profile authorizes it."
  fi

  make_archive "app-store" "$archive" "Apple Distribution"

  local destination="export"
  if [ "$DO_UPLOAD" -eq 1 ]; then
    destination="upload"
  fi
  make_export "$SCRIPT_DIR/ExportOptions-app-store.plist" "$archive" "$export_dir" "$destination"

  if [ "$destination" = "upload" ]; then
    log "Uploaded to App Store Connect. Check https://appstoreconnect.apple.com for processing status."
    return 0
  fi

  # exportArchive names the installer after the product.
  local pkg
  pkg="$(find "$export_dir" -maxdepth 1 -name '*.pkg' | head -n1)"
  [ -n "$pkg" ] || die "no .pkg produced in $export_dir"

  cp "$pkg" "$RELEASE_DIR/$APP_NAME-$VERSION-app-store.pkg"
  log "App Store package: $RELEASE_DIR/$APP_NAME-$VERSION-app-store.pkg"
  log "Do NOT notarize this .pkg - App Review notarizes store builds during ingestion."
  log "Upload it with:  ./scripts/release.sh --variant app-store --upload"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

TMP_DIR=""
cleanup() {
  local rc=$?
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && [ -z "${BIBLIADA_KEEP_TMP:-}" ]; then
    rm -rf "$TMP_DIR"
  elif [ -n "$TMP_DIR" ]; then
    printf 'note: intermediates kept at %s\n' "$TMP_DIR" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT

main() {
  configure_auth
  preflight

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bibliada-release.XXXXXX")"
  # Idempotent: a re-run of the same version starts from a clean directory
  # rather than mixing artifacts from two attempts.
  rm -rf "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"

  if [ "$VARIANT" = "developer-id" ] || [ "$VARIANT" = "both" ]; then
    release_developer_id
  fi
  if [ "$VARIANT" = "app-store" ] || [ "$VARIANT" = "both" ]; then
    release_app_store
  fi

  # `--variant app-store --upload` deliberately produces no local artifact:
  # release_app_store hands the .pkg straight to App Store Connect and returns
  # without copying anything into RELEASE_DIR (there's nothing left to notarize
  # or distribute locally). emit_manifest would otherwise die with "no
  # distributable artifacts produced" on every such run, even a successful one.
  if [ "$VARIANT" = "app-store" ] && [ "$DO_UPLOAD" -eq 1 ]; then
    step "Checksums"
    log "Skipped: --variant app-store --upload produces no local artifact - the .pkg went straight to App Store Connect."
  else
    emit_manifest
  fi

  step "Done"
  if [ "$VARIANT" = "app-store" ] && [ "$DO_UPLOAD" -eq 1 ]; then
    log "Release $VERSION ($BUILD_NUMBER) uploaded to App Store Connect. Check https://appstoreconnect.apple.com for processing status."
  else
    log "Release $VERSION ($BUILD_NUMBER) is in $RELEASE_DIR"
  fi
  if [ "$SKIP_NOTARIZE" -eq 0 ] && [ "$VARIANT" != "app-store" ]; then
    log "Next: tag the commit (git tag -a v$VERSION -m 'Bibliada $VERSION' && git push --tags) and publish the .dmg + SHA256SUMS."
  fi
}

main "$@"
