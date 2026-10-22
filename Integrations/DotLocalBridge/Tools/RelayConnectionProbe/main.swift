import Foundation
import DotLocalBridge

// Approved Mac-local probe. Secrets stay in private storage/in memory; never printed.
let root = FileManager.default.homeDirectoryForCurrentUser.appending(path:"Library/Application Support/CalendarTaskApp/DotLocalRelay")
do {
    let data = try Data(contentsOf:root.appending(path:"auth/device-staging/DotLocalRelay/pairing-inbox.json"))
    let pairing = try JSONDecoder().decode(RelayPairing.self,from:data)
    let transport = try pairing.transport()
    let feed = try await transport.fetch()
    guard feed.bridgeID == pairing.bridgeID else { throw LocalBridgeError.wrongBridge }
    print("Pinned TLS authenticated feed read succeeded; task count: \(feed.tasks.count). No credentials disclosed.")
    var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
    object["certificateSHA256"] = String(repeating:"0",count:64)
    let wrong = try JSONDecoder().decode(RelayPairing.self,from:JSONSerialization.data(withJSONObject:object))
    var rejected = false
    do { _ = try await wrong.transport().fetch() } catch { rejected = true }
    guard rejected else { throw RelayPairingError.invalid }
    print("Mismatched certificate pin rejected before application data access.")
} catch {
    print("Relay TLS/authentication probe failed; credentials withheld.")
    exit(1)
}
