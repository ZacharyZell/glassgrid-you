import AppKit
import CoreAudio
import Foundation
import YouTubeMacCore

/// Reasons the system playback guard can automatically pause active videos.
public enum SystemAutoPauseReason: String, Sendable {
    case screenSleep
    case systemSleep
    case screenLocked
    case audioDisconnected
}

/// Low-level Swift 6–safe CoreAudio output route listener that owns all mutable CoreAudio state
/// on a private serial queue and passes identical `AudioObjectPropertyListenerBlock` references
/// when adding and removing listeners.
private final class CoreAudioOutputListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.glassgridyou.mac.coreaudio-listener", qos: .utility)
    private var isStarted = false
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var dataSourceBlock: AudioObjectPropertyListenerBlock?
    private var lastSnapshot: AudioRouteSnapshot?
    private var onDisconnect: (@Sendable () -> Void)?

    func start(onDisconnect: @escaping @Sendable () -> Void) {
        queue.sync {
            guard !isStarted else { return }
            isStarted = true
            self.onDisconnect = onDisconnect

            let initial = Self.readCurrentSnapshot()
            self.lastSnapshot = initial

            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.handleRouteChangeOnQueue()
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddr,
                queue,
                defaultBlock
            )
            if status == noErr {
                self.defaultDeviceBlock = defaultBlock
            }

            if let initial, initial.deviceID != AudioDeviceID(kAudioObjectUnknown) {
                installDataSourceListenerOnQueue(for: initial.deviceID)
            }
        }
    }

    func stop() {
        queue.sync {
            teardownOnQueue()
        }
    }

    deinit {
        queue.sync {
            teardownOnQueue()
        }
    }

    private func teardownOnQueue() {
        guard isStarted else { return }
        isStarted = false
        onDisconnect = nil

        if let block = defaultDeviceBlock {
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddr,
                queue,
                block
            )
            defaultDeviceBlock = nil
        }

        removeDataSourceListenerOnQueue()
        lastSnapshot = nil
    }

    private func installDataSourceListenerOnQueue(for deviceID: AudioDeviceID) {
        removeDataSourceListenerOnQueue()
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return }

        var dataSourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &dataSourceAddr) else {
            return
        }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleRouteChangeOnQueue()
        }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &dataSourceAddr, queue, block)
        if status == noErr {
            observedDeviceID = deviceID
            dataSourceBlock = block
        }
    }

    private func removeDataSourceListenerOnQueue() {
        guard let block = dataSourceBlock, observedDeviceID != AudioDeviceID(kAudioObjectUnknown) else {
            dataSourceBlock = nil
            observedDeviceID = AudioDeviceID(kAudioObjectUnknown)
            return
        }
        var dataSourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(observedDeviceID, &dataSourceAddr, queue, block)
        dataSourceBlock = nil
        observedDeviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    private func handleRouteChangeOnQueue() {
        guard isStarted, let current = Self.readCurrentSnapshot() else { return }
        if current.deviceID != observedDeviceID {
            installDataSourceListenerOnQueue(for: current.deviceID)
        }

        let shouldPause = AudioOutputDisconnectDetector.shouldAutoPause(from: lastSnapshot, to: current)
        lastSnapshot = current
        if shouldPause {
            onDisconnect?()
        }
    }

    private static func readCurrentSnapshot() -> AudioRouteSnapshot? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(deviceID, &transportAddr, 0, nil, &transportSize, &transportType)

        var dataSource: UInt32 = 0
        var dataSourceSize = UInt32(MemoryLayout<UInt32>.size)
        var dataSourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &dataSourceAddr) {
            let dsStatus = AudioObjectGetPropertyData(deviceID, &dataSourceAddr, 0, nil, &dataSourceSize, &dataSource)
            if dsStatus != noErr {
                dataSource = 0
            }
        }

        return AudioRouteSnapshot(
            deviceID: deviceID,
            transportType: transportType,
            dataSource: dataSource
        )
    }
}

/// Coordinates macOS screen lock, display/system sleep, and CoreAudio output disconnect auto-pause signals.
@MainActor
final class SystemPlaybackGuard {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?
    private let audioListener = CoreAudioOutputListener()
    private var isRunning = false

    func start(onAutoPause: @escaping @MainActor (SystemAutoPauseReason) -> Void) {
        guard !isRunning else { return }
        isRunning = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    onAutoPause(.screenSleep)
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    onAutoPause(.systemSleep)
                }
            }
        ]

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onAutoPause(.screenLocked)
            }
        }

        audioListener.start {
            Task { @MainActor in
                onAutoPause(.audioDisconnected)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            workspaceCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()

        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }

        audioListener.stop()
    }
}
