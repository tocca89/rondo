import CryptoKit
import Foundation
// Creates the Ed25519 key that signs Rondo updates (once per maintainer).
// The private key is stored in the login Keychain; the public key is printed so it can go into Updater.swift.
// Usage: swift Scripts/update_keygen.swift

let service = "Rondo update signing key"

@discardableResult
func security(_ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try! p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

let existing = security(["find-generic-password", "-s", service, "-w"])
let key: Curve25519.Signing.PrivateKey
if existing.status == 0, let raw = Data(base64Encoded: existing.out),
   let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
    print("A signing key already exists in the Keychain; reusing it.")
    key = k
} else {
    key = Curve25519.Signing.PrivateKey()
    let r = security(["add-generic-password", "-s", service, "-a", "ed25519", "-l", service,
                      "-w", key.rawRepresentation.base64EncodedString()])
    guard r.status == 0 else { print("Could not store the key in the Keychain"); exit(1) }
    print("New signing key created and stored in the Keychain (\(service)).")
}
print("PUBLIC_KEY=\(key.publicKey.rawRepresentation.base64EncodedString())")
