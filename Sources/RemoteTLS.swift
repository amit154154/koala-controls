import Foundation
import Security
import CryptoKit

struct RemoteTLS {
    let identity: SecIdentity
    let host: String
    let certificate: Data
    let fingerprint: String
    let profileURL: URL

    static func prepare(in directory: URL) throws -> RemoteTLS {
        guard #available(macOS 15, *) else { throw RemoteFailure.message("Phone remote needs macOS 15 or newer.") }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Use the system Bonjour hostname; the fallback is only for diagnostics.
        let hostname = try run(["/usr/sbin/scutil", "--get", "LocalHostName"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !hostname.isEmpty, hostname.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { throw RemoteFailure.message("Choose a valid local hostname in macOS Sharing settings.") }
        let dns = hostname + ".local"
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let storedHost = directory.appendingPathComponent("hostname")
        let valid = (try? run(["/usr/bin/openssl", "x509", "-checkend", "604800", "-noout", "-in", directory.appendingPathComponent("server.pem").path])) != nil
        if !valid || (try? String(contentsOf: storedHost, encoding: .utf8)) != dns || !fm.fileExists(atPath: directory.appendingPathComponent("identity.p12").path) {
            // Keep one per-install CA, so a hostname change can renew the leaf without reinstalling trust.
            let caKey = directory.appendingPathComponent("ca.key").path
            let caPEM = directory.appendingPathComponent("ca.pem").path
            if !fm.fileExists(atPath: caKey) {
                _ = try run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "3650", "-keyout", caKey, "-out", caPEM, "-subj", "/CN=Koala Remote on \(hostname)/O=Personal Mac Remote", "-config", writeConfig(directory, name: "ca.cnf", text: "[req]\ndistinguished_name=dn\nx509_extensions=ca\n[dn]\n[ca]\nbasicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n")])
            }
            let key = directory.appendingPathComponent("server.key").path
            let csr = directory.appendingPathComponent("server.csr").path
            let cert = directory.appendingPathComponent("server.pem").path
            _ = try run(["/usr/bin/openssl", "req", "-newkey", "rsa:2048", "-nodes", "-sha256", "-keyout", key, "-out", csr, "-subj", "/CN=\(dns)"])
            let ext = try writeConfig(directory, name: "server.cnf", text: "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:\(dns),DNS:localhost,IP:127.0.0.1\n")
            _ = try run(["/usr/bin/openssl", "x509", "-req", "-in", csr, "-CA", caPEM, "-CAkey", caKey, "-CAcreateserial", "-out", cert, "-days", "365", "-sha256", "-extfile", ext])
            let password = RemoteSecret.random()
            let passwordURL = directory.appendingPathComponent("identity-password")
            try Data(password.utf8).write(to: passwordURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordURL.path)
            _ = try run(["/usr/bin/openssl", "pkcs12", "-export", "-out", directory.appendingPathComponent("identity.p12").path, "-inkey", key, "-in", cert, "-certfile", caPEM, "-passout", "file:" + passwordURL.path])
            _ = try run(["/usr/bin/openssl", "x509", "-in", caPEM, "-outform", "DER", "-out", directory.appendingPathComponent("ca.cer").path])
            try dns.write(to: storedHost, atomically: true, encoding: .utf8)
        }
        for f in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path) }
        let password = try String(contentsOf: directory.appendingPathComponent("identity-password"), encoding: .utf8)
        var imported: CFArray?
        let data = try Data(contentsOf: directory.appendingPathComponent("identity.p12"))
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password, kSecImportToMemoryOnly as String: true] as CFDictionary, &imported)
        guard status == errSecSuccess, let first = (imported as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String] else { throw RemoteFailure.message("Could not load the phone remote’s TLS identity (\(status)).") }
        let identity = value as! SecIdentity
        let root = try Data(contentsOf: directory.appendingPathComponent("ca.cer"))
        let fingerprint = SHA256.hash(data: root).map { String(format: "%02X", $0) }.joined(separator: ":")
        let profile: [String: Any] = ["PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "local.minikeyboard.remote.trust.\(hostname)", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Koala Remote · \(hostname)", "PayloadDescription": "Trusts this Mac’s local Koala Remote connection. Install only if you requested it on your own Mac.",
            "PayloadContent": [["PayloadType": "com.apple.security.root", "PayloadVersion": 1,
                "PayloadIdentifier": "local.minikeyboard.remote.ca.\(hostname)", "PayloadUUID": UUID().uuidString,
                "PayloadDisplayName": "Koala Remote on \(hostname)", "PayloadContent": root]]]
        let profileURL = directory.appendingPathComponent("Koala Remote.mobileconfig")
        try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0).write(to: profileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileURL.path)
        return RemoteTLS(identity: identity, host: dns, certificate: root, fingerprint: fingerprint, profileURL: profileURL)
    }
    private static func writeConfig(_ directory: URL, name: String, text: String) throws -> String {
        let u = directory.appendingPathComponent(name); try text.write(to: u, atomically: true, encoding: .utf8); return u.path
    }
    private static func run(_ arguments: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: arguments[0]); p.arguments = Array(arguments.dropFirst())
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw RemoteFailure.message("Could not prepare the local certificate. Check that Apple’s command-line tools are installed.") }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
