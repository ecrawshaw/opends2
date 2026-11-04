import Foundation

/// Which unit system to show the car's readings in. The car always reports metric; `imperial`
/// converts at display time. Stored in UserDefaults under "units" so static helpers, the views
/// and the MCP server can all read the current choice without threading it through every call.
enum UnitSystem: String, CaseIterable {
    case metric, imperial
    var label: String { self == .metric ? "Metric" : "Imperial" }
}

/// Converts a numeric reading (value + unit) from the car's metric units into the chosen system.
/// Units that have no imperial counterpart (rpm, volts, %, degrees, counts) pass through unchanged.
enum Measure {
    /// The current choice, read live from UserDefaults (default: imperial — this is a US-market car).
    static var system: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: "units") ?? "imperial") ?? .imperial
    }

    /// One conversion: how to turn a metric value into imperial, and the imperial unit label.
    private struct Rule { let unit: String; let f: (Double) -> Double }

    /// Keyed by a normalised metric unit. l/100km → mpg is inverse, handled by its closure.
    private static let rules: [String: Rule] = [
        "°c":      Rule(unit: "°F")    { $0 * 9 / 5 + 32 },
        "km/h":    Rule(unit: "mph")   { $0 * 0.621371 },
        "km":      Rule(unit: "mi")    { $0 * 0.621371 },
        "m":       Rule(unit: "ft")    { $0 * 3.280840 },
        "cm":      Rule(unit: "in")    { $0 * 0.393701 },
        "mm":      Rule(unit: "in")    { $0 * 0.039370 },
        "bar":     Rule(unit: "psi")   { $0 * 14.50377 },
        "kpa":     Rule(unit: "psi")   { $0 * 0.145038 },
        "hpa":     Rule(unit: "psi")   { $0 * 0.014504 },
        "mbar":    Rule(unit: "psi")   { $0 * 0.014504 },
        "l":       Rule(unit: "gal")   { $0 * 0.264172 },
        "liter":   Rule(unit: "gal")   { $0 * 0.264172 },
        "l/h":     Rule(unit: "gal/h") { $0 * 0.264172 },
        "nm":      Rule(unit: "lb·ft") { $0 * 0.737562 },
        "kg":      Rule(unit: "lb")    { $0 * 2.204623 },
        "g":       Rule(unit: "oz")    { $0 * 0.035274 },
        "kw":      Rule(unit: "hp")    { $0 * 1.341022 },
        "l/100km": Rule(unit: "mpg")   { $0 == 0 ? 0 : 235.215 / $0 },
    ]

    private static func norm(_ unit: String) -> String {
        unit.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "°C", with: "°c")
            .lowercased()
    }

    /// Parse a reading that may use a German decimal comma or carry a sign.
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Convert a (text, unit) reading. Returns the converted text + unit, or the input unchanged
    /// when the system is metric, the unit has no rule, or the text isn't numeric.
    static func convert(text: String, unit: String, to system: UnitSystem = Measure.system)
        -> (text: String, unit: String) {
        guard system == .imperial, let rule = rules[norm(unit)], let v = number(text) else {
            return (text, unit)
        }
        return (format(rule.f(v), like: text), rule.unit)
    }

    /// Convert a numeric reading, keeping the number form. Used by the gauges.
    static func convert(number: Double?, text: String, unit: String, to system: UnitSystem = Measure.system)
        -> (number: Double?, text: String, unit: String) {
        guard system == .imperial, let rule = rules[norm(unit)] else { return (number, text, unit) }
        guard let v = number ?? Measure.number(text) else { return (number, text, unit) }
        let out = rule.f(v)
        return (out, format(out, like: text), rule.unit)
    }

    /// Format the converted value with roughly the input's precision (integers stay integers).
    private static func format(_ v: Double, like text: String) -> String {
        let decimals = text.contains(".") || text.contains(",")
            ? max(0, text.count - (text.lastIndex(where: { $0 == "." || $0 == "," }).map { text.distance(from: text.startIndex, to: $0) + 1 } ?? text.count))
            : 0
        let places = min(decimals, 2)
        return String(format: "%.\(places)f", v)
    }
}
