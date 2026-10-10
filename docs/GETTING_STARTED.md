# Your first connection

[Documentation home](README.md) · [Connection guide](CONNECTIONS.md) · [Troubleshooting](TROUBLESHOOTING.md)

Tetherly connects a phone or tablet to the desktop already running on your Mac. This guide takes you from a development build to a first local session.

## Before you begin

| Device | Requirement |
| --- | --- |
| Mac | macOS 14 or later, awake and connected to your network |
| Android phone/tablet | Android 12 or later |
| iPhone/iPad | iOS/iPadOS 17 or later |
| First connection | Devices on the same local network |

Public downloads are still in preparation. Follow [Development](DEVELOPMENT.md) to build the Mac host and your chosen client. Platform minimums describe the code targets; they do not mean every supported device has been tested.

## 1. Open the Mac host

Run the built `Tetherly.app`. It lives in the Mac's menu bar, so look there for its controls.

For the default development build, from the repository root:

```sh
open apps/macos/build/DerivedData/Build/Products/Debug/Tetherly.app
```

If the app is already running from another location, quit that copy before opening your new build. Using one app location makes permission setup easier to follow.

## 2. Grant the permissions

The Mac app's **Finish setup** section links to the relevant settings.

| Permission | Why Tetherly needs it |
| --- | --- |
| Screen Recording | Capture the Mac desktop and Mac audio |
| Accessibility | Move the pointer, click, scroll, and send keyboard input |
| Local Network, when requested | Discover and connect to nearby devices |
| Incoming network connections | Let a client reach the Mac host through its firewall |

macOS may label capture permission **Screen & System Audio Recording**. Reopen Tetherly if macOS asks you to. On iPhone/iPad, allow Local Network access; scanning a pairing QR code also needs camera access.

## 3. Pair your devices

1. Put the Mac and client on the same local network. Ethernet on the Mac is fine if it reaches the same network.
2. Turn on **Allow connections** in the Mac menu bar app.
3. Choose **Pair New Device** to display a QR code.
4. Open the client and scan the code, or choose the Mac under Nearby and start pairing.
5. Compare the short codes on both screens. Confirm the match on the client and approve on the Mac.

If the codes differ, cancel. A QR scan does not replace this comparison and approval.

## 4. Make it familiar

Connect to the paired Mac. Try one action at a time: view the desktop, move the pointer, click, then type into a disposable note. The client offers direct-touch and trackpad modes; use whichever fits your screen.

Clipboard send/get, file transfer, and Mac audio are explicit client controls. Their implementation is present, but broader device acceptance is still pending. Check the [acceptance record](ACCEPTANCE.md) for the feature and platform you are trying.

## 5. Connect again

Choose the Mac from the client's paired devices and select **Connect**. Leave the Mac awake, online, running Tetherly, and allowing connections. You do not need to pair again for every session.

For access from another network, continue with [Tailscale setup](CONNECTIONS.md#connect-with-tailscale). Tetherly does not wake a sleeping Mac remotely.

## If something goes wrong

Start with [Troubleshooting](TROUBLESHOOTING.md). A missing Mac usually points to discovery or network reachability. A visible desktop with no input usually points to Accessibility permission. An identity warning needs deliberate re-pairing rather than accepting a changed key.
