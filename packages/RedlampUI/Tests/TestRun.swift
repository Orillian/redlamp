import Darwin
import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampUI

/// Moves Redlamp's caches into the test run's own folder, and its model compiles into the one every
/// run shares (`TestRun`), where a model is compiled once.
@_cdecl("RedlampTestRunBegin")
func testRunBegin() {
    let caches = TestRun.folder.appending(path: "Caches", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: TestRun.folder)
    try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    RedlampFolders.caches = caches
    RedlampFolders.compiledModels = TestRun.compiledModels
    atexit { try? FileManager.default.removeItem(at: TestRun.folder) }
}

@MainActor
struct TestRunTests {
    @Test func `an editor's thumbnails stay in the run's own folder, model compiles in the shared one`() {
        let caches = TestRun.folder.appending(path: "Caches")
        #expect(RedlampFolders.caches.path == caches.path)
        #expect(RedlampFolders.compiledModels.path == TestRun.compiledModels.path)
        #expect(EditorModel(engine: StubEngine()).thumbnailLoader.packs.directory.path
            == caches.appending(path: "Thumbnails").path)
    }
}
