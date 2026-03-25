import CoreAudio
import Observation
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uniqueID: String
    let name: String
}

@Observable
final class AudioDeviceManager {
    var inputDevices: [AudioInputDevice] = []
    var selectedDeviceUID: String? {
        didSet {
            UserDefaults.standard.set(selectedDeviceUID, forKey: "selectedAudioInputDeviceUID")
        }
    }

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    var resolvedDeviceID: AudioDeviceID? {
        guard let uid = selectedDeviceUID else { return nil }
        return inputDevices.first(where: { $0.uniqueID == uid })?.id
    }

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedAudioInputDeviceUID")
        refreshDevices()
        installDeviceChangeListener()
    }

    deinit {
        removeDeviceChangeListener()
    }

    func refreshDevices() {
        inputDevices = Self.enumerateInputDevices()
    }

    // MARK: - CoreAudio Enumeration

    private static func enumerateInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            // Check if device has input channels
            guard inputChannelCount(for: deviceID) > 0 else { return nil }

            guard let name = deviceName(for: deviceID),
                  let uniqueID = deviceUniqueID(for: deviceID) else { return nil }

            return AudioInputDevice(id: deviceID, uniqueID: uniqueID, name: name)
        }
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard result == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var namePtr: UnsafeRawPointer? = nil
        var dataSize = UInt32(MemoryLayout<UnsafeRawPointer>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &namePtr)
        guard status == noErr, let rawPtr = namePtr else { return nil }

        return Unmanaged<CFString>.fromOpaque(rawPtr).takeRetainedValue() as String
    }

    private static func deviceUniqueID(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uidPtr: UnsafeRawPointer? = nil
        var dataSize = UInt32(MemoryLayout<UnsafeRawPointer>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uidPtr)
        guard status == noErr, let rawPtr = uidPtr else { return nil }

        return Unmanaged<CFString>.fromOpaque(rawPtr).takeRetainedValue() as String
    }

    // MARK: - Device Change Monitoring

    private func installDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceChangeListener() {
        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
        listenerBlock = nil
    }
}
