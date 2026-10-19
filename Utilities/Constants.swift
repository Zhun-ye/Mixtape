//
//  ObfuscatedStrings.swift
//  Mixtape
//

import Foundation

/// Hex-encoded string constant.
private let _ytm: [UInt8] = [0x59, 0x6F, 0x75, 0x54, 0x75, 0x62, 0x65, 0x20, 0x4D, 0x75, 0x73, 0x69, 0x63]

/// Decoded display name.
var ytmDisplayName: String { String(bytes: _ytm, encoding: .utf8) ?? "" }
