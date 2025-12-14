import Foundation

#if canImport(MbedTLS) && canImport(MbedTLSShim)
import MbedTLSShim

public enum MbedTLSJpakeError: Error {
    case initializationFailed(Int32)
    case operationFailed(Int32)
    case missingPassword
}

public final class MbedTLSJpakeAdapter {
    private var client = mbedtls_shim_jpake_client()
    private var rngContext: Unmanaged<RngBox>?

    public init(password: Data, random: @escaping JpakeProvider.RandomBytesGenerator) throws {
        guard !password.isEmpty else {
            throw MbedTLSJpakeError.missingPassword
        }

        let status = password.withUnsafeBytes { buffer -> Int32 in
            let ptr = buffer.bindMemory(to: UInt8.self).baseAddress
            return Int32(mbedtls_shim_jpake_init(&client, ptr, buffer.count))
        }

        guard status == 0 else {
            throw MbedTLSJpakeError.initializationFailed(status)
        }

        let box = RngBox(random)
        rngContext = Unmanaged.passRetained(box)
        mbedtls_shim_jpake_set_rng(&client, MbedTLSJpakeAdapter.rngCallback, rngContext?.toOpaque())
    }

    deinit {
        if let rngContext {
            rngContext.release()
        }
        mbedtls_shim_jpake_free(&client)
    }

    public func round1() throws -> Data {
        try writeRound(using: mbedtls_shim_jpake_round1)
    }

    public func consumeRound1(_ data: Data) throws {
        try consume(data, with: mbedtls_shim_jpake_read_round1)
    }

    public func round2() throws -> Data {
        try writeRound(using: mbedtls_shim_jpake_round2)
    }

    public func consumeRound2(_ data: Data) throws {
        try consume(data, with: mbedtls_shim_jpake_read_round2)
    }

    public func deriveSecret() throws -> Data {
        var buffer = mbedtls_shim_buffer()
        let status = Int32(mbedtls_shim_jpake_derive(&client, &buffer))
        guard status == 0 else {
            throw MbedTLSJpakeError.operationFailed(status)
        }

        defer { mbedtls_shim_buffer_free(&buffer) }
        return Data(bytes: buffer.bytes, count: buffer.length)
    }

    private func writeRound(using function: (UnsafeMutablePointer<mbedtls_shim_jpake_client>?, UnsafeMutablePointer<mbedtls_shim_buffer>?) -> Int32) throws -> Data {
        var buffer = mbedtls_shim_buffer()
        let status = function(&client, &buffer)
        guard status == 0 else {
            throw MbedTLSJpakeError.operationFailed(status)
        }

        defer { mbedtls_shim_buffer_free(&buffer) }
        return Data(bytes: buffer.bytes, count: buffer.length)
    }

    private func consume(_ data: Data, with function: (UnsafeMutablePointer<mbedtls_shim_jpake_client>?, UnsafePointer<UInt8>?, Int) -> Int32) throws {
        let status = data.withUnsafeBytes { buffer -> Int32 in
            let ptr = buffer.bindMemory(to: UInt8.self).baseAddress
            return function(&client, ptr, buffer.count)
        }

        guard status == 0 else {
            throw MbedTLSJpakeError.operationFailed(status)
        }
    }

    private static let rngCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int32 = {
        context, output, length in
        guard let context, let output, length > 0 else {
            return -1
        }

        let box = Unmanaged<RngBox>.fromOpaque(context).takeUnretainedValue()
        let bytes = box.generator(length)
        guard bytes.count >= length else {
            return -1
        }

        bytes.copyBytes(to: output, count: length)
        return 0
    }

    private final class RngBox {
        let generator: JpakeProvider.RandomBytesGenerator

        init(_ generator: @escaping JpakeProvider.RandomBytesGenerator) {
            self.generator = generator
        }
    }
}
#endif
