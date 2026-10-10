# Development

[Documentation home](README.md) · [Architecture](ARCHITECTURE.md) · [Contributing](../CONTRIBUTING.md)

Choose a component and install its toolchain. You can contribute to the website or Android client without setting up every native app. Run the commands below from the repository root unless a block changes directory.

## Toolchains

| Component | Tools | Minimum app OS |
| --- | --- | --- |
| Mac host | Xcode 27 with its command-line tools | macOS 14 |
| iPhone/iPad client | Xcode 27 and an installed iOS Simulator runtime | iOS/iPadOS 17 |
| Android client | JDK 17+, Android SDK platform 36 and platform-tools | Android 12 (API 31) |
| Website | Node.js 24 LTS, pnpm version pinned in `apps/web/package.json` | Browser |
| Protocol fixtures | Python 3, standard library only | Not applicable |
| Brand asset generation | Python 3 and Pillow | Not applicable |

The repository includes a pinned Gradle wrapper; a system Gradle installation is unnecessary. Android builds can use `ANDROID_HOME` or an `apps/android/local.properties` file containing your local `sdk.dir`.

```sh
./scripts/doctor.sh
```

The doctor installs nothing. It checks the Xcode 27 family, JDK, SDK platform, wrapper integrity, and optional Mac signing configuration, then reports attached Android devices. It checks all native toolchains, even if you work on only one component. Its SDK check uses `ANDROID_HOME` or the default macOS SDK location, so set `ANDROID_HOME` if your SDK is elsewhere.

Keep local paths and signing settings out of commits. Toolchain upgrades should update the doctor, build configuration, and these instructions together.

## Mac host

```sh
./scripts/build-macos.sh
open apps/macos/build/DerivedData/Build/Products/Debug/Tetherly.app
```

The build script uses the `Tetherly` scheme and a repository-local DerivedData directory. The host runs in the menu bar. Follow [first connection](GETTING_STARTED.md) to grant permissions and pair a client.

Run the host/core checks:

```sh
xcodebuild test -project apps/macos/Tetherly.xcodeproj -scheme TetherlyTests
```

### Mac signing and permissions

The default build is signed ad hoc and does not require an Apple developer account. A rebuild can cause macOS permission grants to become invalid. Run one copy from a consistent location and grant Screen Recording and Accessibility to that copy.

For a stable development identity, copy the local configuration template:

```sh
cp apps/macos/Signing.local.xcconfig.example apps/macos/Signing.local.xcconfig
```

Edit the copied file to match your own installed signing certificate and team. This file is git-ignored. A team ID alone is insufficient without the corresponding certificate and private key. Stable signing helps preserve the app identity across rebuilds; verify permissions after changing the signing configuration.

A Release configuration can be built with:

```sh
CONFIGURATION=Release ./scripts/build-macos.sh
```

That creates a Release build, not a notarized public installer. Distribution has separate steps in the [publishing checklist](PUBLISHING.md).

## Android client

```sh
./scripts/build-android.sh
```

This runs JVM unit tests and builds `apps/android/app/build/outputs/apk/debug/app-debug.apk`. An emulator is sufficient for many UI checks. A physical device is needed for realistic pairing, capture/input interaction, decoder performance, and remote-network evidence.

With one authorized device attached and USB debugging enabled:

```sh
adb devices -l
./scripts/install-android.sh
```

The installer installs and launches the existing debug APK; build it first. For multiple devices, use the [explicit device commands](TROUBLESHOOTING.md#the-android-installer-sees-more-than-one-device).

You can also open `apps/android` in Android Studio. Use the checked-in wrapper and project configuration when importing it.

QR scanning also needs a release check: R8 must preserve ML Kit's manifest-discovered registrar constructors. From the repository root:

```sh
cd apps/android
./gradlew assembleRelease
cd ../..
./scripts/check-android-qr-registrars.sh apps/android/app/build/outputs/apk/release/app-release-unsigned.apk
```

The default release build is unsigned. Local distribution can supply the dedicated upload-key environment variables; see [release workflow](../release/README.md). Run the same checker on a signed APK before device acceptance; passing a debug build does not exercise release optimization. The checker needs Python 3 and Android SDK `apkanalyzer` (set `APKANALYZER` if it is installed elsewhere).

## iPhone and iPad client

```sh
open apps/ios/TetherlyiOS.xcodeproj
```

Select the `TetherlyiOS` scheme and an installed Simulator. For a physical device, select your own development team in Xcode and complete the device's developer setup. Allow Local Network access and camera access when scanning a pairing QR code.

Build for the Simulator without device signing:

```sh
xcodebuild build \
  -project apps/ios/TetherlyiOS.xcodeproj \
  -scheme TetherlyiOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Find an available Simulator, then run tests using its identifier:

```sh
xcrun simctl list devices available
xcodebuild test \
  -project apps/ios/TetherlyiOS.xcodeproj \
  -scheme TetherlyiOSTests \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID'
```

Replace `SIMULATOR_UDID` with an available iPhone Simulator identifier. Simulator results do not establish physical-device audio, input, network, or long-session behavior.

## Website

```sh
cd apps/web
pnpm install --frozen-lockfile
pnpm dev
```

Open `http://localhost:3000`. From the same directory:

```sh
pnpm lint
pnpm build
pnpm start
```

`pnpm start` serves the production build after `pnpm build`. Check affected pages at desktop and narrow mobile widths, keyboard navigation, light/dark themes, and reduced motion. Detailed source and deployment instructions live in the [website README](../apps/web/README.md).

## Protocol and fixtures

Read the [wire contract](../protocol/SPEC.md) before changing messages, framing, pairing, or channel behavior. Swift and Kotlin checks share generated golden fixtures.

```sh
python3 scripts/gen-fixtures.py
git diff -- protocol/fixtures
```

Commit intended fixture changes with the generator, specification, and affected implementations. An unchanged generator should reproduce the checked-in fixtures. A protocol change needs checks across the host, Android, and iOS, not just the component where it started.

## Brand assets

Selected masters live in `design/brand/`. The icon generator requires Pillow:

```sh
python3 scripts/gen-icons.py
```

Review generated changes before committing them. Use the selected masters and retain attribution/provenance; see the [illustration notes](FEATURE_ILLUSTRATIONS_2D.md) for the website assets. Screenshots and bug reports should contain disposable content rather than private documents.

## Checks and evidence

Automatic GitHub CI and Dependabot version-update PRs are disabled at the owner's request. Run the local fixture, Android, Mac, iOS Simulator, and website checks documented above before a release. Record the source commit and actual results; a successful build alone does not establish device behavior.

For a pull request, record the commands you ran, their results, and the exact platforms/devices used. Explain any checks you could not run. Follow physical-device checks for capture, input, permissions, transfers, audio, and reconnect behavior with an entry in the [acceptance record](ACCEPTANCE.md) when they establish a project milestone.

[Next: contributing](../CONTRIBUTING.md)
