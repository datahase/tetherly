import Network
import XCTest

/// Peer termination over real loopback TCP (TLS disabled here; framing and lifecycle are the subject).
final class PeerTests: XCTestCase, @unchecked Sendable { // state is touched only on `queue` or after waits
    private let queue = DispatchQueue(label: "peer-tests")
    private var listener: NWListener!
    private var peer: Peer?
    private var frames = 0
    private var closes = 0
    private var closeError: ProtocolError?
    private var closed: XCTestExpectation!
    private var onFrame: ((Peer, Frame) -> Void)?

    override func setUp() {
        closed = expectation(description: "closed")
        listener = try! NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [unowned self] c in
            let p = Peer(c, queue: queue, requireTLS: false)
            peer = p
            p.onFrame = { [unowned self] p, f in frames += 1; onFrame?(p, f) }
            p.onClose = { [unowned self] _, e in closes += 1; closeError = e; closed.fulfill() }
            p.start()
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
    }

    override func tearDown() { listener.cancel() }

    private func client() -> NWConnection {
        let c = NWConnection(host: "127.0.0.1", port: listener.port!, using: .tcp)
        let ready = expectation(description: "client ready")
        c.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        c.start(queue: DispatchQueue(label: "client"))
        wait(for: [ready], timeout: 5)
        return c
    }

    private func ping() -> Data { Frame.encode(json: ["type": "ping", "n": 1]) }

    func testTruncatedHeaderClosesOnce() {
        let c = client()
        c.send(content: Data([0, 0, 0]), contentContext: .finalMessage, isComplete: true, completion: .idempotent)
        wait(for: [closed], timeout: 5)
        queue.sync { XCTAssertEqual(frames, 0); XCTAssertEqual(closes, 1); XCTAssertTrue(peer!.terminated) }
        c.cancel()
    }

    func testTruncatedPayloadClosesOnce() {
        let c = client()
        let full = ping()
        c.send(content: full.prefix(full.count - 3), contentContext: .finalMessage, isComplete: true, completion: .idempotent)
        wait(for: [closed], timeout: 5)
        queue.sync { XCTAssertEqual(frames, 0); XCTAssertEqual(closes, 1) }
        c.cancel()
    }

    func testOversizedFrameIsRejectedWithError() {
        let c = client()
        let got = expectation(description: "error frame")
        c.receive(minimumIncompleteLength: 5, maximumLength: 65_536) { data, _, _, _ in
            if let data, let f = try? Frame.decode(data, kind: .control, receiver: .client), case .json(let m) = f {
                XCTAssertEqual(m["code"] as? String, "frame_too_large")
                got.fulfill()
            }
        }
        c.send(content: Data(hex: "0001000101")!, completion: .idempotent)
        wait(for: [closed, got], timeout: 5)
        queue.sync { XCTAssertEqual(closeError?.code, "frame_too_large"); XCTAssertEqual(frames, 0) }
        c.cancel()
    }

    func testCloseInsideFrameCallbackStopsDelivery() {
        onFrame = { p, _ in p.close() }
        let c = client()
        c.send(content: ping() + ping() + ping(), completion: .idempotent)
        wait(for: [closed], timeout: 5)
        queue.sync { XCTAssertEqual(frames, 1); XCTAssertEqual(closes, 1) }
        c.cancel()
    }

    /// The client never reads, so sends stall; close(error) must still cancel within the flush deadline.
    func testStalledPeerIsCancelledWithinDeadline() {
        let c = client()
        let started = expectation(description: "peer ready")
        queue.async { [unowned self] in
            func check() { if peer != nil { started.fulfill() } else { queue.asyncAfter(deadline: .now() + 0.05, execute: check) } }
            check()
        }
        wait(for: [started], timeout: 5)
        queue.sync {
            let chunk = Data(count: 1 << 20)
            for _ in 0..<64 { peer!.send(chunk) }
            XCTAssertGreaterThan(peer!.pendingSends, 0)
            peer!.close(ProtocolError(code: "timeout"))
        }
        wait(for: [closed], timeout: 1)
        let cancelled = expectation(description: "cancelled")
        func poll() {
            if case .cancelled = peer!.connection.state { cancelled.fulfill() } else { queue.asyncAfter(deadline: .now() + 0.1, execute: poll) }
        }
        queue.async(execute: poll)
        wait(for: [cancelled], timeout: Peer.flushDeadline + 2)
        c.cancel()
    }
}
