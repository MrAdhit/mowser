# Mowser

Chromium for Android, Linux, Windows and macOS, built from upstream Chromium
plus the patches in `patches/`. On every platform it runs uBlock Origin as a
built-in extension. On Android it also differs from stock Chromium in these
ways:

- It signs in to Google and syncs through MicroG-RE (`app.revanced.android.gms`)
  instead of Google Play services.
- It retrieves the trusted vault keys that encrypt synced passwords through
  MicroG-RE's key retrieval service.
- It keeps passwords in the profile directory, as desktop Chromium does, so
  synced passwords autofill without Google Play services.
- It runs the extensions synced from the Google account.
- It shows the phone UI on phones and the desktop UI on tablets.

Desktop builds sign in and sync with the Google API key and OAuth client they
are built with (see [Repository secrets](#repository-secrets)).

MicroG-RE mints the access tokens. When it requests them from Google it reports
Mowser as Chrome (`com.android.chrome`, signing certificate SHA-1
`38918a453d07199354f8b19af05ec6562ced5788`), read from the
`app.revanced.android.gms.SPOOFED_PACKAGE_NAME` and `…SPOOFED_PACKAGE_SIGNATURE`
manifest meta-data.

## Layout

| Path | Contents |
|---|---|
| `chromium-version` | The Chromium version Mowser builds |
| `args/` | GN build arguments: `common.gn` for every target, and one file per operating system |
| `patches/` | Patches against Chromium `src/`, applied in filename order with `git apply` |
| `scripts/local.sh` | Syncs and builds on a Linux machine |
| `scripts/sync.sh` | Fetches Chromium and runs the gclient hooks |
| `scripts/build.sh` | Applies the patches, bundles uBlock Origin, and builds and packages the targets |
| `scripts/ubo.sh` | Writes the bundled uBlock Origin zip |
| `.github/` | GitHub Actions workflows that build every platform |
| `build.py` | Modal Function that syncs Chromium and builds Android targets |
| `emulator.py` | Modal VM sandbox running an Android emulator, reachable over adb |
| `scripts/emulator/` | Shell steps run inside the emulator sandbox |

## Patches

| Patch | Change |
|---|---|
| `0001-microg-account-manager-delegate.patch` | Adds `MicrogAccountManagerDelegate`, the `AccountManagerDelegate` used for Google accounts. It lists MicroG-RE's `app.revanced` accounts through MicroG-RE's accounts content provider, which also makes them visible to Mowser, gets access tokens from MicroG-RE, looks up Gaia IDs with Google's tokeninfo endpoint, and reports the capabilities of an ordinary adult personal account. |
| `0002-microg-spoof-chrome-identity.patch` | Adds the spoofing meta-data to the manifest, and declares MicroG-RE in `<queries>` so that Mowser can reach its services. |
| `0003-microg-trusted-vault-backend.patch` | Adds `MicrogTrustedVaultBackendFactory`, the trusted vault backend for the Chrome sync security domain. It fetches keys from MicroG-RE's key retrieval service over Binder and opens MicroG-RE's key retrieval UI for "Verify it's you". |
| `0004-built-in-password-store.patch` | When Chrome's Google Play services password backend is absent, keeps the profile and account password stores in `Login Data` and `Login Data For Account` with the desktop `PasswordStoreBuiltInBackend`, and keeps password settings in prefs. |
| `0005-desktop-android-phone-ui.patch` | Keeps the phone UI in the desktop Android configuration: Java code sees a non-desktop build, the WebUI New Tab Page and theming stay off, and the omnibox behaves as on a phone. |
| `0006-bundled-ublock-origin.patch` | Bundles `ublock_origin.zip` (`//mowser`) as an uncompressed APK asset on Android, in the framework bundle's `Resources` on macOS, and next to the executable on Linux and Windows, and loads it as a component extension, unpacked into the profile's `uBlock Origin` directory whenever the bundled zip changes. Also builds the `browserAction` and `pageAction` API schemas on every platform, which uBlock Origin uses. |
| `0007-tablet-desktop-ui.patch` | Shows Chromium's desktop Android UI on devices whose smallest screen width is at least 600dp. |

`args/android.gn` sets `is_desktop_android = true`, the configuration in which
Chromium compiles its extensions system for Android.

## Building

The Chromium version is set by `CHROMIUM_VERSION` (default: the contents of
`chromium-version`). `MOWSER_TARGETS` lists the targets to build, each
`<os>-<cpu>`, with `os` one of `android`, `linux`, `win` and `mac`. Each target
is packaged as:

| OS | Package |
|---|---|
| `android` | `mowser-<target>.apk`, signed with Chromium's in-tree debug key, so each build can replace the previous install |
| `linux` | `mowser-<target>.tar.zst`, the browser's runtime files |
| `win` | `mowser-<target>.zip`, the browser's runtime files |
| `mac` | `mowser-<target>.zip`, holding `Chromium.app` |

Android targets are `android-arm64` for phones and tablets, and `android-x64`
for the emulator.

### On GitHub Actions

The `build` workflow builds the platforms selected when it is started:
Android (`android-arm64`), Linux (`linux-x64`) and Windows (`win-x64`) on
Linux runners, Windows by cross-compiling, and macOS (`mac-arm64`) on macOS
runners. Each target builds in up to eight chained jobs. Each job builds for
up to about five hours and passes the build output to the next job through
the `state-<target>` artifact. A finished build is uploaded as the
`mowser-<target>` artifact.

```bash
gh workflow run build -f android=true -f linux=false -f windows=false -f macos=false
```

The Windows build needs Visual Studio and the Windows SDK packaged by the
`win-toolchain` workflow, which runs on a Windows runner and saves the package
to the Actions cache. The cache entry is dropped after seven days without use,
and is made per Chromium version; run the workflow again in either case.

```bash
gh workflow run win-toolchain
```

### Repository secrets

Desktop builds use these repository secrets for Google sign-in and sync. A
desktop build made without them runs without Google sign-in.

| Secret | GN argument |
|---|---|
| `GOOGLE_API_KEY` | `google_api_key` |
| `GOOGLE_DEFAULT_CLIENT_ID` | `google_default_client_id` |
| `GOOGLE_DEFAULT_CLIENT_SECRET` | `google_default_client_secret` |

### On a Linux machine

The machine needs depot_tools on `PATH` and Chromium's Android build
dependencies (`build/install-build-deps.py --android`).

```bash
scripts/local.sh
```

The checkout lives in `MOWSER_WORK` (default `~/chromium`) and the packages
are written to `MOWSER_OUT` (default `~/mowser-out`). `MOWSER_TARGETS` defaults
to `android-arm64`. `MOWSER_TARGET_OS` lists the operating systems whose
dependencies the checkout fetches besides the host's (default `android`). The
checkout is synced when its version differs from `CHROMIUM_VERSION`.
`MOWSER_SYNC_JOBS` sets the number of parallel fetches during the sync;
googlesource.com answers HTTP 429 when one address opens too many.

### On Modal

```bash
uv sync
uv run modal run --detach build.py
uv run modal volume get mowser-out mowser-android-arm64.apk .
```

The build runs in a Function with 32 cores, 64 GiB of memory and a 400 GiB
local disk; the checkout and build output live on that disk under `/work`. At
the end of each run, successful or not, `/work` is packed into one zstd
archive on the `mowser-state` Volume, and the next run unpacks it, so builds
are incremental. The checkout is synced when there is no archive or when
`CHROMIUM_VERSION` changes. A run is limited to 3 hours. `MOWSER_TARGETS`
defaults to `android-arm64 android-x64`, and the packages are written to the
`mowser-out` Volume.

## Installing on a phone

The phone needs MicroG-RE 7.2.2 or later (MorpheApp), signed in to the Google
account. Google Play services must also be present, because Chromium only
offers sign-in when it is.

```bash
adb install -r mowser-android-arm64.apk
```

## Using

- Passwords synced from the Google account autofill on sign-in forms. The
  Google Password Manager entry in Settings reads "Stopped working on this
  device"; there is no screen that lists saved passwords.
- On Android phones, uBlock Origin's dashboard is at
  `chrome-extension://cbnhekcmihffpmkhiolglckkhmplkhpe/dashboard.html`; the
  phone UI has no extensions toolbar.

## Emulator

Modal sandboxes have no KVM, so the emulator runs an Android 11 x86_64 image
with software emulation on one core. It boots in about seven minutes and is
slow to use. `up` authorizes `~/.android/adbkey.pub` for adb, installs
MicroG-RE, and takes about ten minutes in all. Installing the x64 APK takes
about three more.

The emulator serves one adb connection at a time. `install` disconnects the
local adb from the tunnel while it installs from inside the sandbox and
reconnects it afterwards.

```bash
uv run python emulator.py up                          # prints the adb address
uv run python emulator.py install mowser-android-x64.apk  # from mowser-out, or a local path
adb connect <host>:<port> && scrcpy -s <host>:<port>
uv run python emulator.py down
```

The emulator sandbox stops after `MOWSER_EMULATOR_HOURS` hours (default 2).
