import AVFoundation
import Foundation

enum AudioLevelMonitorError: LocalizedError {
    case permissionDenied
    case inputUnavailable
    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麦克风权限未开启，请在系统设置中允许猪猪挂件访问麦克风。"
        case .inputUnavailable:
            return "当前没有可用的麦克风输入。"
        case .engineStartFailed(let error):
            return "无法启动麦克风音频输入：\(error.localizedDescription)"
        }
    }
}

final class AudioLevelMonitor {
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    var onLevel: ((Double) -> Void)?

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine(completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard granted else {
                        completion(.failure(AudioLevelMonitorError.permissionDenied))
                        return
                    }
                    self.startEngine(completion: completion)
                }
            }
        case .denied, .restricted:
            completion(.failure(AudioLevelMonitorError.permissionDenied))
        @unknown default:
            completion(.failure(AudioLevelMonitorError.permissionDenied))
        }
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
    }

    private func startEngine(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !engine.isRunning else {
            completion(.success(()))
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            completion(.failure(AudioLevelMonitorError.inputUnavailable))
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let frameCount = Int(buffer.frameLength)
            var sum: Double = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<frameCount {
                    let sample = Double(samples[frame])
                    sum += sample * sample
                }
            }
            let rms = sqrt(sum / Double(frameCount * Int(buffer.format.channelCount)))
            DispatchQueue.main.async { [weak self] in self?.onLevel?(rms) }
        }
        tapInstalled = true
        do {
            try engine.start()
            completion(.success(()))
        } catch {
            stop()
            completion(.failure(AudioLevelMonitorError.engineStartFailed(error)))
        }
    }
}
