import XCTest

final class StorageTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mb-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    func testTrustStorePersistsAndReloads() throws {
        let url = dir.appendingPathComponent("devices.json"), pin = Data(repeating: 9, count: 32)
        try TrustStore(url: url).add(pin: pin, name: "Test phone")
        let reloaded = TrustStore(url: url)
        XCTAssertTrue(reloaded.isApproved(pin))
        XCTAssertEqual(reloaded.name(pin), "Test phone")
        try reloaded.remove(pin: pin)
        XCTAssertFalse(TrustStore(url: url).isApproved(pin))
    }

    func testUnwritableStorageFailsClosed() throws {
        let url = dir.appendingPathComponent("devices.json"), pin = Data(repeating: 1, count: 32), other = Data(repeating: 2, count: 32)
        let store = TrustStore(url: url)
        try store.add(pin: other, name: "old")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try store.add(pin: pin, name: "new"))
        XCTAssertFalse(store.isApproved(pin), "a failed write must not approve the device")
        XCTAssertThrowsError(try store.remove(pin: other))
        XCTAssertFalse(store.isApproved(other), "revocation still takes effect in memory")
    }

    func testExclusiveTempRefusesExistingFilesAndSymlinks() throws {
        let victim = dir.appendingPathComponent("victim.txt")
        try Data("keep".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(".tetherly-link.partial"), withDestinationURL: victim)
        XCTAssertNil(FileNames.createExclusiveTemp(in: dir, tag: "link"), "must not follow a planted symlink")
        try Data().write(to: dir.appendingPathComponent(".tetherly-taken.partial"))
        XCTAssertNil(FileNames.createExclusiveTemp(in: dir, tag: "taken"), "must not reuse an existing file")
        XCTAssertEqual(try Data(contentsOf: victim), Data("keep".utf8))
        XCTAssertNotNil(FileNames.createExclusiveTemp(in: dir, tag: "fresh"))
    }

    func testPublishNeverOverwrites() throws {
        let existing = dir.appendingPathComponent("a.txt")
        try Data("original".utf8).write(to: existing)
        let (temp, h) = try XCTUnwrap(FileNames.createExclusiveTemp(in: dir, tag: "t1"))
        try h.write(contentsOf: Data("new".utf8)); try h.close()
        XCTAssertEqual(FileNames.publishExclusive(temp, in: dir, name: "a.txt"), "a (2).txt")
        XCTAssertEqual(try Data(contentsOf: existing), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("a (2).txt")), Data("new".utf8))
    }
}
