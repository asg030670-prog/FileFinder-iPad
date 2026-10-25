import Foundation

/// Deterministic, locale-independent byte size formatting (base 1000, like the Files app).
public enum ByteSizeFormatter {
    private static let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    public static func string(fromBytes bytes: Int64) -> String {
        if bytes < 1000 {
            return bytes == 1 ? "1 byte" : "\(max(bytes, 0)) bytes"
        }
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        let rounded = (value * 10).rounded() / 10
        if rounded >= 1000, unitIndex < units.count - 1 {
            return "1 \(units[unitIndex + 1])"
        }
        let formatted = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int64(rounded))
            : String(format: "%.1f", rounded)
        return "\(formatted) \(units[unitIndex])"
    }
}
