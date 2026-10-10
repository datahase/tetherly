import CoreImage
import SwiftUI

/// Brand tokens (sampled from the logo). Orange is the only accent; state colors stay semantic.
enum Brand {
    static let orange = Color(red: 0xFD / 255, green: 0x6B / 255, blue: 0x0B / 255)
    /// Ink on orange is about 6:1; white on this orange fails WCAG AA for body text.
    static let ink = Color(red: 0x1C / 255, green: 0x18 / 255, blue: 0x14 / 255)
}

struct MenuView: View {
    let permissions: Permissions
    let host: HostModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(permissions: permissions, host: host)
            if !permissions.allGranted { SetupCard(permissions: permissions) }
            if let error = host.startupError { Notice(text: error, systemImage: "exclamationmark.triangle.fill", tint: .red) }
            ConnectionCard(host: host)
            PairingSection(host: host)
            DevicesSection(host: host)
            ReleaseNotesView()
            Footer(host: host)
        }
        .padding(16)
        .frame(width: 380)
        .tint(Brand.orange)
        .onAppear { permissions.refresh() }
    }
}

// MARK: - Header

private struct Header: View {
    let permissions: Permissions
    let host: HostModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
            Text("Tetherly").font(.title3.weight(.semibold))
            Spacer()
            StatusCapsule(text: status.text, color: status.color)
        }
    }

    private var status: (text: String, color: Color) {
        let s = host.snapshot
        if !permissions.allGranted { return ("Needs setup", .orange) }
        if s.sessionDevice != nil { return ("Connected", .green) }
        if s.pairingUntil != nil { return ("Pairing", Brand.orange) }
        return s.hosting ? ("Ready", .secondary) : ("Off", .secondary)
    }
}

private struct StatusCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Status: \(text)")
    }
}

// MARK: - Setup (only while a permission is missing)

private struct SetupCard: View {
    let permissions: Permissions

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Finish setup").font(.headline)
                ForEach(Permissions.Kind.allCases) { kind in
                    let granted = permissions.granted[kind] == true
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: granted ? "checkmark.circle.fill" : icon(kind))
                            .foregroundStyle(granted ? .green : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.callout.weight(.medium))
                            Text(granted ? "Granted" : kind.purpose).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if !granted {
                            Button("Open Settings") { permissions.request(kind) }.controlSize(.small)
                                .help(kind.missingHelp)
                        }
                    }
                }
                if permissions.granted[.screenRecording] != true {
                    HStack {
                        Text("Screen Recording applies after a relaunch.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch") { permissions.relaunch() }.controlSize(.small)
                    }
                }
                if let error = permissions.relaunchError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func icon(_ kind: Permissions.Kind) -> String {
        kind == .screenRecording ? "rectangle.dashed.badge.record" : "hand.point.up.left"
    }
}

// MARK: - Connection

private struct ConnectionCard: View {
    let host: HostModel

