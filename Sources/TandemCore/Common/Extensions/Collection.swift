//
//  Collection.swift
//  TandemKit
//
//  Created by James Woglom on 1/14/25.
//

public extension Collection {
    func chunked(into size: Int) -> [SubSequence] {
        precondition(size > 0, "Chunk size must be greater than zero")
        var start = startIndex
        return stride(from: 0, to: count, by: size).map {_ in
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            defer { start = end }
            return self[start..<end]
        }
    }
}
