import Foundation

public enum ByteUnitStyle: String, Codable, Sendable, Equatable {
    case binary, decimal
}

/// Human-readable byte counts with explicit IEC or SI labels. The explicit
/// labels avoid presenting binary values with decimal `GB`/`MB` suffixes.
public enum ByteFormat: Sendable {
    public static func human(_ bytes: Int64, units: ByteUnitStyle = .binary,
                             locale: Locale = .current) -> String {
        let divisor = units == .binary ? 1_024.0 : 1_000.0
        let labels = units == .binary
            ? ["B", "KiB", "MiB", "GiB", "TiB"]
            : ["B", "kB", "MB", "GB", "TB"]
        var value = Double(max(0, bytes))
        var index = 0
        while value >= divisor, index < labels.count - 1 {
            value /= divisor
            index += 1
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < 10 && index > 0 ? 1 : 0
        let rendered = formatter.string(from: NSNumber(value: value)) ?? "0"
        return rendered + " " + labels[index]
    }
}
