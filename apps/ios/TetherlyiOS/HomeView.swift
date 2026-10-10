import AVFoundation
import SwiftUI

struct HomeView: View {
    let model: SessionModel
    @State private var moreOpen = false
    @State private var scanning = false
    @State private var cameraRequest: Task<Void, Never>?
    @State private var requestingCamera = false

    private var connecting: Bool { if case .connecting = model.state { true } else { false } }
    private var busy: Bool { connecting || requestingCamera }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusCard(model: model)
                    if let primary = model.macs.first {
                        MacHero(model: model, mac: primary)
                        if model.macs.count > 1 {
                            Section(title: "Other Macs") {
                                ForEach(model.macs.dropFirst()) { mac in
                                    MacRow(icon: "laptopcomputer", title: mac.hostName, subtitle: reachLabel(mac), mono: model.discovery.reach(of: mac) == .offline,
                                           action: "Connect", enabled: !busy) { model.connect(mac) } menu: {
                                        Button("Forget this Mac", role: .destructive) { model.forget(mac) }
                                    }
                                }
                            }
                        }
                        Button { scan() } label: { Label("Pair another Mac", systemImage: "qrcode.viewfinder") }
                            .buttonStyle(SecondaryButtonStyle()).disabled(busy)
                    } else {
                        WelcomeCard(busy: busy, onScan: scan)
                    }
                    OtherWays(model: model, open: $moreOpen, busy: busy)
                    ReleaseNotesView()
                    Text(model.discovery.tailscaleOn ? "Tailscale is on. Pull down to search again." : "Pull down to search again.")
                        .font(.caption).foregroundStyle(Brand.onSurfaceVariant).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .refreshable { await model.refresh() }
            .background(Brand.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        BrandMark(size: 30)
                        Text("Tetherly").font(.headline)
                    }
                }
            }
            .toolbarBackground(Brand.background, for: .navigationBar)
        }
        .sheet(isPresented: $scanning) {
            ScanSheet(onCode: { code in
                scanning = false
                if let link = PairLink.parse(code) { model.pair(with: link) } else { model.notice = "That isn't a valid Tetherly pairing code." }
            }, onError: { message in
                scanning = false
                model.notice = message
            })
        }
        .onDisappear { cameraRequest?.cancel() }
    }

    private func scan() {
        guard !busy else { return }
        guard QRScanner.supported else {
            model.notice = "The camera scanner isn't available on this device. Pair by address instead."
            return
        }
        requestingCamera = true
        cameraRequest = Task { @MainActor in
            defer { requestingCamera = false }
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard !Task.isCancelled, !connecting else { return }
            guard authorized else {
                model.notice = "Allow camera access for Tetherly in Settings to scan a QR code, or pair by address."
                return
            }
            guard QRScanner.available else {
                model.notice = "The camera scanner is unavailable right now. Pair by address instead."
                return
            }
            scanning = true
        }
    }

    private func reachLabel(_ mac: PairedMac) -> String {
        switch model.discovery.reach(of: mac) {
        case .wifi: "Available on Wi-Fi"
        case .tailscale: "Available via Tailscale"
        case .offline: "Not reachable. Last seen at \(mac.address)"
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.onSurfaceVariant)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusCard: View {
    let model: SessionModel
    var body: some View {
        switch model.state {
        case .failed(let message):
            ErrorCard(text: message, dismiss: nil)
        default:
            if let n = model.notice { ErrorCard(text: n) { model.notice = nil } }
        }
    }
}

private struct ErrorCard: View {
    let text: String
    let dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle")
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss { Button("Dismiss", action: dismiss).font(.subheadline.weight(.semibold)) }
        }
        .foregroundStyle(Brand.onErrorContainer)
        .padding(16).background(Brand.errorContainer, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// The main paired Mac, with the one action people come here for.
private struct MacHero: View {
    let model: SessionModel
    let mac: PairedMac

    var body: some View {
        let reach = model.discovery.reach(of: mac)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "laptopcomputer").font(.system(size: 26)).foregroundStyle(Brand.onPrimaryContainer)
                    .frame(width: 56, height: 56).background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(mac.hostName).font(.title3.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        // A real state indicator: green only when the Mac answers on some route right now.
                        Circle().fill(reach == .offline ? Brand.outline : Brand.available).frame(width: 8, height: 8)
                        Image(systemName: reach == .tailscale ? "lock.shield" : "wifi").font(.caption).foregroundStyle(Brand.onSurfaceVariant)
                        Text(label(reach)).font(.subheadline).foregroundStyle(Brand.onSurfaceVariant).lineLimit(1)
                    }
                }
                Spacer()
                Menu {
                    Button("Forget this Mac", role: .destructive) { model.forget(mac) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("More options for \(mac.hostName)")
            }
            Button("Connect") { model.connect(mac) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled({ if case .connecting = model.state { true } else { false } }())
        }
        .padding(20)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func label(_ r: Discovery.Reach) -> String {
        switch r {
        case .wifi: "Available on Wi-Fi"
        case .tailscale: "Available via Tailscale"
        case .offline: "Last seen at \(mac.address)"
        }
    }
}

/// First run: what to do on the Mac, then one clear action here.
private struct WelcomeCard: View {
    let busy: Bool
    let onScan: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandMark(size: 52)
            Text("Control your Mac from this device").font(.title2.weight(.semibold))
            ForEach([("laptopcomputer", "Open Tetherly on your Mac"), ("qrcode", "Click Pair New Device"),
                     ("qrcode.viewfinder", "Scan the code and compare the numbers")], id: \.1) { icon, text in
                Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Brand.primary) }
            }
            Button { onScan() } label: { Label("Scan QR to pair", systemImage: "qrcode.viewfinder") }
                .buttonStyle(PrimaryButtonStyle()).disabled(busy)
        }
        .padding(20)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct MacRow<MenuContent: View>: View {
    let icon: String, title: String, subtitle: String
    var mono = false
    let action: String
    var enabled = true
    let onAction: () -> Void
    @ViewBuilder let menu: MenuContent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.onPrimaryContainer)
                .frame(width: 44, height: 44).background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(mono ? .caption.monospaced() : .caption).foregroundStyle(Brand.onSurfaceVariant).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action, action: onAction).buttonStyle(SecondaryButtonStyle(tonal: true)).frame(width: 96).disabled(!enabled)
            Menu { menu } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }
                .accessibilityLabel("More options for \(title)")
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct OtherWays: View {
    let model: SessionModel
    @Binding var open: Bool
    let busy: Bool
    @State private var address = ""
    @State private var error: String?

    private var nearby: [String] { model.discovery.nearby.filter { name in !model.macs.contains { $0.hostName == name } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other ways to connect").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.onSurface)
                        Text(nearby.isEmpty ? "Enter an address or a Tailscale name" : "\(nearby.count) nearby, or enter an address")
                            .font(.caption).foregroundStyle(Brand.onSurfaceVariant)
                    }
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(Brand.onSurfaceVariant)
                }
                .padding(16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 14) {
                    if let f = model.discovery.failed {
                        Text(f).font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
                    } else if model.discovery.nearby.isEmpty {
                        Text("Looking for Macs on this Wi-Fi").font(.subheadline).foregroundStyle(Brand.onSurfaceVariant)
                        ProgressView().progressViewStyle(.linear).tint(Brand.primary)
                    }
                    ForEach(nearby, id: \.self) { name in
                        MacRow(icon: "network", title: name, subtitle: "On this network", action: "Pair", enabled: !busy) {
                            model.connectNearby(name, pair: true)
                        } menu: {
                            Button("Connect without pairing") { model.connectNearby(name, pair: false) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mac address").font(.caption.weight(.medium)).foregroundStyle(Brand.onSurfaceVariant)
                        TextField("192.168.1.20", text: $address)
                            .font(.body.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .submitLabel(.go).onSubmit { go(pair: false) }
                            .padding(14)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error == nil ? Brand.outline : Brand.error, lineWidth: 1))
                            .onChange(of: address) { error = nil }
                        Text(error ?? "Works on Wi-Fi and over Tailscale.").font(.caption).foregroundStyle(error == nil ? Brand.onSurfaceVariant : Brand.error)
                    }
                    // Both actions stay enabled and validate on press, so the form never shows dead grey buttons.
                    HStack(spacing: 10) {
                        Button { go(pair: false) } label: { Label("Connect", systemImage: "arrow.right").labelStyle(TrailingIcon()) }
                            .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                        Button { go(pair: true) } label: { Label("Pair", systemImage: "link") }
                            .buttonStyle(SecondaryButtonStyle(tonal: true)).disabled(busy)
                    }
                }
                .padding([.horizontal, .bottom], 16)
            }
        }
        .background(Brand.surfaceLow, in: RoundedRectangle(cornerRadius: 16))
    }

    private func go(pair: Bool) {
        guard HostAddress.parse(address) != nil else {
            error = address.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter your Mac's address first." : "Use an IP address, hostname or Tailscale name, optionally with :port."
            return
        }
        model.connect(address: address, pair: pair)
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 8) { configuration.title; configuration.icon } }
}

