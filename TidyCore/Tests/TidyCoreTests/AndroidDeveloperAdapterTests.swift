import Foundation
import Testing
@testable import TidyCore

@Suite("Android developer adapter")
struct AndroidDeveloperAdapterTests {
    @Test("AVD metadata without runtime token remains unknown inventory")
    func parsesBoundedAVDWithoutInventingRuntimeIdentity() throws {
        let avd = try #require(AndroidDeveloperAdapter.parseAVDINI(Data("""
        avd.ini.displayname=Fixture
        path=/private/fixture
        target=android-35
        """.utf8)))
        #expect(avd.displayName == "Fixture")
        #expect(avd.runtimeInstanceToken == nil)
        #expect(AndroidDeveloperAdapter.parseAVDINI(Data("x=x\nx=y".utf8)) == nil)
    }
}
