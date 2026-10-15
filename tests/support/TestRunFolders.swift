import Darwin
import Foundation

/// Where a test run keeps what Redlamp makes, so nothing a test makes reaches the owner's caches.
/// Compiled into every package's tests; those whose code keeps caches move Redlamp's into these as
/// the test bundle loads (`TestRun.c` beside them).
enum TestRun {
    /// The run's own folder, which goes when the run ends.
    static let folder = FileManager.default.temporaryDirectory
        .appending(path: "redlamp-tests-\(getpid())", directoryHint: .isDirectory)

    /// The model compiles, which every run shares and keeps: Core ML keeps what it specialises from a
    /// compile by the compile's path and files, so compiles of each run's own leave another of those
    /// behind each run. Not in the temporary folder, whose files macOS may remove between runs.
    static let compiledModels = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "app.redlamp.tests/CompiledModels", directoryHint: .isDirectory)
}