private struct ScanSheet: View {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            QRScanner(onCode: onCode, onError: onError)
                .ignoresSafeArea()
                .navigationTitle("Scan the code on your Mac")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct PairingView: View {
    let model: SessionModel
    let host: String, code: [Int]?, confirmed: Bool, macApproved: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            BrandMark(size: 56)
            VStack(spacing: 6) {
                Text("Pair with \(host)").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(code == nil ? "Setting up a secure connection" : !confirmed ? "Check that your Mac shows exactly this code."
                     : macApproved ? "Your Mac approved. Finishing." : "Now click Allow on your Mac.")
                    .foregroundStyle(Brand.onSurfaceVariant).multilineTextAlignment(.center)
            }
            if let code {
                HStack(spacing: 10) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, n in
                        Text(String(n)).font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.onPrimaryContainer)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
            } else {
                ProgressView().progressViewStyle(.linear).tint(Brand.primary).frame(maxWidth: 280)
            }
            if code != nil, !confirmed {
                VStack(spacing: 10) {
                    Button("Codes match") { model.engine?.confirmPairing() }.buttonStyle(PrimaryButtonStyle()).frame(maxWidth: 320)
                    Button("Cancel") { model.engine?.cancelPairing() }
                }
                Text("If the codes differ, cancel. Someone may be trying to intercept the connection.")
                    .font(.footnote).foregroundStyle(Brand.onSurfaceVariant).multilineTextAlignment(.center)
            } else {
                Button("Cancel") { model.engine?.cancelPairing() }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
    }
}

