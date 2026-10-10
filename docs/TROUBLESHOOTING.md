# Troubleshooting

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Connection guide](CONNECTIONS.md)

Start with the symptom you see. Work through one change at a time so you know what fixed it.

## My Mac is not listed

- Confirm the Mac is awake and Tetherly is running in its menu bar.
- Turn on **Allow connections**.
- For local access, put both devices on the same network. Guest Wi-Fi may isolate devices.
- Allow Local Network access when requested, including on iPhone/iPad.
- If discovery fails, enter an address shown by the Mac app. Discovery and reachability are separate checks.
- For remote access, verify both devices are online in the same tailnet and try the Mac's Tailscale address.

See [manual address pairing](CONNECTIONS.md#pair-with-an-address).

## The app is running, but I cannot find a window

The Mac host is a menu bar app. Open its menu bar item to see setup, hosting, pairing, and paired-device controls. A Finder or Dock window is not required for it to host sessions.

## I connect, but see no desktop

Check Screen Recording permission in System Settings → Privacy & Security. Newer macOS versions may call it Screen & System Audio Recording. Use the Mac app's setup controls, then reopen Tetherly if prompted.

Keep the Mac awake. Check the app's error message before trying the session again. A successful network connection alone does not prove capture is permitted.

## The desktop is visible, but clicks or typing do not work

Check Accessibility permission for the exact copy of Tetherly you are running. If you rebuilt or moved the app, a previous grant may refer to another copy. Quit that copy, open the intended build, and follow the setup prompts.

Ad hoc development signing can cause macOS to request permissions again after a rebuild. The [signing guide](DEVELOPMENT.md#mac-signing-and-permissions) explains how a stable team signature helps.

## Pairing fails or the codes differ

Cancel on both devices. Open a fresh pairing window on the Mac and try again. Check the codes on the actual Mac you intend to control; do not approve a mismatch.

Pairing windows expire. The current protocol also closes the window after repeated failed or aborted attempts. Reopen Pair New Device to start a fresh attempt.

## I see an identity-changed or already-paired warning

Do not silently accept a different identity. Confirm that this is your Mac and that a rebuild, reinstall, or identity reset explains the change. Remove the old pairing on both sides, then pair again and compare the codes.

If pairing was interrupted after the Mac saved approval but before the client saved it, the Mac may remember the client while the client has no matching record. Revoke that device on the Mac and start a new pair.

## Tailscale is connected, but Tetherly is not

Check that both devices appear online in the intended tailnet. Try the Mac's Tailscale IPv4 address if it is not discovered. Keep Tetherly hosting enabled and confirm pairing is complete.

A managed tailnet needs a policy that permits the client to reach the Mac on TCP `47800`. You do not need an exit node or router port forwarding for this route.

For Tailscale's own setup and diagnostics, use its [official quickstart](https://tailscale.com/docs/how-to/quickstart) and [connection types guide](https://tailscale.com/docs/reference/connection-types).

## The session feels slow

Try a stronger connection on both devices and compare the same session on local Wi-Fi. A Tailscale relay may add delay. The Mac's display and client decoder also affect the session; the project does not yet publish a performance guarantee.

Include the device models, network route, and whether the problem occurs locally when reporting it. Long-session and adverse-network acceptance remain in the [status record](PLAN.md).

## The Android installer sees more than one device

The install helper assumes a single attached device. Choose the intended device explicitly instead:

```sh
adb devices -l
adb -s DEVICE_SERIAL install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
adb -s DEVICE_SERIAL shell am start -n link.tetherly/link.tetherly.MainActivity
```

Replace `DEVICE_SERIAL` with the identifier from `adb devices -l`.

## The website preview shows old styles

Restart the local development server first. If its development cache is still stale, stop the server and move `apps/web/.next/dev` aside, then restart from `apps/web`. This cache is generated output. Keep any backup outside the upload root and preserve your source changes.

For Vercel, the configured Root Directory and CLI upload root must agree. The monorepo project uses `apps/web` as Root Directory and CLI uploads from the repository root. See the [website README](../apps/web/README.md#vercel-monorepo-uploads).

## Ask for help with useful details

Use the repository's bug template and include:

- App/commit version, macOS version, client OS, and device models.
- Local Wi-Fi or Tailscale, and the step that failed.
- Expected result, actual result, and a short reproduction sequence.
- Relevant error text and which checks above you tried.

Remove private desktop content, clipboard text, pairing codes, QR links, and key material before sharing logs or screenshots. Send security issues privately as described in the [security policy](../SECURITY.md).
