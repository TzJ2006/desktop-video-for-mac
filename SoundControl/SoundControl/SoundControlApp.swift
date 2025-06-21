//
//  SoundControlApp.swift
//  SoundControl
//
//  Created by 汤子嘉 on 6/17/25.
//

//  WARNING  ▸
//  Boosting volume above 100 % applies software gain which will clip/distort on
//  consumer hardware.  Offer a preference to *enable* boost instead of turning
//  it on by default!

import SwiftUI
import CoreAudio
import Combine
import AudioToolbox
import AVFoundation

// MARK: – App entry‑point
@main
struct AudioMixerMenuBarApp: App {
    // Keep an AppDelegate around if you need Core Audio callbacks before UI
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra(NSLocalizedString("Mixer", comment: "菜单栏标题")) {
            MixerView()
        }
        .menuBarExtraStyle(.window) // gives us the detachable pop‑over style
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = DeviceManager.shared // kick it so listeners are registered early
    }
}

// MARK: – Model objects
struct AudioDevice: Identifiable {
    var id: AudioDeviceID
    var name: String
    var isOutput: Bool
    var isInput: Bool
    var volume: Float32 // 0.0 … 1.0
}

struct AppAudio: Identifiable {
    var id: pid_t
    var name: String
    var bundleID: String
    var icon: NSImage?
    var volume: Float32  // 0.0 … 4.0 (allowing ⇡ ⇡ ⇡ 400 %)
    var isBoosted: Bool  { volume > 1.0 }
}

// MARK: – Core Audio device management
final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputDevices:  [AudioDevice] = []
    @Published var defaultOutputID: AudioDeviceID = 0
    @Published var defaultInputID: AudioDeviceID = 0

    private var propertyQueue = DispatchQueue(label: "com.example.mixer.ca")

    private init() {
        refreshDeviceList()
        listenForHardwareChanges()
    }

    func setDefaultOutput(deviceID: AudioDeviceID) {
        var id = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: id)),
            &id)
        if status != noErr {
            print("⚠️ Failed to set default output: \(status)")
        }
        defaultOutputID = deviceID
    }

    func setDeviceVolume(id: AudioDeviceID, volume: Float) {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(
            id, &address, 0, nil,
            UInt32(MemoryLayout.size(ofValue: vol)), &vol)
        if status != noErr { print("⚠️ Cannot set volume: \(status)") }
        refreshDeviceList()
    }

    // MARK: – Private helpers
    private func refreshDeviceList() {
        // Update default I/O device IDs
        var outID = AudioDeviceID(0)
        var addrOut = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var sizeID = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addrOut, 0, nil, &sizeID, &outID)

        var inID = AudioDeviceID(0)
        var addrIn = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addrIn, 0, nil, &sizeID, &inID)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        var outs: [AudioDevice] = []
        var ins:  [AudioDevice] = []
        for id in deviceIDs {
            // Fetch device name
            var name: CFString = "Unknown" as CFString
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let namePtr = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
            defer { namePtr.deallocate() }
            let status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, namePtr)
            guard status == noErr, let fetched = namePtr.pointee else {
                continue
            }
            name = fetched
            // Determine IO capabilities
            var outputStreams: UInt32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: outputStreams))
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &size)
            let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
            defer { bufList.deallocate() }
            _ = AudioObjectGetPropertyData(id, &streamsAddress, 0, nil, &size, bufList)
            outputStreams = bufList.pointee.mNumberBuffers

            var inputStreams: UInt32 = 0
            streamsAddress.mScope = kAudioDevicePropertyScopeInput
            size = UInt32(MemoryLayout.size(ofValue: inputStreams))
            _ = AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &size)
            let inBufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
            defer { inBufList.deallocate() }
            _ = AudioObjectGetPropertyData(id, &streamsAddress, 0, nil, &size, inBufList)
            inputStreams = inBufList.pointee.mNumberBuffers

            // Volume
            var vol: Float32 = 0
            var volSize = UInt32(MemoryLayout.size(ofValue: vol))
            var volAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(id, &volAddress, 0, nil, &volSize, &vol)

            let device = AudioDevice(id: id, name: name as String, isOutput: outputStreams > 0, isInput: inputStreams > 0, volume: vol)
            if device.isOutput { outs.append(device) }
            if device.isInput  { ins.append(device)  }
        }
        DispatchQueue.main.async {
            self.defaultOutputID = outID
            self.defaultInputID = inID
            self.outputDevices = outs
            self.inputDevices  = ins
        }
    }

    private func listenForHardwareChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let callback: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDeviceList()
