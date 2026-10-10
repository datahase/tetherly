import XCTest

final class ClientTests: XCTestCase {
    func testAnnexBToAVCCHandlesBothStartCodeLengths() {
        let annexB = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB, 0xCC, 0, 0, 0, 1, 0x65])
        XCTAssertEqual(AnnexB.toAVCC(annexB), Data([0, 0, 0, 2, 0x67, 0xAA, 0, 0, 0, 3, 0x68, 0xBB, 0xCC, 0, 0, 0, 1, 0x65]))
        XCTAssertEqual(AnnexB.toAVCC(Data([1, 2, 3])), Data(), "no start code, nothing to decode")
    }

    func testCoreIsSharedWithTheMac() {
        XCTAssertEqual(HostAddress.parse("192.0.2.10")?.port, HostAddress.defaultPort)
        XCTAssertTrue(isTailscaleHost("100.101.102.103"))
    }

}
