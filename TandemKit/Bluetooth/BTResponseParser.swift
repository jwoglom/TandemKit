import Foundation
import CoreBluetooth

/// Parses raw Bluetooth notification packets into pump messages.
/// This is a minimal Swift port of PumpX2 `BTResponseParser` used for unit testing.
struct BTResponseParser {
    static func parse(wrapper: TronMessageWrapper, output: Data, characteristic: CBUUID) -> PumpResponseMessage? {
        var parser = wrapper.buildPacketArrayList(.Response)
        parser.validatePacket(output)
        if parser.needsMorePacket() {
            return PumpResponseMessage(data: output)
        }
        let authKey = PumpStateSupplier.authenticationKey()
        guard parser.validate(authKey) else { return PumpResponseMessage(data: output) }
        let msgData = parser.messageData().dropFirst(3) // remove op, txid, size
        // TODO: message decoding not yet implemented
        return PumpResponseMessage(data: output)
    }
}