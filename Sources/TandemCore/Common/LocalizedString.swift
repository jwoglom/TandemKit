//
//  LocalizedString.swift
//  TandemKit
//
//  Created by James Woglom on 1/13/25.
//

//
//  Basis: OmniBLE LocalizedString.swift
//
//  Created by Kathryn DiSimone on 8/15/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

private class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

public func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value = value {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, comment: comment)
    }
}
