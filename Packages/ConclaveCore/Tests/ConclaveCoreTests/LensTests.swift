import Testing
@testable import ConclaveCore

struct LensTests {
    @Test func aProWithThreeLenses() {
        // an iPhone Pro: ultra-wide, main at 2, tele at 8 (4× of the main camera)
        let lenses = Lens.choices(switchOvers: [2, 8], ultraWide: true, min: 1, max: 30)
        #expect(lenses.map(\.label) == ["0.5", "1", "4"])
        #expect(lenses.map(\.zoom) == [1, 2, 8])
    }

    @Test func wideAndUltraWideOnly() {
        #expect(Lens.choices(switchOvers: [2], ultraWide: true).map(\.label) == ["0.5", "1"])
    }

    @Test func wideAndTele() {
        #expect(Lens.choices(switchOvers: [2], ultraWide: false).map(\.label) == ["1", "2"])
    }

    @Test func oneLensGetsADigitalTwo() {
        #expect(Lens.choices(switchOvers: [], ultraWide: false).map(\.label) == ["1", "2"])
    }

    @Test func lensesOutsideTheScannersRangeAreLeftOut() {
        #expect(Lens.choices(switchOvers: [2, 6], ultraWide: true, min: 1, max: 4).map(\.label) == ["0.5", "1"])
    }

    @Test func labels() {
        #expect(Lens.label(0.5) == "0.5" && Lens.label(3) == "3" && Lens.label(2.5) == "2.5" && Lens.label(1.999) == "2")
    }

    @Test func thePickedLensFollowsTheZoom() {
        let lenses = Lens.choices(switchOvers: [2, 8], ultraWide: true, max: 30)
        #expect(Lens.picked(1, in: lenses)?.label == "0.5")
        #expect(Lens.picked(3, in: lenses)?.label == "1")  // a pinch between lenses stays on the main camera
        #expect(Lens.picked(9, in: lenses)?.label == "4")
    }
}
