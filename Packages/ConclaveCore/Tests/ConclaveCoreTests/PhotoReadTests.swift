import Foundation
import Testing
@testable import ConclaveCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct PhotoReadTests {
    @Test func aPhotoFillsTheScreenLikeThePreview() {
        // a 3:4 photo on a taller screen: scaled to the screen's height, its sides cut off
        let photo = CGSize(width: 3000, height: 4000), screen = CGSize(width: 400, height: 800)
        #expect(PhotoRead.screenRect(of: CGRect(x: 0, y: 0, width: 3000, height: 4000), photo: photo, screen: screen)
            == CGRect(x: -100, y: 0, width: 600, height: 800))
        #expect(PhotoRead.screenRect(of: CGRect(x: 1500, y: 2000, width: 300, height: 100), photo: photo, screen: screen)
            == CGRect(x: 200, y: 400, width: 60, height: 20))
        #expect(PhotoRead.screenRect(of: .zero, photo: .zero, screen: screen) == .zero)
    }

    @Test func framesOfSeveralSizesAroundTheMiddle() {
        let frames = PhotoRead.frames(around: CGRect(x: 100, y: 100, width: 200, height: 280))
        #expect(frames.count == 4 && frames[0] == CGRect(x: 100, y: 100, width: 200, height: 280))
        #expect(frames.allSatisfy { abs($0.midX - 200) < 0.001 && abs($0.midY - 240) < 0.001 })
        #expect(frames[1].width < 200 && frames[2].width > 200)
    }

    @Test func theBestHitWins() {
        let elves = Printing(id: "elves", oracleID: "elves", name: "Llanowar Elves", set: "fdn", collectorNumber: "274")
        let fight = Printing(id: "fight", oracleID: "fight", name: "Rejoin the Fight", set: "mh3", collectorNumber: "99")
        let bySetOnly = ReadHit(printing: fight, sure: false, bySet: true, read: "")
        let piece = ReadHit(printing: fight, sure: false, bySet: false, read: "Fight")
        let whole = ReadHit(printing: elves, sure: true, bySet: false, read: "Llanowar Elves")
        let both = ReadHit(printing: elves, sure: true, bySet: true, read: "Llanowar Elves")
        #expect(PhotoRead.best([bySetOnly, piece]) == piece)
        #expect(PhotoRead.best([bySetOnly]) == nil)  // a set line alone is too weak for one photo
        #expect(PhotoRead.best([piece, whole]) == whole)
        #expect(PhotoRead.best([whole, both]) == both)
        #expect(PhotoRead.best([whole, whole]) == whole && PhotoRead.best([]) == nil)
    }

    @Test func aPhotoIsReadOverTheCardFrame() async {
        // a 3:4 photo on a 400 × 800 screen: half size, 100 points cut off left and right
        let photo = CGSize(width: 1200, height: 1600), screen = CGSize(width: 400, height: 800)
        let frame = CardFrame.rect(in: screen, top: 60, bottom: 200)
        func inPhoto(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {  // a frame-relative box, in the photo
            CGRect(x: (Double(frame.minX) + x * Double(frame.width) + 100) * 2, y: (Double(frame.minY) + y * Double(frame.height)) * 2,
                   width: w * Double(frame.width) * 2, height: h * Double(frame.height) * 2)
        }
        let lookup = CardReaderTests.Lookup()
        lookup.byName["llanowar elves|fdn"] = CardReaderTests.elves
        lookup.bySet["fdn/274/en"] = CardReaderTests.elves
        let reader = CardReader(lookup: lookup)
        let lines: [(text: String, box: CGRect)] = [
            ("Llanowar Elves", inPhoto(0.08, 0.04, 0.6, 0.05)),
            ("0274 C", inPhoto(0.05, 0.9, 0.2, 0.02)),
            ("FDN • EN Artist", inPhoto(0.05, 0.93, 0.4, 0.02)),
        ]
        let hit = await PhotoRead.identify(lines, photo: photo, screen: screen, frame: frame, reader: reader)
        #expect(hit?.printing == CardReaderTests.elves && hit?.bySet == true)
        #expect(await PhotoRead.identify([], photo: photo, screen: screen, frame: frame, reader: reader) == nil)
    }
}
