import CryptoKit
import Foundation
// Signs an update file with the Ed25519 key from the Keychain and writes <file>.sig (base64).
// Usage: swift Scripts/sign_update.swift dist/Rondo-x.y.z.dmg

let service = "Rondo update signing key"
let path = CommandLine.arguments[1]

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
p.arguments = ["find-generic-password", "-s", service, "-w"]
let pipe = Pipe()
p.standardOutput = pipe
p.standardError = FileHandle.nullDevice
try! p.run()
let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
p.waitUntilExit()
guard p.terminationStatus == 0, let raw = Data(base64Encoded: out), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("No signing key in the Keychain. Run: swift Scripts/update_keygen.swift\n".utf8))
    exit(1)
}
let data = try! Data(contentsOf: URL(fileURLWithPath: path))
let sig = try! key.signature(for: data).base64EncodedString()
try! sig.write(toFile: path + ".sig", atomically: true, encoding: .utf8)
print("✓ Signed \(path) → \(path).sig")
