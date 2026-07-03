#!/usr/bin/swift
// Tiny helper for build-app.sh: prints one string field from config.json.
// Avoids a jq/python3 dependency — Foundation's JSONSerialization is all we need,
// and Swift is already required by the rest of the toolchain.
//
// Usage: swift read-config.swift <path-to-config.json> <fieldName>

import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: read-config.swift <config.json> <field>\n".data(using: .utf8)!)
    exit(1)
}
let configPath = args[1]
let field = args[2]

let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let value = json[field] as? String else {
    FileHandle.standardError.write("error: field '\(field)' not found or not a string in \(configPath)\n".data(using: .utf8)!)
    exit(1)
}
print(value)
