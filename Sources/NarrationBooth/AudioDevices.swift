import CoreAudio
import Foundation

/// Core Audio helpers: map a capture device to its Core Audio device, read its sample rate, and read/set the
/// device's own input volume (the "mic gain").
enum AudioDevices {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Core Audio device for an AVCaptureDevice.uniqueID (the same string as the device's kAudioDevicePropertyDeviceUID).
    static func coreAudioID(uid: String) -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids {
            var a = address(kAudioDevicePropertyDeviceUID)
            var u: Unmanaged<CFString>?
            var sz = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &sz, &u) == noErr, let v = u?.takeRetainedValue() as String?, v == uid {
                return id
            }
        }
        return nil
    }

    static func sampleRate(_ id: AudioDeviceID) -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate) == noErr ? rate : 0
    }

    /// Input volume (0…1) on the main element, or channel 1 when the device only exposes per-channel volume.
    private static func volumeElement(_ id: AudioDeviceID) -> AudioObjectPropertyElement? {
        for el in [kAudioObjectPropertyElementMain, 1] {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, el)
            if AudioObjectHasProperty(id, &addr) { return el }
        }
        return nil
    }

    static func inputVolume(_ id: AudioDeviceID) -> Float? {
        guard let el = volumeElement(id) else { return nil }
        var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, el)
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func canSetInputVolume(_ id: AudioDeviceID) -> Bool {
        guard let el = volumeElement(id) else { return false }
        var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, el)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    static func setInputVolume(_ id: AudioDeviceID, _ value: Float) {
        guard let el = volumeElement(id) else { return }
        var v = Float32(max(0, min(1, value)))
        for e in el == kAudioObjectPropertyElementMain ? [el] : [1, 2] {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, e)
            if AudioObjectHasProperty(id, &addr) {
                AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            }
        }
    }
}
