import GameController
import SwiftUI
import UIKit
import VisionKit

/// A connected mouse (GameController) drives the Mac: relative movement, both buttons and the scroll wheel.
@MainActor @Observable
final class MouseBridge {
    private(set) var connected = false
    var enabled = true
    var send: (([String: Any]) -> Void)?

    init() {
        NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { GCMouse.mice().forEach { self?.attach($0) } }
        }
        NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connected = GCMouse.mice().isEmpty == false }
        }
        GCMouse.mice().forEach(attach)
    }

    private func attach(_ mouse: GCMouse) {
        connected = true
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated {
                // GameController reports y up; the Mac's y grows downward.
                guard let self, self.enabled else { return }
                self.send?(["type": "pointer", "dx": Double(dx), "dy": Double(-dy)])
            }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { if self?.enabled == true { self?.send?(["type": "button", "button": "left", "down": pressed]) } }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { if self?.enabled == true { self?.send?(["type": "button", "button": "right", "down": pressed]) } }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                guard let self, self.enabled, x != 0 || y != 0 else { return }
                self.send?(["type": "scroll", "dx": Double(-x) * 8, "dy": Double(y) * 8])
            }
        }
    }
}

/// Live QR scanning with VisionKit. Unavailable on the Simulator and on devices without a camera.
struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    static var supported: Bool { DataScannerViewController.isSupported }
    static var available: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(coordinator: context.coordinator)
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ vc: ScannerController, coordinator: Coordinator) { vc.invalidate() }
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }

    final class ScannerController: UIViewController {
        private let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                        qualityLevel: .balanced, isHighlightingEnabled: true)
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
            scanner.delegate = coordinator
        }

        required init?(coder: NSCoder) { return nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scanner.view)
            NSLayoutConstraint.activate([
                scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
                scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !coordinator.done else { return }
            do { try scanner.startScanning() }
            catch { coordinator.fail() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stop()
        }

        func stop() { scanner.stopScanning() }

        func invalidate() {
            coordinator.done = true
            scanner.delegate = nil
            stop()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        fileprivate var done = false
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func fail() {
            guard !done else { return }
            done = true
            onError("The camera scanner couldn't start. Try again, or pair by address instead.")
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            scanner.stopScanning()
            fail()
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                guard !done, let s = b.payloadStringValue, s.hasPrefix("tetherly://") else { continue }
                done = true
                scanner.stopScanning()
                onCode(s)
            }
        }
    }
}

/// Orientation lock for the session screen (Auto, Landscape, Portrait), applied through the scene.
@MainActor
enum Orientation: String, CaseIterable {
    case auto, landscape, portrait

    static var mask: UIInterfaceOrientationMask = .all


    func apply() {
        Self.mask = switch self {
        case .auto: .all
        case .landscape: .landscape
        case .portrait: .portrait
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: Self.mask)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Orientation.mask }
    }
}
