import Foundation

#if canImport(SwiftECC) && canImport(BigInt)
import SwiftECC
import BigInt

struct EcJpake {
    enum Role {
        case client
        case server
    }

    typealias RandomBytesGenerator = (Int) -> Data

    private var xm1: BInt?
    private var Xm1: Point?
    private var xm2: BInt?
    private var Xm2: Point?
    private var Xp1: Point?
    private var Xp2: Point?
    private var Xp: Point?
    private var s: BInt

    private var hasPeerRound1 = false
    private var hasPeerRound2 = false
    private var myRound1: Data?
    private var myRound2: Data?
    private var derivedSecret: Data?

    let role: Role
    let myId: Data
    let peerId: Data
    let domain: Domain
    let rand: RandomBytesGenerator

    init(role: Role, password: Data, random: @escaping RandomBytesGenerator) {
        self.role = role
        self.rand = random
        self.domain = Domain.instance(curve: .EC256r1)
        self.s = BInt(magnitude: [UInt8](password))
        if role == .client {
            self.myId = Data("client".utf8)
            self.peerId = Data("server".utf8)
        } else {
            self.myId = Data("server".utf8)
            self.peerId = Data("client".utf8)
        }
    }

    mutating func getRound1() -> Data {
        if let data = myRound1 { return data }
        var out = Data()
        let kp1 = genKeyPair(domain.g)
        xm1 = kp1.priv
        Xm1 = kp1.pub
        writePoint(Xm1!, to: &out)
        writeZkp(&out, base: domain.g, x: xm1!, X: Xm1!, id: myId)
        let kp2 = genKeyPair(domain.g)
        xm2 = kp2.priv
        Xm2 = kp2.pub
        writePoint(Xm2!, to: &out)
        writeZkp(&out, base: domain.g, x: xm2!, X: Xm2!, id: myId)
        myRound1 = out
        return out
    }

    mutating func readRound1(_ data: Data) {
        precondition(!hasPeerRound1, "Invalid protocol state")
        var r = DataReader(data)
        Xp1 = readPoint(&r)
        readZkp(&r, base: domain.g, X: Xp1!, id: peerId)
        Xp2 = readPoint(&r)
        readZkp(&r, base: domain.g, X: Xp2!, id: peerId)
        hasPeerRound1 = true
    }

    mutating func getRound2() -> Data {
        if let data = myRound2 { return data }
        precondition(hasPeerRound1 && myRound1 != nil, "Invalid protocol state")
        var out = Data()
        let G = try! domain.addPoints(try! domain.addPoints(Xp1!, Xp2!), Xm1!)
        let xm = mulSecret(xm2!, s, negate: false)
        let Xm = try! domain.multiplyPoint(G, xm)
        if role == .server {
            writeCurveId(to: &out)
        }
        writePoint(Xm, to: &out)
        writeZkp(&out, base: G, x: xm, X: Xm, id: myId)
        myRound2 = out
        return out
    }

    mutating func readRound2(_ data: Data) {
        precondition(!hasPeerRound2 && hasPeerRound1 && myRound1 != nil, "Invalid protocol state")
        var r = DataReader(data)
        if role == .client {
            readCurveId(&r)
        }
        let G = try! domain.addPoints(try! domain.addPoints(Xm1!, Xm2!), Xp1!)
        Xp = readPoint(&r)
        readZkp(&r, base: G, X: Xp!, id: peerId)
        hasPeerRound2 = true
    }

    mutating func deriveSecret() -> Data {
        if let d = derivedSecret { return d }
        precondition(hasPeerRound2, "Invalid protocol state")
        let xm2s = mulSecret(xm2!, s, negate: true)
        let tmp = try! domain.multiplyPoint(Xp2!, xm2s)
        let K = try! domain.multiplyPoint(try! domain.addPoints(Xp!, tmp), xm2!)
        let encoded = domain.encodePoint(K, compress: false)
        let xCoord = Data(encoded.dropFirst(1).prefix(32))
        derivedSecret = Data(SHA256.hash(data: xCoord))
        return derivedSecret!
    }

    // MARK: - ZKP helpers

