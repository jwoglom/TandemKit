import Foundation

struct IOBRequestBuilder {
    static func create(controlIQ: Bool) -> Message {
        if controlIQ {
            return ControlIQIOBRequest()
        } else {
            return NonControlIQIOBRequest()
        }
    }
}
