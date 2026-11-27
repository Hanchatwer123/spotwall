import Foundation
import ScreenCaptureKit
import Accelerate
import CoreMedia

final class SpectrumAnalyzer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = SpectrumAnalyzer()
    static let bandCount = 64

    private let lock = NSLock()
    private var _bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var _live = false

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "spotwall.audio", qos: .userInteractive)

    private let fftSize = 2048
    private let log2n: vDSP_Length = 11
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var pending: [Float] = []
    private let sampleRate: Float = 44100
    private var edges: [Int] = []

    private override init() {
        fftSetup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 2048)
        super.init()
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let n = Self.bandCount
        let (fMin, fMax): (Float, Float) = (40, 14000)
        let binHz = sampleRate / Float(fftSize)
        edges = (0...n).map { i in
            let f = fMin * powf(fMax / fMin, Float(i) / Float(n))
            return min(fftSize / 2 - 1, max(1, Int(f / binHz)))
        }
    }

    // MARK: Public

    var isLive: Bool { lock.withLock { _live } }
    func snapshot() -> [Float] { lock.withLock { _bands } }

    func start() async {
        guard stream == nil else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 44100
            cfg.channelCount = 2
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)

            let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                             configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) 
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await s.startCapture()
            stream = s
            lock.withLock { _live = true }
        } catch {
            lock.withLock { _live = false }
            print("SpectrumAnalyzer: capture unavailable — \(error.localizedDescription)")
        }
    }

    // MARK: SCStreamDelegate / Output

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        lock.withLock { _live = false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let first = list.first, let data = first.mData else { return }
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = data.assumingMemoryBound(to: Float.self)
            process(UnsafeBufferPointer(start: ptr, count: count))   
        }
    }

    // MARK: DSP

    private func process(_ samples: UnsafeBufferPointer<Float>) {
        pending.append(contentsOf: samples)
        while pending.count >= fftSize {
            analyze(Array(pending[0..<fftSize]))
            pending.removeFirst(fftSize / 2)       
        }
    }

    private func analyze(_ input: [Float]) {
        let n = fftSize, half = n / 2
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }

        let bands = Self.bandCount
        var fresh = [Float](repeating: 0, count: bands)
        for k in 0..<bands {
            let lo = edges[k]
            let hi = max(edges[k + 1], lo + 1)
            var sum: Float = 0
            for i in lo..<min(hi, half) { sum += sqrtf(mags[i]) }
            let amp = sum / Float(max(1, hi - lo)) / Float(n)
            let db = 20 * log10f(max(amp, 1e-7))
            let norm = (db + 72) / 60 + Float(k) / Float(bands) * 0.18  
            fresh[k] = min(1, max(0, norm))
        }

        lock.withLock {
            for k in 0..<bands {
                let old = _bands[k]
                let x = fresh[k]
                _bands[k] = old + (x - old) * (x > old ? 0.6 : 0.15)  
            }
        }
    }
}
