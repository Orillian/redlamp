import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampEngine

/// The models picking Sky offers, while they aren't on this Mac (MSK-37).
struct SkyModelOfferTests {
    static func model(
        _ id: String, _ state: ModelInfo.State = .notDownloaded, cleared: Bool = true, published: Bool = true,
        fits: Bool = true,
    ) -> ModelInfo {
        ModelInfo(
            id: id, name: id, purpose: "", downloadBytes: 1, state: state, isCleared: cleared, isPublished: published,
            fitsThisMac: fits,
        )
    }

    @Test func `Sky offers Segment Anything, then Depth Anything 3, and nothing else`() {
        let offered = RedlampEngine.skyModelsToOffer(from: [
            Self.model("depth-anything-3-mono-large"), Self.model("sam3"), Self.model("sam2.1-tiny"),
            Self.model("depth-anything-v2-small"),
        ])
        #expect(offered.map(\.id) == ["sam2.1-tiny", "depth-anything-3-mono-large"])
    }

    @Test func `a model on this Mac, or downloading, isn't offered`() {
        let offered = RedlampEngine.skyModelsToOffer(from: [
            Self.model("sam2.1-tiny", .ready), Self.model("depth-anything-3-mono-large", .downloading(0.4)),
        ])
        #expect(offered.isEmpty)
        let one = RedlampEngine.skyModelsToOffer(from: [
            Self.model("sam2.1-tiny", .ready), Self.model("depth-anything-3-mono-large"),
        ])
        #expect(one.map(\.id) == ["depth-anything-3-mono-large"])
    }

    @Test func `a model not cleared for everyone, not published or too big for this Mac isn't offered`() {
        #expect(RedlampEngine.skyModelsToOffer(from: [Self.model("sam2.1-tiny", cleared: false)]).isEmpty)
        #expect(RedlampEngine.skyModelsToOffer(from: [Self.model("sam2.1-tiny", published: false)]).isEmpty)
        #expect(RedlampEngine.skyModelsToOffer(from: [Self.model("depth-anything-3-mono-large", fits: false)]).isEmpty)
    }
}
