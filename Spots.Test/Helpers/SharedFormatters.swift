//
//  SharedFormatters.swift
//  Spots.Test
//
//  Shared ISO8601 date formatters and JSON decoder to avoid repeated allocation.
//

import Foundation

extension ISO8601DateFormatter {
    /// Use for encoding/decoding Supabase timestamps with fractional seconds.
    static let fractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Use as fallback when fractional seconds parsing fails.
    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension JSONDecoder {
    /// Shared decoder with ISO8601 date decoding (handles fractional seconds).
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = SharedFormatters.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return d
    }()
}

enum SharedFormatters {
    /// Parses ISO8601 date string (tries fractional seconds, then standard).
    static func date(from string: String) -> Date? {
        ISO8601DateFormatter.fractionalSeconds.date(from: string)
            ?? ISO8601DateFormatter.standard.date(from: string)
    }
}
