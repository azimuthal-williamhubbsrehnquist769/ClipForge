import SwiftUI
import AVFoundation
import AppKit

/// An NSViewRepresentable that hosts an AVSampleBufferDisplayLayer for live capture preview.
struct CapturePreviewView: NSViewRepresentable {

    let displayLayer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> PreviewHostView {
        PreviewHostView(displayLayer: displayLayer)
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {}
}

final class PreviewHostView: NSView {
    let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
