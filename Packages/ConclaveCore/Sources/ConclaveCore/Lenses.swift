import Foundation

/// One of the scanner's lens buttons, like the Camera app's "0.5", "1×" and "4": the zoom factor to set
/// on the camera and the number to show, counted from the main (wide) camera.
public struct Lens: Equatable, Sendable, Identifiable {
    /// The camera's own zoom factor (1 = its widest lens).
    public var zoom: Double
    /// "0.5", "1", "2", "4": the zoom against the main camera, without the "×" (the picked one shows it).
    public var label: String

    public var id: Double { zoom }

    public init(zoom: Double, label: String) {
        self.zoom = zoom
        self.label = label
    }

    /// The lens buttons for a camera that switches lenses at `switchOvers` (AVFoundation's
    /// `virtualDeviceSwitchOverVideoZoomFactors`), within the zoom range the scanner allows. With an ultra-wide
    /// lens the camera's 1 is "0.5" and the first switch-over is the main camera's "1"; without one, the
    /// switch-overs are the tele lenses. A camera with one lens gets "1" and "2", for small print.
    public static func choices(switchOvers: [Double], ultraWide: Bool, min: Double = 1, max: Double = 10) -> [Lens] {
        let base = ultraWide ? (switchOvers.first ?? 2) : 1
        var zooms = [1.0] + switchOvers
        if zooms.count == 1 { zooms.append(2) }
        return zooms.filter { $0 >= min && $0 <= max }.map { Lens(zoom: $0, label: label($0 / base)) }
    }

    /// 0.5 → "0.5", 2 → "2", 2.5 → "2.5": at most one decimal, no trailing zero.
    static func label(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// The button to show as picked for the camera's current zoom: the last lens at or below it.
    public static func picked(_ zoom: Double, in lenses: [Lens]) -> Lens? {
        lenses.last { $0.zoom <= zoom + 0.01 } ?? lenses.first
    }
}
