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
        #expect(PhotoRead.best([piece, whole]) == whole)
        #expect(PhotoRead.best([whole, both]) == both)
        #expect(PhotoRead.best([whole, whole]) == whole && PhotoRead.best([]) == nil)
    }
}
