import SwiftUI

@main
struct TetherlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SessionModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(Brand.primary)
                .onOpenURL { url in
                    // Links can come from any app or web page, so they only propose a pairing; the user confirms it.
                    if let link = PairLink.parse(url.absoluteString) { model.pendingLink = link } else { model.notice = "That isn't a valid Tetherly pairing code." }
                }
        }
    }
}

struct RootView: View {
    let model: SessionModel

    var body: some View {
        Group {
            switch model.state {
            case .pairing(let host, let code, let confirmed, let approved):
                PairingView(model: model, host: host, code: code, confirmed: confirmed, macApproved: approved)
                    #if DEBUG
                    .task(id: code) { if code != nil, !confirmed, model.autoConfirm { model.engine?.confirmPairing() } }
                    #endif
            case .connected, .reconnecting:
                SessionView(model: model)
            case .connecting(let label, let pairing):
                ConnectingView(model: model, label: label, pairing: pairing)
            default:
                HomeView(model: model)
            }
        }
        .sheet(item: Binding(get: { model.pendingLink.map(LinkBox.init) }, set: { model.pendingLink = $0?.link })) { box in
            PairLinkSheet(link: box.link, onPair: { model.pendingLink = nil; model.pair(with: box.link) }, onCancel: { model.pendingLink = nil })
                .presentationDetents([.medium, .large])
        }
    }
}

struct LinkBox: Identifiable {
    let link: PairLink
    var id: String { link.pin.hex }
}
