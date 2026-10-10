# Wi-Fi and Tailscale connections

[Documentation home](README.md) · [Getting started](GETTING_STARTED.md) · [Troubleshooting](TROUBLESHOOTING.md)

Tetherly uses the same paired device identities on either route. Choose local Wi-Fi when both devices are nearby. Add Tailscale when they need to reach each other across networks.

| Route | What you need | Account |
| --- | --- | --- |
| Local network | Mac and client on a network that permits communication between devices | No Tetherly or Tailscale account |
| Tailscale | Tailscale installed and connected on both devices; Mac remains online | A Tailscale account; no Tetherly account |

## Connect on your local network

1. Join the same home network. A Mac connected by Ethernet can work with a client on Wi-Fi.
2. Open Tetherly on the Mac and turn on **Allow connections**.
3. Choose **Pair New Device**.
4. Scan its QR code in the client, or choose the Mac under Nearby and select Pair.
5. Compare and confirm the short codes, then approve the device on the Mac.
6. Reconnect from the paired-device list for later sessions.

A local session does not require internet connectivity. Guest Wi-Fi and some managed networks isolate devices; use a network you control if discovery or connections fail.

### Pair with an address

Enter an address shown by the Mac app if local discovery is unavailable. For a new device, enable **Pair New Device** on the Mac before starting Pair in the client. The code comparison and Mac approval are still required.

The Mac listens on TCP port `47800`. Addresses are routes to a host, not proof of its identity: Tetherly still checks its stored certificate pin.

## Connect with Tailscale

This is the supported source flow. Physical acceptance over cellular remains pending in the [acceptance record](ACCEPTANCE.md).

1. Install Tailscale on the Mac and phone/tablet using its [official downloads](https://tailscale.com/download).
2. Sign in on both devices using the same Tailscale account. Follow the [official quickstart](https://tailscale.com/docs/how-to/quickstart), including the client's VPN permission prompts.
3. Confirm that both devices appear online in the same private Tailscale network, called a tailnet.
4. While Tailscale is connected, pair in Tetherly using the local steps above. If already paired, connect once with Tailscale enabled so the client can learn the Mac's Tailscale route.
5. Keep the Mac awake, online, running Tetherly, and allowing connections. Switch the client to mobile data or another Wi-Fi network, keep Tailscale connected, and select Connect for your paired Mac.

No router port forwarding or exit node is needed for this device-to-device route. On a managed tailnet, its access policy must allow the client to reach the Mac on TCP `47800`.

### If the Mac is not discovered

Local Bonjour discovery is not a requirement for remote access. Copy the Mac's Tailscale IPv4 address from Tailscale and enter it in the client's address field. These addresses begin with `100.`. You can also use a reachable MagicDNS name when configured in your tailnet.

For new pairing, open pairing on the Mac first. For an existing pair, use Connect. Continue to compare codes for new pairs, even when Tailscale is providing the network route.

### Understand remote performance

Tailscale prefers direct connections and can use encrypted relays when a direct path is unavailable. A relay can add delay. Its [connection types guide](https://tailscale.com/docs/reference/connection-types) explains how these paths work. Tetherly's own TLS identity checks still apply on either path.

## Disconnect and revoke access

Disconnect from the client to end a session. Turn off Allow connections on the Mac to stop accepting sessions. Revoke a device from the Mac's paired-device controls when it should no longer have access.

If the Mac's identity changes, forget its old pairing on the client and remove the corresponding device on the Mac before starting a new pair. Do this only after confirming that you are connecting to your own Mac.

## Connection checklist

- Mac awake, online, and Tetherly running.
- Required permissions granted and hosting enabled.
- Both devices reachable on the chosen network.
- For Tailscale, both devices online in the intended tailnet.
- Pairing completed with matching codes and approval on the Mac.

If one of these is unclear, use the symptom-based [troubleshooting guide](TROUBLESHOOTING.md).
