import Testing
@testable import ConclaveCore

@Suite struct ETagTests {
    @Test func readsTheCoreBehindCaddysSuffix() {
        #expect(ETag.core(#""ab12-3f-42""#) == "ab12-3f-42")
        #expect(ETag.core(#"W/"ab12-3f-42-zstd""#) == "ab12-3f-42")
        #expect(ETag.core(#""ab12-3f-42-gzip""#) == "ab12-3f-42")
    }

    @Test func seqIsTheLastPart() {
        #expect(ETag.seq(#""ab12-3f-42-zstd""#) == 42)
        #expect(ETag.seq(nil) == 0)
    }

    @Test func refusesForeignTags() {
        #expect(ETag.core("") == "")
        #expect(ETag.core(#""xyz-3f-42""#) == "")
        #expect(ETag.core(#""ab12-3f-x""#) == "")
        #expect(ETag.core(#""ab12-3f""#) == "")
    }
}
