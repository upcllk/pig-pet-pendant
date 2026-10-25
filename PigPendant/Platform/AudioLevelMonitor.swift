import AudioToolbox
import CoreAudio
import Foundation

enum AudioLevelMonitorError: LocalizedError {
    case unsupportedSystem
    case outputUnavailable
    case unsupportedFormat
    case coreAudio(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "系统音频律动需要 macOS 14.2 或更高版本。"
        case .outputUnavailable:
            return "无法获取当前系统音频输出设备。"
        case .unsupportedFormat:
            return "系统音频输出格式不受支持，无法分析节拍。"
        case .coreAudio(let operation, let status):
            return "\(operation)失败（Core Audio 错误 \(status)）。"
        }
    }
}

final class AudioLevelMonitor {
    private let lifecycleQueue = DispatchQueue(label: "local.pigpendant.audio-tap-lifecycle")
    private let captureQueue = DispatchQueue(label: "local.pigpendant.audio-tap-capture",
                                             qos: .userInitiated)
    private var processTapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var beatDetector: DrumBeatDetector?
    var onBeat: ((Double) -> Void)?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        lifecycleQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startTap()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                self.stopTap()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop() {
        lifecycleQueue.async { [weak self] in self?.stopTap() }
    }

    private func startTap() throws {
        guard #available(macOS 14.2, *) else {
            throw AudioLevelMonitorError.unsupportedSystem
        }
        guard aggregateDeviceID == AudioObjectID(kAudioObjectUnknown) else { return }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.name = "Pig Pendant Music Reactive"
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapID),
                  operation: "创建系统音频 tap")
        processTapID = tapID

        let outputUID = try defaultOutputDeviceUID()
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pig Pendant Audio Analysis",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
                  operation: "创建系统音频分析设备")
        aggregateDeviceID = aggregateID

        let format = try tapStreamFormat(tapID)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let beatDetector = DrumBeatDetector(sampleRate: format.mSampleRate) else {
            throw AudioLevelMonitorError.unsupportedFormat
        }
        self.beatDetector = beatDetector

        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, captureQueue) {
            [weak self] _, inputData, _, _, _ in
            guard let self = self else { return }
            self.consume(inputData)
        }, operation: "创建系统音频读取回调")
        deviceProcID = procID
        try check(AudioDeviceStart(aggregateID, procID), operation: "启动系统音频读取")
    }

    private func tapStreamFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
                  operation: "读取系统音频格式")
        return format
    }

    private func defaultOutputDeviceUID() throws -> String {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &outputDevice),
                  operation: "读取默认音频输出设备")
        guard outputDevice != AudioObjectID(kAudioObjectUnknown) else {
            throw AudioLevelMonitorError.outputUnavailable
        }

        address.mSelector = kAudioDevicePropertyDeviceUID
        let uid: CFString = try readProperty(
            outputDevice, address: &address, defaultValue: "" as CFString,
            operation: "读取音频输出设备标识"
        )
        return uid as String
    }

    private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let channels = buffers.compactMap { buffer -> (samples: UnsafePointer<Float>, count: Int, channels: Int)? in
            guard let data = buffer.mData, buffer.mDataByteSize >= MemoryLayout<Float>.size else { return nil }
            return (UnsafePointer(data.assumingMemoryBound(to: Float.self)),
                    Int(buffer.mDataByteSize) / MemoryLayout<Float>.size,
                    max(1, Int(buffer.mNumberChannels)))
        }
        var mono: [Float] = []
        if channels.count > 1 && channels.allSatisfy({ $0.channels == 1 }) {
            let frameCount = channels.map { $0.count }.min() ?? 0
            mono.reserveCapacity(frameCount)
            for frame in 0..<frameCount {
                var sample: Float = 0
                for channel in channels { sample += channel.samples[frame] }
                mono.append(sample / Float(channels.count))
            }
        } else {
            for channel in channels {
                let frameCount = channel.count / channel.channels
                mono.reserveCapacity(mono.count + frameCount)
                for frame in 0..<frameCount {
                    var sample: Float = 0
                    for channelIndex in 0..<channel.channels {
                        sample += channel.samples[frame * channel.channels + channelIndex]
                    }
                    mono.append(sample / Float(channel.channels))
                }
            }
        }
        guard !mono.isEmpty, let beatStrength = beatDetector?.process(mono), beatStrength > 0 else { return }
        DispatchQueue.main.async { [weak self] in self?.onBeat?(beatStrength) }
    }

    private func stopTap() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            if let deviceProcID = deviceProcID {
                let stopStatus = AudioDeviceStop(aggregateDeviceID, deviceProcID)
                if stopStatus != noErr {
                    NSLog("Failed to stop system audio tap: %d", stopStatus)
                }
                let destroyStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if destroyStatus != noErr {
                    NSLog("Failed to destroy system audio callback: %d", destroyStatus)
                }
                self.deviceProcID = nil
            }
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if status != noErr { NSLog("Failed to destroy aggregate audio device: %d", status) }
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if processTapID != AudioObjectID(kAudioObjectUnknown) {
            if #available(macOS 14.2, *) {
                let status = AudioHardwareDestroyProcessTap(processTapID)
                if status != noErr { NSLog("Failed to destroy process audio tap: %d", status) }
            }
            processTapID = AudioObjectID(kAudioObjectUnknown)
        }
        beatDetector = nil
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioLevelMonitorError.coreAudio(operation: operation, status: status)
        }
    }

    private func readProperty<T>(_ objectID: AudioObjectID,
                                 address: inout AudioObjectPropertyAddress,
                                 defaultValue: T, operation: String) throws -> T {
        var value = defaultValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        try check(status, operation: operation)
        return value
    }
}
