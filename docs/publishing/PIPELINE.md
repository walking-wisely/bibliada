# Bibliada release pipeline

How Bibliada gets from source to two shippable products:

1. **Developer ID** — a notarized, stapled `.dmg` (and `.zip`) for direct
   download from a website or GitHub Release.
2. **Mac App Store** — a signed `.pkg` uploaded to App Store Connect.

`build.sh` is untouched by all of this: it remains the fast local
build-and-install loop, including its unsigned/ad-hoc fallback when
`BIBLIADA_TEAM_ID` is empty. Release builds have no such fallback — an ad-hoc
signed binary can never be notarized.

## Files

| File | Purpose |
| --- | --- |
| `scripts/release.sh` | The whole pipeline in one command |
| `scripts/ExportOptions-developer-id.plist` | `xcodebuild -exportArchive` options, direct download |
| `scripts/ExportOptions-app-store.plist` | `xcodebuild -exportArchive` options, Mac App Store |
| `.github/workflows/release.yml` | The same pipeline on a GitHub-hosted macOS runner |

Both `.plist` files are **templates**: `release.sh` copies them and fills in
`teamID` with `plutil -replace` before handing them to `xcodebuild`. Do not run
`xcodebuild -exportArchive` against them directly without substituting the
placeholder.

---

## What the pipeline actually does

```
xcodegen generate                     # the .xcodeproj is gitignored — always regenerate
  -> xcodebuild archive               # Release config, real Developer ID identity
  -> xcodebuild -exportArchive        # re-signs app + embedded widget for distribution
  -> verify signature                 # Developer ID? hardened runtime? secure timestamp? .appex OK?
  -> ditto -c -k --keepParent         # zip the .app (notarytool won't take a bare bundle)
  -> notarytool submit --wait         # round trip 1 — prints the submission ID
  -> stapler staple <app>             # ticket lands inside the .app
  -> spctl --assess --type execute    # what Gatekeeper will actually decide
  -> hdiutil create + codesign        # build and sign the .dmg
  -> notarytool submit --wait         # round trip 2 — the disk image needs its own ticket
  -> stapler staple <dmg>
  -> shasum -a 256 > SHA256SUMS       # plus RELEASE.txt with commit/version/Xcode
```

### Why two notarization round trips