//            return noErr
            return;
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, propertyQueue, callback)
    }
}

// MARK: – Per-application mixer (using AVAudioEngine taps)
final class AppAudioManager: ObservableObject {
    static let shared = AppAudioManager()
    @Published private(set) var apps: [AppAudio] = []

    private let engine = AVAudioEngine()
    private let systemTap = AVAudioMixerNode()
    private var processNodes: [pid_t: AVAudioMixerNode] = [:]

    private init() {
        setupAudioEngine()
        discoverAudioProcesses()
    }

    private func setupAudioEngine() {
        // 连接混音节点以截取系统输出
        engine.attach(systemTap)
        let mainMixer = engine.mainMixerNode
        engine.connect(systemTap, to: mainMixer, format: nil)
        do {
            try engine.start()
        } catch {
            print("⚠️ Failed to start AVAudioEngine:", error)
        }
        dlog("Audio engine started", level: .info)
        // TODO: 在 systemTap 上添加 tap，按应用拆分系统音频流
    }

    private func discoverAudioProcesses() {
        dlog("discoverAudioProcesses", level: .info)
        // TODO: 查询正在输出音频的进程 (AudioObject + kAudioHardwarePropertyProcessIsAudioProcess)
        //       为每个 PID 创建 mixer node 并通过 tap bus 连接到 systemTap
        // 示例代码：
        let audioPIDs: [pid_t] = [] // fill via AudioObject APIs
        for pid in audioPIDs {
            let node = AVAudioMixerNode()
            engine.attach(node)
            engine.connect(node, to: systemTap, format: nil)
            processNodes[pid] = node
            // Initialize AppAudio entry
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "PID \(pid)"
            let icon = NSRunningApplication(processIdentifier: pid)?.icon
            let audio = AppAudio(id: pid, name: appName, bundleID: "", icon: icon, volume: 1.0)
            apps.append(audio)
        }
    }

    func setVolume(for pid: pid_t, to newValue: Float32) {
        // 软件增益最高可达 4×
        dlog("setVolume pid=\(pid) newValue=\(newValue)", level: .debug)
        let gain = min(max(newValue, 0), 4)
        if let node = processNodes[pid] {
            node.volume = gain
        }
        if let idx = apps.firstIndex(where: { $0.id == pid }) {
            apps[idx].volume = gain
        }
    }
}

// MARK: – SwiftUI Views
struct MixerView: View {
    @ObservedObject var devices = DeviceManager.shared
    @ObservedObject var apps    = AppAudioManager.shared

    var body: some View {
        ScrollView {
            systemSection
            Divider().padding(.vertical, 4)
            applicationsSection
        }
        .frame(width: 350, alignment: .leading)
        .padding()
    }

    // ––– System I/O –––
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Out:") .bold()
                Text(devices.outputDevices.first(where: { $0.id == devices.defaultOutputID })?.name ?? "None")
                Spacer()
                Button {
                    devices.setDeviceVolume(id: devices.defaultOutputID, volume: 0)
                } label: {
                    Image(systemName: "speaker.slash.fill")
                }.buttonStyle(.plain)
            }
            HStack {
                Text("In:") .bold()
                Text(devices.inputDevices.first(where: { $0.id == devices.defaultInputID })?.name ?? "None")
                Spacer()
                // optional: you could add mute on input if desired
            }
            Divider()
            Text("System").font(.headline)
            ForEach(devices.outputDevices) { device in
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Text(device.name).lineLimit(1)
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(device.volume) },
                        set: { devices.setDeviceVolume(id: device.id, volume: Float($0)) }),
                           in: 0...1)
                    Text("\(Int(device.volume * 100))%")
                        .frame(width: 40, alignment: .trailing)
                    if DeviceManager.shared.defaultOutputID == device.id {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    }
                    Button {
                        devices.setDefaultOutput(deviceID: device.id)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ––– Running apps –––
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applications").font(.headline)
            if apps.apps.isEmpty {
                Text("No active audio streams").foregroundColor(.secondary)
            }
            ForEach(apps.apps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16).cornerRadius(3)
                    }
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(app.volume) },
                        set: { newVol in
                            let clipped = min(max(Float32(newVol), 0), 4)
                            apps.setVolume(for: app.id, to: clipped)
                        }),
                           in: 0...4)
                    Button {
                        let boosted = app.volume <= 1.0 ? min(app.volume * 4, 4) : app.volume / 4
                        apps.setVolume(for: app.id, to: boosted)
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(app.isBoosted ? .accentColor : .secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