/// Confirms a pairing link that arrived from outside the app before anything connects.
struct PairLinkSheet: View {
    let link: PairLink
    let onPair: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BrandMark(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pair with this Mac?").font(.subheadline.weight(.medium)).foregroundStyle(Brand.onSurfaceVariant)
                    Text(link.name.isEmpty ? "Unnamed Mac" : link.name).font(.title2.weight(.semibold)).lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Address").font(.caption.weight(.medium)).foregroundStyle(Brand.onSurfaceVariant)
                ForEach(link.addresses, id: \.self) { Text($0.description).font(.body.monospaced()) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
            Label {
                Text("This link was opened from another app. Continue only if you just scanned it from Tetherly on your own Mac. You will still compare a code on both screens.")
            } icon: { Image(systemName: "shield") }
                .font(.subheadline).foregroundStyle(Brand.onPrimaryContainer)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.primaryContainer, in: RoundedRectangle(cornerRadius: 12))
            Button("Pair", action: onPair).buttonStyle(PrimaryButtonStyle())
            Button("Cancel", action: onCancel).buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
        .background(Brand.surfaceLow)
    }
}

/// Connecting (or starting a pairing) gets one calm full screen: the Mac's name and route rather than its IP, the
/// same ring the session shows while its video starts, and a way out.
struct ConnectingView: View {
    let model: SessionModel
    let label: String
    let pairing: Bool

    private var tailscale: Bool {
        if let mac = model.macs.first(where: { $0.hostName == label }) { return model.discovery.reach(of: mac) == .tailscale }
        return isTailscaleHost(HostAddress.parse(label)?.host ?? label)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LoaderRing(accent: Brand.primary, content: Brand.onSurface)
            Text((pairing ? "Pairing with " : "Connecting to ") + label)
                .font(.title2.weight(.semibold)).foregroundStyle(Brand.onSurface).multilineTextAlignment(.center).lineLimit(2)
                .padding(.top, 28)
            Label(tailscale ? "Over Tailscale" : "Over Wi-Fi", systemImage: tailscale ? "lock.shield" : "wifi")
                .font(.subheadline.weight(.medium)).foregroundStyle(Brand.onSurfaceVariant)
                .padding(.horizontal, 12).padding(.vertical, 6).background(Brand.surfaceHigh, in: Capsule())
                .padding(.top, 12)
            Text(pairing ? "Setting up a secure pairing" : "Securing the connection")
                .font(.subheadline).foregroundStyle(Brand.onSurfaceVariant).padding(.top, 12)
            Spacer()
            Button("Cancel") { model.engine?.disconnect() }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background.ignoresSafeArea())
    }
}

private struct ReleaseNotesView: View {
    private let releaseNotesText = "- Initial public release.\n- Pair your phone with your Mac and control its desktop.\n- Transfer files and clipboard content between paired devices." // RELEASE_NOTES_TEXT
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown" }
    var body: some View {
        DisclosureGroup("Version \(version) (\(build)) · Changelog") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Initial public release").font(.headline)
                Text(releaseNotesText)
                Link("Full changelog", destination: URL(string: "https://www.tetherly.link/changelog")!)
            }.font(.subheadline).padding(.top, 8)
        }.font(.caption).padding(16)
    }
}