Notarizing only the `.dmg` gives the *disk image* a ticket but leaves the `.app`
inside it without one. Gatekeeper checks the app separately on first launch; if
the user is offline (or behind a proxy that blocks Apple's OCSP/notary hosts),
that check fails and the app is blocked even though it was notarized. Stapling
the `.app` first, then building the `.dmg` around the already-stapled app, then
notarizing and stapling the `.dmg`, makes the download work offline. It costs
one extra round trip — usually a few minutes.

The same principle in one line: **sign inside-out, notarize and staple every
container you hand to a user.**

---

## One-time setup

Nothing below can be done before the Apple Developer Program membership is
active. Budget a day: enrollment approval is not instant, and for an individual
account it can require an identity check.

### 1. Enroll and get the Team ID

<https://developer.apple.com/programs/> ($99/yr). Once active, the 10-character
Team ID is at <https://developer.apple.com/account> under Membership details.

```sh
export BIBLIADA_TEAM_ID=ABCDE12345      # same variable build.sh already uses
```

Put that in `~/.zshrc` so both `build.sh` and `release.sh` see it.

### 2. Create the certificates

Easiest path — Xcode > Settings > Accounts > (your Apple ID) > Manage
Certificates > **+**:

| Certificate | Needed for |
| --- | --- |
| Developer ID Application | signing the `.app` and `.dmg` for direct download |
| Apple Distribution | signing the `.app` for the Mac App Store |
| Mac Installer Distribution | signing the `.pkg` for the Mac App Store |

Verify they landed:

```sh
security find-identity -v -p codesigning
```

You should see `Developer ID Application: Your Name (ABCDE12345)`.

> Developer ID certificates are limited (currently 5 per type per account) and
> **cannot be re-downloaded with their private key**. Export each one to a `.p12`
> and back it up now — losing the private key means burning one of your slots.

### 3. Register the App IDs and the App Group

At <https://developer.apple.com/account/resources/identifiers>:

- App ID `com.bibliada.Bibliada` with the **App Groups** capability.
- App ID `com.bibliada.Bibliada.Widget` with the **App Groups** capability.
- App Group `group.com.bibliada.shared`, enabled on both App IDs.

This is what finally makes the widget see the app's settings — see the
"Signing caveat" section of `README.md` for what happens without it.

> **Prefer the Team-ID-prefixed form.** Registering the bare
> `group.com.bibliada.shared` above only grants the entitlement when an embedded
> provisioning profile authorizes it. Switching the entitlements files to
> `$(TeamIdentifierPrefix)group.com.bibliada.shared` makes the group
> self-authorizing on **both** channels and needs no portal registration at all.
> Since macOS 15 Sequoia, `~/Library/Group Containers` is SIP-protected and
> access requires one of: Mac App Store delivery, a Team-ID prefix, or profile
> authorization. Whichever form you pick, use the **same one in both variants** —
> differing identifiers mean different container directories, so a user moving
> between the store build and the direct download silently loses every setting
> and the cached verse.

### 4. Create an App Store Connect API key

<https://appstoreconnect.apple.com> > Users and Access > Integrations > Keys >
**+**. Role **Developer** is enough for notarization.

Record three things:

- the `.p8` file (**downloadable exactly once** — save it to
  `~/private_keys/AuthKey_XXXXXXXXXX.p8`, `chmod 600`, and back it up)
- the **Key ID** (10 characters)
- the **Issuer ID** (a UUID, shown above the key list)

API keys beat an Apple ID + app-specific password for automation: no 2FA
prompts, independently revocable, and not tied to your personal login.

### 5. Store notarytool credentials locally (once)

```sh
xcrun notarytool store-credentials "bibliada-notary" \
  --key ~/private_keys/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 11111111-2222-3333-4444-555555555555
```

`store-credentials` validates against Apple before saving, so a success here
means the credentials really work. It writes a keychain item that `release.sh`
finds via `--keychain-profile bibliada-notary` (override the name with
`BIBLIADA_NOTARY_PROFILE`).

For an **Individual** (personal) API key, omit `--issuer` entirely — notarytool
rejects an issuer ID for individual keys. Team keys require it.

App-specific-password alternative (works, but the secret ends up on your
command line):

```sh
xcrun notarytool store-credentials "bibliada-notary" \
  --apple-id you@example.com --team-id "$BIBLIADA_TEAM_ID" --password <app-specific-password>
```

Generate the password at <https://account.apple.com> > Sign-In and Security >
App-Specific Passwords.

### 6. Verify the whole thing without touching Apple

```sh
./scripts/release.sh --skip-notarize
```

This runs archive, export, and every signature check, and builds a `.dmg` — but
makes no notary submission. If this passes, the only remaining failure modes are
Apple-side.

---

## Running a release

```sh
export BIBLIADA_TEAM_ID=ABCDE12345

./scripts/release.sh                          # Developer ID, version from project.yml
./scripts/release.sh --version 1.1 --build 12  # explicit version/build
./scripts/release.sh --variant app-store       # Mac App Store .pkg
./scripts/release.sh --variant app-store --upload   # ...and push it to App Store Connect
./scripts/release.sh --variant both
./scripts/release.sh --help                    # full env-var reference
```

Output lands in `dist/<version>-<build>/`:

```
Bibliada-1.1.dmg        notarized + stapled disk image  <- this is what users download
Bibliada-1.1.zip        notarized + stapled app, zipped
SHA256SUMS              checksums of the above
RELEASE.txt             version, build, commit, Xcode version, team, notarization status
submission-ids.txt      notarytool submission IDs for this release
```

> Add `dist/` and `.build-release/` to `.gitignore` before the first release —
> neither is ignored today, and the preflight's clean-working-tree check will
> trip on leftover artifacts from the previous run.

Version and build numbers are passed to `xcodebuild` on the command line
(`MARKETING_VERSION=`, `CURRENT_PROJECT_VERSION=`), so cutting a release never
edits and never dirties `project.yml`.

### Preflight guarantees

`release.sh` refuses to start unless all of these hold, so you never discover a
problem 15 minutes into a notarization wait:

- `xcodegen`, `xcodebuild`, `notarytool`, `stapler`, `hdiutil`, `ditto`, `plutil` present
- `BIBLIADA_TEAM_ID` set and shaped like a real Team ID
- a `Developer ID Application` certificate **for that team** exists (its SHA-1 is
  resolved up front, so signing is unambiguous even with several teams' certs installed)
- notary credentials exist (keychain profile present, or API key file readable)
- the git working tree is clean (`BIBLIADA_ALLOW_DIRTY=1` to override)
- the version is not already tagged/released (`BIBLIADA_ALLOW_RELEASED=1` to override)

### CI

Push a tag to run the pipeline on a hosted runner:

```sh
git tag -a v1.1 -m 'Bibliada 1.1'
git push origin v1.1
```

The workflow imports the `.p12` into a throwaway keychain, decodes the API key
to `$RUNNER_TEMP`, runs the same `scripts/release.sh`, uploads artifacts, and
creates a GitHub Release. Required secrets are documented in the comment header
of `.github/workflows/release.yml`.

The Mac App Store job is present but gated behind `if: false` — see
"Project-specific gotchas" below.

---

## How long notarization takes

- **Typical: 1–15 minutes** per submission. Most finish in a couple of minutes.
  Bibliada is a small app with no third-party frameworks, so it sits at the fast
  end.
- The pipeline makes **two** submissions, so budget roughly **5–20 minutes** of
  notarization per release on top of build time.
- **Tens of minutes** happens when a submission is pulled for deeper analysis.
  Unpleasant but normal; `--wait` keeps blocking.
- **Hours** is not normal. It means an Apple-side incident. Multi-day
  "In Progress" outages have happened (most recently a widely reported one in
  early 2026). Check <https://developer.apple.com/system-status/> before
  debugging your own build.

`BIBLIADA_NOTARY_TIMEOUT` (default `45m`) caps how long `--wait` blocks. Hitting
the timeout does **not** cancel the submission — Apple keeps processing it. Pick
it back up with the ID that `release.sh` printed and saved:

```sh
xcrun notarytool info    <submission-id> --keychain-profile bibliada-notary
xcrun notarytool wait    <submission-id> --keychain-profile bibliada-notary
xcrun notarytool log     <submission-id> --keychain-profile bibliada-notary
xcrun notarytool history --keychain-profile bibliada-notary
```

### Keeping it fast

- Notarize the **smallest thing that works**. The pipeline submits a compressed
  zip of the app and a UDZO-compressed dmg, not raw directories.
- Do not re-run the whole pipeline to retry a *stapling* failure — the ticket is
  already minted; `xcrun stapler staple` again.
- `--s3-acceleration` is on by default in notarytool; leave it alone.
- Catch rejections locally. Every check in `verify_signature` exists because it
  corresponds to a specific notary rejection; failing in 2 seconds beats failing
  in 10 minutes.

---

## Debugging runbook

`release.sh` fetches the notary log automatically on rejection, prints a
severity/message/path summary, and saves the full JSON to
`dist/<version>-<build>/notarytool-<label>-<submission-id>.json`. The `issues`
array is the actionable part; `statusSummary` is the headline.

To read a log by hand:

```sh
xcrun notarytool log <submission-id> --keychain-profile bibliada-notary
```

### `The signature does not include a secure timestamp.`

Signed without network access, or with `--timestamp=none`. `codesign` silently
omits the RFC 3161 timestamp when it cannot reach Apple's timestamp server.
Reconnect and rebuild. Confirm with:

```sh
codesign --display --verbose=4 dist/*/Bibliada.app 2>&1 | grep Timestamp
```

Preflight catches this before submission.

### `The executable does not have the hardened runtime enabled.`

`ENABLE_HARDENED_RUNTIME` must be `YES` on **both** targets. `project.yml`
already sets it; if it regresses, `verify_signature` fails locally.

```sh
codesign --display --verbose=4 <path> 2>&1 | grep 'flags='   # must contain 'runtime'
```

### `The binary is not signed with a valid Developer ID certificate.`

You built with the ad-hoc fallback. `project.yml` sets
`CODE_SIGN_IDENTITY: "-"` as the no-team default; `release.sh` overrides it on
the command line. This error means either `BIBLIADA_TEAM_ID` was empty (preflight
would have caught it) or the archive was made by `build.sh` rather than
`release.sh`. Never notarize a `build.sh` product.

### Issue paths pointing inside `Contents/PlugIns/BibliadaWidget.appex`

The embedded widget extension is signed **before** the app that contains it
(inside-out), which XcodeGen expresses as `embed: true, codeSign: true` on the
`BibliadaWidget` dependency. If the `.appex` is unsigned, stale, or signed with a
different identity than the enclosing app, notarization rejects the whole
submission with paths inside `PlugIns/`. Check:

```sh
codesign --verify --deep --strict --verbose=2 dist/*/Bibliada.app
codesign --display --verbose=4 dist/*/Bibliada.app/Contents/PlugIns/BibliadaWidget.appex
```

Fix by rebuilding cleanly (`rm -rf .build-release`) rather than by re-signing
the `.appex` in place — a hand re-signed extension invalidates the outer
signature.

### `Team is not yet configured for notarization` / `403` / `401`

- Membership not fully active yet (can lag hours after payment).
- API key lacks a sufficient role, or the `.p8` does not match the Key ID.
- Issuer ID supplied for an **Individual** key (must be omitted), or missing for
  a **Team** key (required).
- Re-run `xcrun notarytool store-credentials`; it validates against Apple and
  will tell you which half is wrong.

### `Error: HTTP status code: 401. Unable to authenticate.` in CI only

The keychain relocked or the partition list was never set. Both are handled in
`release.yml` (`set-keychain-settings -lut`, `set-key-partition-list`); if you
change that step, keep both.

### `User interaction is not allowed` during codesign in CI

`security set-key-partition-list` was skipped or ran before `security import`.
Order matters: create keychain → unlock → import → set partition list → make it
the default.

### `notarytool submit` succeeds but `spctl` still rejects the app

The ticket was minted but not stapled, or was stapled to the wrong copy. Staple
the exact bundle you are about to ship, then:

```sh
xcrun stapler validate  dist/*/Bibliada.app
spctl --assess --type execute --verbose=4 dist/*/Bibliada.app
```

A healthy result reports `accepted` and `source=Notarized Developer ID`.

### Users see "damaged and can't be opened"

Almost always a stapling or transport problem, not a signing one: the app was
delivered through something that stripped extended attributes (a plain `cp`,
some upload pipelines), or it was zipped with Finder/`zip` instead of `ditto`.
Always distribute the pipeline's `.dmg`, or its `.zip` (created with
`ditto -c -k --sequesterRsrc --keepParent`).

### Submission stuck "In Progress" for hours

Check <https://developer.apple.com/system-status/> first. If the notary service
is healthy, cancel the wait (Ctrl-C — the submission survives) and poll with
`xcrun notarytool info <id>`. Resubmitting the same binary rarely helps and only
adds queue load.

### `altool` errors

`xcrun altool` has not accepted notarization uploads since **2023-11-01**. If
any tooling still calls it for notarization, it is broken by definition. This
pipeline uses `notarytool` exclusively. (`altool` is still used by some
workflows for *App Store uploads*; this pipeline uses
`xcodebuild -exportArchive` with `destination: upload` instead.)

---

## Project-specific gotchas

### The `.xcodeproj` is generated

`Bibliada.xcodeproj` is gitignored. Both `release.sh` and the CI workflow run
`xcodegen generate` before every build, so a release can never be cut from a
stale project file — but it also means **XcodeGen must be installed on any
machine that releases** (`brew install xcodegen`; the workflow does this). Keep
the CI XcodeGen version close to the local one (2.46.0) so generated projects do
not diverge.

### The widget must be signed before the app

The archive contains `Bibliada.app/Contents/PlugIns/BibliadaWidget.appex`. Code
signatures nest: signing the app seals the extension's signature inside it, so
the extension must be signed first and must never be touched afterwards.
`project.yml`'s `dependencies: [{target: BibliadaWidget, embed: true,
codeSign: true}]` gives the right order, and `xcodebuild -exportArchive` re-signs
the whole tree correctly when it swaps in the distribution identity. Do not
"fix" a signing problem by running `codesign` on the `.appex` inside an exported
app — that silently invalidates the app's own seal.

Both targets need `ENABLE_HARDENED_RUNTIME: YES` (they have it) and both need to
appear in the provisioning profiles. A missing *widget* profile is the most
common export failure for an app with an extension.

### What differs between the two variants

| | Developer ID | Mac App Store |
| --- | --- | --- |
| App Sandbox (app target) | optional (currently `NO`) | **required** |
| App Group ID | `$(TeamIdentifierPrefix)group.com.bibliada.shared` | same |

**The App Group should NOT differ.** An earlier draft of this document had the
prefix rule backwards. The actual rule: the Team-ID-prefixed form is
self-authorizing and valid on both channels, while the bare
`group.com.bibliada.shared` form requires portal registration *and* an embedded
provisioning profile authorizing it — on either channel, not just one. Since
macOS 15 Sequoia, `~/Library/Group Containers` is SIP-protected and access
requires one of: Mac App Store delivery, a Team-ID prefix, or profile
authorization.

Use `$(TeamIdentifierPrefix)group.com.bibliada.shared` in both variants. XcodeGen
expands it at build time, so one source spelling serves both channels, both
builds share one container, and users switching between the store version and
the direct download keep their settings. Two different identifiers would mean two
different container directories and silent data loss on switching.

*Not yet verified against Apple documentation:* that App Store ingestion accepts
a Team-ID-prefixed group. Confirm on the first upload. If it is rejected, use the
bare form for the store variant and add a first-launch migration in
`SettingsStore.init` / `VerseCache` that reads whichever domain is populated.

The sandbox difference alone still means the variants need **different
entitlements files** — `App/Bibliada.entitlements` cannot serve both. To make the
switch possible you need two things:

1. Variant files: `App/Bibliada-AppStore.entitlements` and
   `Widget/BibliadaWidget-AppStore.entitlements`.
2. `project.yml` referencing them through XcodeGen variable substitution, the
   same mechanism it already uses for `DEVELOPMENT_TEAM`, with the current paths
   as defaults — e.g. `CODE_SIGN_ENTITLEMENTS: ${BIBLIADA_APP_ENTITLEMENTS}` on
   the app target and `${BIBLIADA_WIDGET_ENTITLEMENTS}` on the widget.

Then:

```sh
BIBLIADA_APP_ENTITLEMENTS=App/Bibliada-AppStore.entitlements \
BIBLIADA_WIDGET_ENTITLEMENTS=Widget/BibliadaWidget-AppStore.entitlements \
./scripts/release.sh --variant app-store
```

`release.sh` exports these before running `xcodegen generate` and **warns loudly
if `project.yml` does not reference them**, because an ignored override is worse
than a missing one. Note that these deliberately are *not* passed to `xcodebuild`
as a `CODE_SIGN_ENTITLEMENTS=` build setting: command-line build settings apply
to every target, which would give `BibliadaWidget` the app's entitlements.

If the group ID is wrong for the variant, nothing fails at build time — the app
and widget just silently fall back to separate `UserDefaults`, exactly the
failure mode `README.md` describes for unsigned builds. Test the *installed*
store build, not the exported one.

`release.sh` warns about both of these before it starts the App Store build, and
the CI `app-store` job is gated behind `if: false` until they are resolved.

### Mac App Store builds are not notarized by you

App Review notarizes store submissions during ingestion. Never run `notarytool`
on the store `.pkg`; `release.sh` skips the entire notarize/staple/dmg stage for
`--variant app-store`.

### `build.sh` and `release.sh` use different derived-data directories

`build.sh` uses `.build/`, `release.sh` uses `.build-release/`. They will not
fight over each other's intermediates, and a broken release build can be reset
with `rm -rf .build-release` without disturbing your local dev loop.
