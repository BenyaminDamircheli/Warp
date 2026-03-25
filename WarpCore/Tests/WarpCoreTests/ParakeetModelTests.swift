import Testing
import WarpCore

@Suite("ParakeetModel")
struct ParakeetModelTests {
  @Test("EOU streaming identifier is distinct from TDT")
  func eouIdentifier() {
    #expect(ParakeetModel.eouStreaming160.identifier == "parakeet-eou-streaming-160ms")
    #expect(ParakeetModel.eouStreaming160.isStreamingEOU)
    #expect(ParakeetModel.eouStreaming160.isTDT == false)
    #expect(ParakeetModel.multilingualV3.isTDT)
    #expect(ParakeetModel.multilingualV3.isStreamingEOU == false)
  }
}
