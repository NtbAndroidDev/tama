import Foundation
import Security
import CryptoKit

/// The receiver's TLS identity: an EC P-256 key and a self-signed X.509
/// certificate, both made on this Mac with the Security framework and kept in
/// the login keychain as "Tama LocalSend TLS", so the fingerprint other
/// devices remember stays the same between launches.
///
/// macOS offers no public API to hold a `SecIdentity` in memory only before
/// macOS 15, so the key and certificate live in the keychain. The key's
/// access list names Tama; an ad-hoc signed rebuild changes that signature
/// and macOS then asks once before Tama may use the key again.
enum LocalSendTLS {
    static let label = "Tama LocalSend TLS"
    private static let keyTag = Data("app.tama.localsend.tls".utf8)

    struct Identity: @unchecked Sendable {
        let identity: SecIdentity
        /// SHA-256 of the certificate's DER, lowercase hex: LocalSend's fingerprint.
        let fingerprint: String
    }

    enum TLSError: LocalizedError {
        case keychain(OSStatus, String)
        public var errorDescription: String? {
            switch self {
            case let .keychain(status, step):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
                return "Couldn't prepare the encryption certificate (\(step)): \(message)"
            }
        }
    }

    /// The stored identity, or a new one when there's none (or it expired).
    static func loadOrCreate() throws -> Identity {
        if let existing = storedIdentity() { return existing }
        deleteStored()
        return try create()
    }

    /// A self-signed certificate (DER) for an EC P-256 private key.
    static func selfSignedCertificate(for privateKey: SecKey, now: Date = Date()) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let point = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw TLSError.keychain(OSStatus((error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? -1), "public key")
        }
        let tbs = CertificateBuilder.tbsCertificate(publicKeyPoint: point, commonName: "Tama LocalSend", now: now)
        guard let signature = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error) as Data? else {
            throw TLSError.keychain(OSStatus((error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? -1), "signature")
        }
        return CertificateBuilder.certificate(tbs: tbs, signature: signature)
    }

    static func fingerprint(ofCertificate der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Keychain

    private static func storedIdentity() -> Identity? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let result,
              CFGetTypeID(result) == SecIdentityGetTypeID() else { return nil }
        let identity = result as! SecIdentity
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { return nil }
        // Renew a certificate within a month of expiring.
        if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [CFString: Any],
           let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
           let seconds = (entry[kSecPropertyKeyValue] as? NSNumber)?.doubleValue,
           Date(timeIntervalSinceReferenceDate: seconds) < Date().addingTimeInterval(30 * 86_400) {
            return nil
        }
        return Identity(identity: identity, fingerprint: fingerprint(ofCertificate: SecCertificateCopyData(cert) as Data))
    }

    private static func deleteStored() {
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: label] as CFDictionary)
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag] as CFDictionary)
    }

    private static func create() throws -> Identity {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrLabel: label,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: keyTag,
                kSecAttrLabel: label,
            ] as [CFString: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw TLSError.keychain(OSStatus((error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? -1), "key")
        }
        let der = try selfSignedCertificate(for: privateKey)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw TLSError.keychain(errSecDecode, "certificate")
        }
        let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate, kSecAttrLabel: label] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw TLSError.keychain(status, "store") }
        var identity: SecIdentity?
        let found = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        guard found == errSecSuccess, let identity else { throw TLSError.keychain(found, "identity") }
        return Identity(identity: identity, fingerprint: fingerprint(ofCertificate: der))
    }
}

/// Just enough DER to write an X.509 v3 certificate with an EC P-256 key,
/// signed ecdsa-with-SHA256.
enum CertificateBuilder {
    static func tbsCertificate(publicKeyPoint: Data, commonName: String, now: Date) -> Data {
        var serial = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F // positive
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([2, 5, 4, 3]) + DER.utf8String(commonName))))
        let validity = DER.sequence(DER.time(now.addingTimeInterval(-86_400)) + DER.time(now.addingTimeInterval(10 * 365 * 86_400)))
        let spki = DER.sequence(
            DER.sequence(DER.oid([1, 2, 840, 10045, 2, 1]) + DER.oid([1, 2, 840, 10045, 3, 1, 7]))
                + DER.bitString(publicKeyPoint)
        )
        return DER.sequence(
            DER.explicit(0, DER.integer([2]))
                + DER.integer(serial)
                + signatureAlgorithm
                + name + validity + name + spki
        )
    }

    static func certificate(tbs: Data, signature: Data) -> Data {
        DER.sequence(tbs + signatureAlgorithm + DER.bitString(signature))
    }

    private static var signatureAlgorithm: Data { DER.sequence(DER.oid([1, 2, 840, 10045, 4, 3, 2])) }
}

enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            var bytes: [UInt8] = []
            var v = n
            while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
            out.append(0x80 | UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        return out + content
    }

    static func sequence(_ content: Data) -> Data { tlv(0x30, content) }
    static func set(_ content: Data) -> Data { tlv(0x31, content) }
    static func explicit(_ tag: UInt8, _ content: Data) -> Data { tlv(0xA0 | tag, content) }
    static func utf8String(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func bitString(_ bits: Data) -> Data { tlv(0x03, Data([0]) + bits) }

    static func integer(_ bytes: [UInt8]) -> Data {
        var b = Array(bytes.drop { $0 == 0 })
        if b.isEmpty { b = [0] }
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, Data(b))
    }

    static func oid(_ arcs: [UInt]) -> Data {
        var out = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(arc & 0x7F)]
            var v = arc >> 7
            while v > 0 { chunk.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            out.append(contentsOf: chunk)
        }
        return tlv(0x06, out)
    }

    /// UTCTime before 2050, GeneralizedTime after, as RFC 5280 asks.
    static func time(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date).year ?? 2000
        if year < 2050 {
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return tlv(0x17, Data(formatter.string(from: date).utf8))
        }
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return tlv(0x18, Data(formatter.string(from: date).utf8))
    }
}
