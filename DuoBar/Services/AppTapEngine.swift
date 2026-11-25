import CoreAudio
import Foundation

/// Taps one app (all its audio processes), mutes it at the source and replays it to a target
/// output device through a private aggregate, scaled by a per-app gain. One engine per app.
/// Private taps and aggregates disappear with the process, so a crash restores the original sound.
@available(macOS 14.2, *)
final class AppTapEngine {
    let bundleID: String
    let processObjects: [AudioObjectID]
    let targetUID: String

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private(set) var isRunning = false

    /// Shared with the IO thread: [0] target gain, [1] current gain, [2] input peak, [3] output peak.
    private let shared: UnsafeMutablePointer<Float>

    private static let bufferFrames: UInt32 = 512

    private var gainValue: Float = 1
    private var mutedValue = false

    init(bundleID: String, processObjects: [AudioObjectID], targetUID: String) {
        self.bundleID = bundleID
        self.processObjects = processObjects
        self.targetUID = targetUID
        shared = .allocate(capacity: 4)
        shared.initialize(repeating: 0, count: 4)
        shared[0] = 1
        shared[1] = 1
    }

    deinit {
        stop()
        shared.deallocate()
    }

    /// Target gain 0...1. Only writes the shared pointer, no rebuild.
    var gain: Float {
        get { gainValue }
        set {
            gainValue = max(0, min(1, newValue))
            publishTarget()
        }
    }

    var muted: Bool {
        get { mutedValue }
        set {
            mutedValue = newValue
            publishTarget()
        }
    }

    /// Max input and output peak since the last read; reading resets both.
    var peaks: (input: Float, output: Float) {
        let result = (input: shared[2], output: shared[3])
        shared[2] = 0
        shared[3] = 0
        return result
    }

    private func publishTarget() {
        shared[0] = mutedValue ? 0 : gainValue
    }

    func start() throws {
        guard !isRunning else { return }
        guard !processObjects.isEmpty else {
            throw CAError(step: "start tap for \(bundleID): no process objects", status: kAudioHardwareBadObjectError)
        }
        guard let device = Self.device(uid: targetUID) else {
            throw CAError(step: "find target device '\(targetUID)'", status: kAudioHardwareBadDeviceError)
        }

        let tap = CATapDescription(stereoMixdownOfProcesses: processObjects)
        tap.name = "Status Ring \(bundleID)"
        tap.isPrivate = true
        tap.muteBehavior = .mutedWhenTapped

        do {
            try check(AudioHardwareCreateProcessTap(tap, &tapID), "create process tap")

            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Status Ring \(bundleID)",
                kAudioAggregateDeviceUIDKey: "com.jurek.statusring.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: targetUID,
                kAudioAggregateDeviceClockDeviceKey: targetUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: targetUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tap.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "create aggregate")

            var frames = Self.bufferFrames
            var addr = CAQuery.address(kAudioDevicePropertyBufferFrameSize)
            AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)

            let s = shared
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, inData, _, outData, _ in
                AppTapEngine.render(inData, outData, s)
            }, "create IOProc")

            // The device's own input streams are not needed: switch them off so no mic data is read
            // (a Bluetooth headset stays out of HFP, no mic indicator).
            let interfaceStreams = CAQuery.objects(device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput).count
            setInterfaceInputs(on: false, interfaceStreams: interfaceStreams)

            shared[1] = shared[0]
            shared[2] = 0
            shared[3] = 0
            try check(AudioDeviceStart(aggregateID, ioProc), "start IO")
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProc, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProc)
            AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        }
        ioProc = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        isRunning = false
    }

    private static func device(uid: String) -> AudioObjectID? {
        CAQuery.objects(CAQuery.system, kAudioHardwarePropertyDevices).first {
            CAQuery.string($0, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    /// Switches the target device's own input streams off for our IOProc; the tap always stays on.
    private func setInterfaceInputs(on: Bool, interfaceStreams: Int) {
        guard let ioProc else { return }
        let streams = CAQuery.objects(aggregateID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        guard streams.count > 1 else { return }
        let size = MemoryLayout<AudioHardwareIOProcStreamUsage>.size + MemoryLayout<UInt32>.size * (streams.count - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        let usage = raw.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streams.count)
        let flags = raw.advanced(by: MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!)
            .bindMemory(to: UInt32.self, capacity: streams.count)
        for i in 0..<streams.count { flags[i] = (i >= interfaceStreams || on) ? 1 : 0 }
        var addr = CAQuery.address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(size), raw)
    }

    /// Real-time thread: no allocation, no locks, no logging. Copies the stereo tap to output
    /// channels 1/2 with a per-buffer linear gain ramp so level changes do not click.
    private static func render(_ inData: UnsafePointer<AudioBufferList>,
                               _ outData: UnsafeMutablePointer<AudioBufferList>,
                               _ s: UnsafeMutablePointer<Float>) {
        let outs = UnsafeMutableAudioBufferListPointer(outData)
        for buffer in outs { if let p = buffer.mData { memset(p, 0, Int(buffer.mDataByteSize)) } }

        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        // The single tap is always the last input buffer, whether or not the device streams are listed.
        guard ins.count > 0 else { return }
        let tapBuffer = ins[ins.count - 1]
        guard let src = tapBuffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let inChannels = Int(tapBuffer.mNumberChannels)
        guard inChannels > 0 else { return }
        let frames = Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)

        let target = s[0]
        let start = s[1]
        let step = frames > 0 ? (target - start) / Float(frames) : 0
        var inPeak: Float = 0
        var outPeak: Float = 0

        // Walk output channels across buffers (works for interleaved and non-interleaved layouts).
        var channel = 0
        for buffer in outs {
            let outChannels = Int(buffer.mNumberChannels)
            guard let dst = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                channel += outChannels; continue
            }
            let outFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * max(outChannels, 1)))
            for c in 0..<outChannels where channel + c < 2 {
                // Mono tap feeds both sides.
                let srcChannel = min(channel + c, inChannels - 1)
                var g = start
                for f in 0..<outFrames {
                    g += step
                    let x = src[f * inChannels + srcChannel]
                    let y = x * g
                    dst[f * outChannels + c] = y
                    inPeak = max(inPeak, abs(x))
                    outPeak = max(outPeak, abs(y))
                }
            }
            channel += outChannels
        }
        s[1] = target
        // Peaks accumulate until the main thread reads and resets them (a lost update is harmless).
        s[2] = max(s[2], inPeak)
        s[3] = max(s[3], outPeak)
    }
}
