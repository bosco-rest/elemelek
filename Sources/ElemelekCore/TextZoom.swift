import Foundation

/// Manual text zoom (Cmd+/Cmd−/Cmd0): a factor every font size multiplies by.
/// Pure stepping math; the model owns persistence, views read it through the environment.
public enum TextZoom {
    public static let `default` = 1.0
    public static let min = 0.75
    public static let max = 2.0
    public static let step = 1.15
    public static let key = "textZoom"

    public static func clamped(_ z: Double) -> Double { Swift.min(max, Swift.max(min, z)) }

    public static func stored() -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return (min...max).contains(v) ? v : `default`
    }

    public static func zoomIn(_ z: Double) -> Double { clamped(((z * step) * 1000).rounded() / 1000) }
    public static func zoomOut(_ z: Double) -> Double { clamped(((z / step) * 1000).rounded() / 1000) }
}