    private mutating func readZkp(_ reader: inout DataReader, base: Point, X: Point, id: Data) {
        let V = readPoint(&reader)
        let r = readNum(&reader)
        let h = zkpHash(base: base, V: V, X: X, id: id)
        let lhs = try! domain.addPoints(try! domain.multiplyPoint(base, r), try! domain.multiplyPoint(X, h.mod(domain.order)))
        precondition(lhs == V, "Validation failed")
    }

    private mutating func writeZkp(_ out: inout Data, base: Point, x: BInt, X: Point, id: Data) {
        let kp = genKeyPair(base)
        let v = kp.priv
        let V = kp.pub
        let h = zkpHash(base: base, V: V, X: X, id: id)
        let r = (v - x * h).mod(domain.order)
        writePoint(V, to: &out)
        writeNum(r, to: &out)
    }

    private func zkpHash(base: Point, V: Point, X: Point, id: Data) -> BInt {
        var out = Data()
        writeZkpHashPoint(base, to: &out)
        writeZkpHashPoint(V, to: &out)
        writeZkpHashPoint(X, to: &out)
        out.appendUInt32BE(UInt32(id.count))
        out.append(id)
        let h = SHA256.hash(data: out)
        return BInt(magnitude: [UInt8](h)).mod(domain.order)
    }

    private func writeZkpHashPoint(_ point: Point, to out: inout Data) {
        let enc = domain.encodePoint(point, compress: false)
        out.appendUInt32BE(UInt32(enc.count))
        out.append(contentsOf: enc)
    }

    // MARK: - Encoding helpers

    private func writePoint(_ p: Point, to out: inout Data) {
        let enc = domain.encodePoint(p, compress: false)
        precondition(enc.count < 256, "Encoded point too long")
        out.appendUInt8(UInt8(enc.count))
        out.append(contentsOf: enc)
    }

    private func readPoint(_ reader: inout DataReader) -> Point {
        let len = Int(reader.readUInt8())
        let bytes = reader.read(len)
        return try! domain.decodePoint([UInt8](bytes))
    }

    private func writeNum(_ n: BInt, to out: inout Data) {
        let enc = n.asMagnitudeBytes()
        precondition(enc.count < 256, "Integer too long")
        out.appendUInt8(UInt8(enc.count))
        out.append(contentsOf: enc)
    }

    private func readNum(_ reader: inout DataReader) -> BInt {
        let len = Int(reader.readUInt8())
        let bytes = reader.read(len)
        return BInt(magnitude: [UInt8](bytes))
    }

    private func writeCurveId(to out: inout Data) {
        out.appendUInt8(3)
        out.appendUInt16BE(23)
    }

    private func readCurveId(_ reader: inout DataReader) {
        let type = reader.readUInt8()
        precondition(type == 3, "Invalid message")
        let id = reader.readUInt16BE()
        precondition(id == 23, "Unexpected curve type")
    }

    // MARK: - Math helpers

    private func genKeyPair(_ G: Point) -> (priv: BInt, pub: Point) {
        let priv = randomScalar()
        let pub = try! domain.multiplyPoint(G, priv)
        return (priv, pub)
    }

    private func randomScalar() -> BInt {
        var n = BInt(magnitude: [UInt8](rand(32)))
        n = n % (domain.order - 1) + 1
        return n
    }

    private func mulSecret(_ X: BInt, _ S: BInt, negate: Bool) -> BInt {
        var b = BInt(magnitude: [UInt8](rand(16)))
        b = b * domain.order + S
        var R = X * b
        if negate { R = -R }
        return R.mod(domain.order)
    }
}

#endif

// MARK: - Byte helpers

private struct DataReader {
    private let data: Data
    private var idx: Int = 0

    init(_ data: Data) { self.data = data }

    mutating func read(_ count: Int) -> Data {
        let end = idx + count
        let sub = data[idx..<end]
        idx = end
        return sub
    }

    mutating func readUInt8() -> UInt8 {
        let v = data[idx]
        idx += 1
        return v
    }

    mutating func readUInt16BE() -> UInt16 {
        let bytes = read(2)
        return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex+1])
    }
}

private extension Data {
    mutating func appendUInt8(_ v: UInt8) { append(contentsOf: [v]) }
    mutating func appendUInt16BE(_ v: UInt16) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
    mutating func appendUInt32BE(_ v: UInt32) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}