    var body: some View {
        let s = host.snapshot
        Card {
            VStack(alignment: .leading, spacing: 12) {
                if let device = s.sessionDevice {
                    HStack(spacing: 10) {
                        DeviceGlyph(active: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device).font(.headline).lineLimit(1)
                            Text(sessionDetail(s)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Button { host.sendFile() } label: { Label("Send File", systemImage: "arrow.up.doc") }
                        Button { host.disconnect() } label: { Label("Disconnect", systemImage: "xmark.circle") }
                    }
                    .controlSize(.regular)
                    .tint(.primary)
                } else {
                    HStack(spacing: 10) {
                        DeviceGlyph(active: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No device connected").font(.headline)
                            Text(s.hosting ? "Open Tetherly on your phone to connect." : "Turn on connections to let your phone connect.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }

                Divider()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow connections").font(.callout)
                        if s.hosting {
                            Text(addressLine(s)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(2)
                        }
                    }
                    Spacer()
                    Toggle("Allow connections", isOn: Binding(get: { s.hosting }, set: { host.setHosting($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                ForEach(s.transfers) { t in TransferRow(transfer: t) { host.cancelTransfer(t.id) } }
            }
        }
    }

    private func sessionDetail(_ s: BridgeHost.Snapshot) -> String {
        let since = s.sessionSince.map { "since " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return s.videoActive ? "Viewing your screen, \(since)" : "Connected \(since)"
    }

    private func addressLine(_ s: BridgeHost.Snapshot) -> String {
        guard s.listener.hasPrefix("Listening") else { return s.listener }
        let list = host.addresses.isEmpty ? ["no network"] : host.addresses
        return list.map { "\($0)  port \(BridgeHost.port)" }.joined(separator: "\n")
    }
}

private struct DeviceGlyph: View {
    let active: Bool

    var body: some View {
        Image(systemName: "iphone.gen3")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(active ? Brand.orange : .secondary)
            .frame(width: 36, height: 36)
            .background((active ? Brand.orange : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

private struct TransferRow: View {
    let transfer: BridgeHost.Snapshot.Transfer
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: transfer.incoming ? "arrow.down.circle" : "arrow.up.circle").foregroundStyle(.secondary)
                Text(transfer.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Cancel", action: cancel).controlSize(.small)
            }
            ProgressView(value: transfer.size == 0 ? 1 : Double(transfer.done) / Double(transfer.size))
            Text("\(transfer.state). \(ByteCountFormatter.string(fromByteCount: transfer.done, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: transfer.size, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pairing

private struct PairingSection: View {
    let host: HostModel

    var body: some View {
        let s = host.snapshot
        if !s.hosting {
            EmptyView()
        } else if let until = s.pairingUntil {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Pair a new device").font(.headline)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let left = max(0, Int(until.timeIntervalSinceNow))
                            Text(String(format: "%d:%02d", left / 60, left % 60)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityLabel("\(left) seconds left")
                        }
                    }
                    if let code = s.pairingCode, let device = s.pairingDevice {
                        Text("Check that \(device) shows this code.").font(.callout).foregroundStyle(.secondary)
                        CodeView(code: code)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            if let qr = QRCode.image(host.pairingLink) {
                                Image(nsImage: qr).interpolation(.none).resizable()
                                    .frame(width: 132, height: 132)
                                    .padding(8)
                                    .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel("Pairing QR code")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Scan with Tetherly on your phone.").font(.callout)
                                Text("Or pick this Mac under Nearby and tap Pair. You will compare a code on both screens.")
                                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button("Stop Pairing") { host.stopPairing() }.controlSize(.small)
                }
            }
        } else {
            Button { host.startPairing() } label: {
                Label("Pair New Device", systemImage: "qrcode").frame(maxWidth: .infinity).foregroundStyle(Brand.ink)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct CodeView: View {
    let code: [Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, n in
                Text(String(n))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Brand.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
    }
}


private struct DevicesSection: View {
    let host: HostModel

    var body: some View {
        let devices = host.snapshot.devices
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paired devices").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(devices) { d in
                    HStack(spacing: 10) {
                        Image(systemName: "iphone.gen3").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name).font(.callout).lineLimit(1)
                            Text("Paired \(d.pairedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revoke") { host.revoke(d) }.controlSize(.small).tint(.primary).help("Disconnect and forget \(d.name)")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Footer and shared pieces

private struct Footer: View {
    let host: HostModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(host.snapshot.lastEvent ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q").controlSize(.small).tint(.primary)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Notice: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }
}

enum QRCode {
    static func image(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

private struct ReleaseNotesView: View {
    private let releaseNotesText = "- Initial public release.\n- Pair your phone with your Mac and control its desktop.\n- Transfer files and clipboard content between paired devices." // RELEASE_NOTES_TEXT
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown" }
    var body: some View {
        DisclosureGroup("Version \(version) (\(build)) · Changelog") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Initial public release").font(.callout.weight(.medium))
                Text(releaseNotesText)
                    .font(.caption).foregroundStyle(.secondary)
                Link("Full changelog", destination: URL(string: "https://www.tetherly.link/changelog")!)
            }.padding(.top, 6)
        }.font(.caption)
    }
}
