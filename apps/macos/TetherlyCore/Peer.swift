import Foundation
import Network
import Security

/// One accepted connection. All methods and callbacks run on `queue`.
/// Reads are bounded: the 5-byte header is validated (protocol/SPEC.md §2) before the payload is received.
/// Every terminal path (EOF, transport error, malformed input, explicit close) goes through `terminate`, which cancels
/// the NWConnection and reports `onClose` exactly once.
final class Peer: @unchecked Sendable {
    let connection: NWConnection
    let id = UUID()
    var kind: ConnKind = .control // provisional until hello; control limits are the tightest that admit hello
    private(set) var pin: Data?
    private(set) var channelBinding: Data?
    private(set) var pendingSends = 0
    private(set) var terminated = false
    var lastReceived = Date()
    var onFrame: ((Peer, Frame) -> Void)?
    var onReady: ((Peer) -> Void)?
    var onClose: ((Peer, ProtocolError?) -> Void)?
    private let queue: DispatchQueue
    private let requireTLS: Bool
    /// Which end of the connection we are; decides which frame types we may receive (SPEC §2).
    let role: Role
    static let flushDeadline: TimeInterval = 2

    init(_ connection: NWConnection, queue: DispatchQueue, requireTLS: Bool = true, role: Role = .server) {
        self.connection = connection
        self.queue = queue
        self.requireTLS = requireTLS
        self.role = role
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.terminated else { return }
            switch state {
            case .ready:
                if self.requireTLS {
                    self.readTLSMetadata()
                    guard self.pin != nil, self.channelBinding != nil else { return self.terminate(ProtocolError(code: "not_paired")) }
                }
                self.onReady?(self)
                self.readHeader()
            case .failed, .cancelled:
                self.terminate(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readTLSMetadata() {
        guard let tls = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return }
        let meta = tls.securityProtocolMetadata
        var leaf: SecCertificate?
        sec_protocol_metadata_access_peer_certificate_chain(meta) { cert in
            if leaf == nil { leaf = sec_certificate_copy_ref(cert).takeRetainedValue() }
        }
        pin = leaf.flatMap(SPKI.pin(of:))
        let label = "EXPORTER-Channel-Binding"
        channelBinding = label.withCString { ptr in
            sec_protocol_metadata_create_secret(meta, label.utf8.count, ptr, 32).map { Data($0 as DispatchData) }
        }
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: Frame.headerSize, maximumLength: Frame.headerSize) { [weak self] data, _, _, _ in
            guard let self, !self.terminated else { return }
            // Short read means EOF or a transport error mid-header: end the connection.
            guard let data, data.count == Frame.headerSize else { return self.terminate(nil) }
            do {
                let (type, length) = try Frame.header(data, kind: self.kind, receiver: self.role)
                length == 0 ? self.deliver(type, Data()) : self.readPayload(type, length)
            } catch {
                self.terminate(error as? ProtocolError ?? .malformed)
            }
        }
    }

    private func readPayload(_ type: UInt8, _ length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
            guard let self, !self.terminated else { return }
            guard let data, data.count == length else { return self.terminate(nil) }
            self.deliver(type, data)
        }
    }

    private func deliver(_ type: UInt8, _ payload: Data) {
        let frame: Frame
        do { frame = try Frame.payload(type: type, payload) } catch { return terminate(error as? ProtocolError ?? .malformed) }
        lastReceived = Date()
        onFrame?(self, frame)
        if !terminated { readHeader() } // the handler may have closed us
    }

    func send(_ data: Data, completion: (() -> Void)? = nil) {
        guard !terminated else { return }
        pendingSends += 1
        nonisolated(unsafe) let completion = completion // runs on the host queue, like every Peer callback
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.pendingSends -= 1
            if !self.terminated { completion?() }
        })
    }

    func send(json: [String: Any]) { send(Frame.encode(json: json)) }

    func sendError(_ code: String, _ message: String = "") {
        send(json: ["type": "error", "code": code, "message": message])
    }

    /// Closes now. With an error, it is flushed first, bounded by `flushDeadline` so a stalled peer can't hold us.
    func close(_ error: ProtocolError? = nil) { terminate(error) }

    /// Sends `data` as the final message, then closes (same bounded flush as an error).
    func sendAndClose(_ data: Data) { terminate(nil, final: data) }

    private func terminate(_ error: ProtocolError?, final: Data? = nil) {
        guard !terminated else { return }
        terminated = true
        let conn = connection // captured strongly: cancellation must not depend on this Peer staying alive
        let last = final ?? error.map { Frame.encode(json: ["type": "error", "code": $0.code, "message": $0.message]) }
        if let last, conn.state == .ready {
            conn.send(content: last, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
            queue.asyncAfter(deadline: .now() + Self.flushDeadline) { conn.cancel() }
        } else {
            conn.cancel()
        }
        let handler = onClose
        onClose = nil
        onFrame = nil
        onReady = nil
        handler?(self, error)
    }
}
