import SwiftUI

@main
struct TetherlyApp: App {
    @State private var permissions = Permissions()
    @State private var host = HostModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(permissions: permissions, host: host)
        } label: {
            // Template image: macOS tints it for light/dark menu bars. The triangle flags missing permissions.
            if permissions.allGranted {
                Image("MenuBarIcon").accessibilityLabel(host.snapshot.sessionDevice == nil ? "Tetherly" : "Tetherly, device connected")
            } else {
                Image(systemName: "exclamationmark.triangle").accessibilityLabel("Tetherly needs permissions")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
