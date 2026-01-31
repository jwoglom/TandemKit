import UIKit

protocol NibLoadable: IdentifiableClass {
    static func nib() -> UINib
}

protocol IdentifiableClass: AnyObject {
    static var className: String { get }
}



extension NibLoadable {
    static func nib() -> UINib {
        UINib(nibName: className, bundle: Bundle(for: self))
    }
}

extension IdentifiableClass {
    static var className: String {
        NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
