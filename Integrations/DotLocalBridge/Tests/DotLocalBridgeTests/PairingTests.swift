import XCTest
@testable import DotLocalBridge

final class PairingTests: XCTestCase {
    func testValidSyntheticConfigurationAndMalformedOrUnsafePairingRejected() throws {
        let valid: [String: Any] = ["version":1,"endpoint":"https://192.168.0.35:8778","bridgeID":"fixture","certificateSHA256":String(repeating:"a",count:64),"bearer":String(repeating:"x",count:40),"deviceLabel":"synthetic phone"]
        let decoded = try JSONDecoder().decode(RelayPairing.self,from:JSONSerialization.data(withJSONObject:valid))
        XCTAssertNoThrow(try decoded.validate())
        for bad in [["version":2],["endpoint":"http://192.168.0.35:8778"],["endpoint":"https://public.invalid"],["bridgeID":"../escape"],["bearer":"short"],["certificateSHA256":"bad"]] as [[String:Any]] {
            let object = valid.merging(bad) { _,new in new }
            let value = try JSONDecoder().decode(RelayPairing.self,from:JSONSerialization.data(withJSONObject:object))
            XCTAssertThrowsError(try value.validate())
        }
    }
}
