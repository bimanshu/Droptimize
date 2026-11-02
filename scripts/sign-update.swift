#!/usr/bin/env swift
// Signs Droptimize updates for the built-in updater, which checks them with the public key in
// Store/UpdateFeed.swift (`Update.publicKey`) before installing (App/UpdateInstaller.swift).
// Ed25519 via CryptoKit, so it runs on any Mac with Xcode; CI runs it on its macOS runner.
//
//   swift scripts/sign-update.swift generate <private-key-file>
//       Once only: makes the key pair. Writes the private key (base64 of the 32-byte Ed25519 seed)
//       to the file, readable only by you, and prints the public key for `Update.publicKey`.
//       The private key goes into GitHub as the UPDATE_SIGNING_KEY secret, never into the repo.
//   swift scripts/sign-update.swift public-key
//       Prints the public key of $UPDATE_SIGNING_KEY (CI checks it matches the app's).
//   swift scripts/sign-update.swift feed <zip> --version 1.0.0 --build 57 --url <zip's URL>
//                                     [--notes-file <file>] [--minimum-system 14.0]
//       Signs <zip> with $UPDATE_SIGNING_KEY and prints update.json.
//   swift scripts/sign-update.swift self-test <zip>
//       Signs <zip> with a throwaway key and checks the signature and the feed (every CI run, so
//       the first release doesn't find it broken).
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign-update: \(message)\n".utf8))
    exit(1)
}

func privateKeyFromEnvironment() -> Curve25519.Signing.PrivateKey {
    guard let text = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"], !text.isEmpty else {
        fail("UPDATE_SIGNING_KEY isn't set. Add it in GitHub: Settings → Secrets and variables → Actions.")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: trimmed), seed.count == 32,
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    else { fail("UPDATE_SIGNING_KEY isn't a base64 Ed25519 private key (32 bytes).") }
    return key
}

func read(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    return data
}

/// The fields `UpdateFeed` reads (Store/UpdateFeed.swift); keep the two in step.
func feedJSON(zip: Data, key: Curve25519.Signing.PrivateKey, version: String, build: Int, url: String,
              notes: String, minimumSystem: String) -> Data {
    guard let signature = try? key.signature(for: zip) else { fail("couldn't sign") }
    let feed: [String: Any] = [
        "version": version,
        "build": build,
        "url": url,
        "signature": signature.base64EncodedString(),
        "notes": notes,
        "minimumSystemVersion": minimumSystem,
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: feed,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    else { fail("couldn't write the feed") }
    return json + Data("\n".utf8)
}

/// `--name value` pairs after the positional arguments.
func options(_ arguments: ArraySlice<String>) -> [String: String] {
    var result: [String: String] = [:]
    var rest = arguments
    while let name = rest.popFirst() {
        guard name.hasPrefix("--"), let value = rest.popFirst() else { fail("expected --name value, got \(name)") }
        result[String(name.dropFirst(2))] = value
    }
    return result
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "generate":
    guard arguments.count == 2, let path = arguments.last else { fail("usage: generate <private-key-file>") }
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) already exists; not overwriting a key.") }
    let key = Curve25519.Signing.PrivateKey()
    let text = Data((key.rawRepresentation.base64EncodedString() + "\n").utf8)
    guard FileManager.default.createFile(atPath: path, contents: text, attributes: [.posixPermissions: 0o600]) else {
        fail("can't write \(path)")
    }
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "public-key":
    print(privateKeyFromEnvironment().publicKey.rawRepresentation.base64EncodedString())

case "feed":
    guard arguments.count >= 2 else { fail("usage: feed <zip> --version … --build … --url …") }
    let zip = read(arguments[arguments.startIndex + 1])
    let given = options(arguments.dropFirst(2))
    guard let version = given["version"], version.range(of: #"^[0-9]+\.[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil
    else { fail("--version must look like 1.0 or 1.0.1") }
    guard let build = given["build"].flatMap({ Int($0) }), build > 0 else { fail("--build must be a positive number") }
    guard let url = given["url"], url.hasPrefix("https://") else { fail("--url must be an https link to the zip") }
    let notes = given["notes-file"].map { String(decoding: read($0), as: UTF8.self) } ?? ""
    let json = feedJSON(zip: zip, key: privateKeyFromEnvironment(), version: version, build: build, url: url,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        minimumSystem: given["minimum-system"] ?? "14.0")
    FileHandle.standardOutput.write(json)

case "self-test":
    guard arguments.count == 2, let path = arguments.last else { fail("usage: self-test <zip>") }
    let zip = read(path)
    let key = Curve25519.Signing.PrivateKey()
    let json = feedJSON(zip: zip, key: key, version: "1.2.3", build: 42, url: "https://example.com/Droptimize-42.zip",
                        notes: "Faster \"GIFs\" & more", minimumSystem: "14.0")
    guard let feed = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
          Set(feed.keys) == ["version", "build", "url", "signature", "notes", "minimumSystemVersion"],
          feed["build"] as? Int == 42, feed["notes"] as? String == "Faster \"GIFs\" & more",
          let signature = (feed["signature"] as? String).flatMap({ Data(base64Encoded: $0) })
    else { fail("self-test: the feed doesn't read back") }
    guard key.publicKey.isValidSignature(signature, for: zip) else { fail("self-test: the signature doesn't verify") }
    var tampered = zip
    tampered[tampered.startIndex] ^= 0x01
    guard !key.publicKey.isValidSignature(signature, for: tampered) else { fail("self-test: a changed zip still verifies") }
    print("sign-update: self-test passed (\(zip.count) bytes signed and verified)")

default:
    fail("usage: generate <file> | public-key | feed <zip> … | self-test <zip>  (see the top of this file)")
}
