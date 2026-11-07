//
//  CoreMIDIController.swift
//  AI Music Studio
//

import Combine
import CoreMIDI
import Foundation

struct CoreMIDIDevice: Identifiable, Equatable {
    let id: MIDIEndpointRef
    let name: String
}

enum CoreMIDINoteEvent: Sendable {
    case noteOn(pitch: Int, velocity: Int, channel: Int)
    case noteOff(pitch: Int, channel: Int)
}

@MainActor
final class CoreMIDIController: ObservableObject {
    @Published private(set) var devices: [CoreMIDIDevice] = []
    @Published var selectedDeviceID: MIDIEndpointRef?
    @Published private(set) var isConnected = false
    @Published private(set) var statusMessage = "Connect a MIDI keyboard to begin."

    var onNoteEvent: ((CoreMIDINoteEvent) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSource = MIDIEndpointRef()

    func refreshDevices() {
#if targetEnvironment(simulator)
        devices = []
        selectedDeviceID = nil
        isConnected = false
        statusMessage = "MIDI controllers are unavailable in the Simulator."
        return
#else
        let sourceCount = MIDIGetNumberOfSources()
        var available: [CoreMIDIDevice] = []
        if sourceCount > 0 {
            for index in 0..<sourceCount {
                let endpoint = MIDIGetSource(index)
                guard endpoint != 0 else { continue }
                available.append(CoreMIDIDevice(id: endpoint, name: displayName(for: endpoint)))
            }
        }
        devices = available

        if let selectedDeviceID, !available.contains(where: { $0.id == selectedDeviceID }) {
            disconnect()
            self.selectedDeviceID = nil
        }
        if selectedDeviceID == nil {
            selectedDeviceID = available.first?.id
        }
        if !isConnected {
            statusMessage = available.isEmpty
                ? "No MIDI controller found. Connect a device and refresh."
                : "Ready to connect to a MIDI controller."
        }
#endif
    }

    func connectSelectedDevice() {
#if targetEnvironment(simulator)
        statusMessage = "MIDI controllers are unavailable in the Simulator."
        return
#else
        guard let selectedDeviceID,
              let device = devices.first(where: { $0.id == selectedDeviceID }) else {
            statusMessage = "Choose an available MIDI input first."
            return
        }
        guard createClientIfNeeded() else { return }

        if inputPort == 0 {
            let status = MIDIInputPortCreateWithBlock(
                client,
                "Instrument MIDI Input" as CFString,
                &inputPort
            ) { [weak self] packetList, _ in
                let events = Self.noteEvents(from: packetList)
                for event in events {
                    Task { @MainActor [weak self] in
                        self?.onNoteEvent?(event)
                    }
                }
            }
            guard status == noErr else {
                statusMessage = "The MIDI input port could not be opened (\(status))."
                inputPort = 0
                return
            }
        }

        disconnectSourceOnly()
        let status = MIDIPortConnectSource(inputPort, device.id, nil)
        guard status == noErr else {
            statusMessage = "Could not connect to \(device.name) (\(status))."
            return
        }
        connectedSource = device.id
        isConnected = true
        statusMessage = "Receiving from \(device.name)."
#endif
    }

    func disconnect() {
        disconnectSourceOnly()
        isConnected = false
        statusMessage = devices.isEmpty
            ? "No MIDI controller found. Connect a device and refresh."
            : "MIDI controller disconnected."
    }

    private func disconnectSourceOnly() {
        guard connectedSource != 0, inputPort != 0 else { return }
        MIDIPortDisconnectSource(inputPort, connectedSource)
        connectedSource = 0
        isConnected = false
    }

    private func createClientIfNeeded() -> Bool {
        guard client == 0 else { return true }
        let status = MIDIClientCreate("AI Music Studio" as CFString, nil, nil, &client)
        guard status == noErr else {
            statusMessage = "Core MIDI could not start (\(status))."
            return false
        }
        return true
    }

    private func displayName(for endpoint: MIDIEndpointRef) -> String {
        var property: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)
        guard status == noErr, let property else { return "MIDI Controller" }
        return property.takeRetainedValue() as String
    }

    nonisolated private static func noteEvents(from packetList: UnsafePointer<MIDIPacketList>) -> [CoreMIDINoteEvent] {
        var result: [CoreMIDINoteEvent] = []
        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(Int(packet.length)))
            }
            var offset = 0
            while offset + 2 < bytes.count {
                let status = bytes[offset]
                let kind = status & 0xF0
                let channel = Int(status & 0x0F)
                let pitch = Int(bytes[offset + 1] & 0x7F)
                let velocity = Int(bytes[offset + 2] & 0x7F)

                if kind == 0x90 {
                    if velocity == 0 {
                        result.append(.noteOff(pitch: pitch, channel: channel))
                    } else {
                        result.append(.noteOn(pitch: pitch, velocity: velocity, channel: channel))
                    }
                    offset += 3
                } else if kind == 0x80 {
                    result.append(.noteOff(pitch: pitch, channel: channel))
                    offset += 3
                } else {
                    offset += kind == 0xC0 || kind == 0xD0 ? 2 : 3
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }

        return result
    }
}
