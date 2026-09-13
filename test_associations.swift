#!/usr/bin/env swift
import Foundation
import TandemCore

// Test the MessageRegistry associations
print("=== Testing MessageRegistry Request-Response Associations ===\n")

// Validate all associations
let warnings = MessageRegistry.validateAssociations()
if warnings.isEmpty {
    print("✓ All request-response associations are valid!\n")
} else {
    print("⚠️  Found \(warnings.count) association warnings:\n")
    for warning in warnings {
        print("  - \(warning)")
    }
    print()
}

// Test some specific associations
print("=== Testing Specific Associations ===\n")

// Test ApiVersionRequest -> ApiVersionResponse
if let apiReqMeta = MessageRegistry.metadata(forName: "ApiVersionRequest") {
    print("✓ Found ApiVersionRequest metadata:")
    print("  - OpCode: \(apiReqMeta.opCode)")
    print("  - Size: \(apiReqMeta.size)")
    print("  - Type: \(apiReqMeta.messageType)")

    if let respMeta = MessageRegistry.responseMetadata(for: ApiVersionRequest.self) {
        print("  - Associated Response: \(respMeta.name)")
        print("    - OpCode: \(respMeta.opCode)")
        print("    - Size: \(respMeta.size)")
    } else {
        print("  ⚠️  No associated response found")
    }
} else {
    print("⚠️  ApiVersionRequest metadata not found")
}
print()

// Test reverse lookup: ApiVersionResponse -> ApiVersionRequest
if let apiRespMeta = MessageRegistry.metadata(forName: "ApiVersionResponse") {
    print("✓ Found ApiVersionResponse metadata:")
    print("  - OpCode: \(apiRespMeta.opCode)")
    print("  - Size: \(apiRespMeta.size)")

    if let reqMeta = MessageRegistry.requestMetadata(for: ApiVersionResponse.self) {
        print("  - Associated Request: \(reqMeta.name)")
        print("    - OpCode: \(reqMeta.opCode)")
        print("    - Size: \(reqMeta.size)")
    } else {
        print("  ⚠️  No associated request found")
    }
} else {
    print("⚠️  ApiVersionResponse metadata not found")
}
print()

// Count statistics
let allMessages = MessageRegistry.all
let requests = allMessages.filter { $0.messageType == .Request }
let responses = allMessages.filter { $0.messageType == .Response }
let requestsWithAssoc = requests.filter { $0.associatedType != nil }
let responsesWithAssoc = responses.filter { $0.associatedType != nil }

print("=== Association Statistics ===")
print("Total messages: \(allMessages.count)")
print("Requests: \(requests.count)")
print("  - With associations: \(requestsWithAssoc.count)")
print("  - Without associations: \(requests.count - requestsWithAssoc.count)")
print("Responses: \(responses.count)")
print("  - With associations: \(responsesWithAssoc.count)")
print("  - Without associations: \(responses.count - responsesWithAssoc.count)")
