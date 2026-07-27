//
//  PropertyValue.swift
//  CircuitPro
//
//  Created by Giorgi Tchelidze on 7/25/25.
//

import Foundation

enum PropertyValue: Codable, Equatable, Hashable {
    case single(Double?)
    case range(min: Double?, max: Double?)
    case text(String)

    var type: PropertyValueType {
        switch self {
        case .single: return .single
        case .range: return .range
        case .text: return .text
        }
    }

    var description: String {
        switch self {
        case .single(let value):
            if let value { return "\(value)" } else { return "" }
        case let .range(min, max):
            return "\(min ?? 0) to \(max ?? 0)"
        case .text(let value):
            return value
        }
    }

    // — Codable remains the same but modified for optionals —
    private enum CodingKeys: String, CodingKey {
        case type, value, min, max
    }

    private enum ValueType: String, Codable {
        case single, range, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .single:
            let value = try container.decodeIfPresent(Double.self, forKey: .value)
            self = .single(value)
        case .range:
            let min = try container.decodeIfPresent(Double.self, forKey: .min)
            let max = try container.decodeIfPresent(Double.self, forKey: .max)
            self = .range(min: min, max: max)
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .single(let value):
            try container.encode(ValueType.single, forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
        case let .range(min, max):
            try container.encode(ValueType.range, forKey: .type)
            try container.encodeIfPresent(min, forKey: .min)
            try container.encodeIfPresent(max, forKey: .max)
        case .text(let value):
            try container.encode(ValueType.text, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

enum PropertyValueType: String, CaseIterable, Identifiable, Codable {
    case single
    case range
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "Single Value"
        case .range: return "Range"
        case .text: return "Text"
        }
    }
}
