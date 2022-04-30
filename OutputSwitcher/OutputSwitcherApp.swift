//
//  OutputSwitcherApp.swift
//  OutputSwitcher
//
//  Created by Anders Hovmöller on 2022-04-12.
//

import Cocoa
import SwiftUI
import AppKit
import CoreAudio
import Carbon

let speakers = 1
let headphones = 2


@main
struct OutputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


var statusBar = NSStatusBar.init()
var statusBarItem = statusBar.statusItem(withLength: 28.0)
var headphonesSelector: Selector?
var speakersSelector: Selector?
let speakersName = "Realtek USB2.0 Audio"
let headphoneName = "RODE NT-USB"

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.close()
        }
        
        speakersSelector = #selector(output_speakers(sender:))
        headphonesSelector = #selector(output_headphones(sender:))

        registerHotkey(keyCode: kVK_F16, id: speakers, modifierFlags: 0)
        registerHotkey(keyCode: kVK_F17, id: headphones, modifierFlags: 0)
        
        let audioDevices = AudioDevice.getAll()
        let outputAudioDevices = audioDevices.filter { $0.type == .output }
        if let audioDevice = outputAudioDevices.first(where: { $0.isDefault}) {
            if audioDevice.name == headphoneName {
                self.output_headphones(sender: self)
            }
            else {
                self.output_speakers(sender: self)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    @objc func output_speakers(sender: AnyObject) {
        setAudioDevice(id: speakers)
    }

    @objc func output_headphones(sender: AnyObject) {
        setAudioDevice(id: headphones)
    }
}

func setAudioDevice(id: Int) {
    let audioDevices = AudioDevice.getAll()
    let outputAudioDevices = audioDevices.filter { $0.type == .output }

//    do {
//        let jsonEncodedData = try JSONEncoder().encode(audioDevices)
//        let data = String(data: jsonEncodedData, encoding: .utf8)!
//
//        print(data)
//    }
//    catch {
//    }
    
    let deviceName: String
    let title: String
    let selector: Selector
    
    switch id {
    case speakers:
        title = "🔈"
        selector = headphonesSelector!
        deviceName = speakersName
    case headphones:
        title = "🎧"
        selector = speakersSelector!
        deviceName = headphoneName
    default:
        print("Device not found!")
        return
    }
    
    if let statusBarButton = statusBarItem.button {
        statusBarButton.title = title
        statusBarButton.action = selector
    }
    
    if let audioDevice = outputAudioDevices.first(where: { $0.name == deviceName}) {
        audioDevice.setAsDefault()
    }
}
  

// https://github.com/hladik-dan/switch-audio
class AudioDevice: Encodable {
    enum AudioDeviceType: String, Encodable {
        case input
        case output
        case unknown
    }
    
    var id = AudioDeviceID()
    var name = String()
    var type = AudioDeviceType.unknown
    var isDefault = false
    
    init(id: AudioDeviceID) {
        self.id = id
        self.name = self.getName()
        self.type = self.getType()
        self.isDefault = self.checkIfIsDefault()
    }
    
    public static func getAll() -> [AudioDevice] {
        return self.getAudioDeviceIDs().map { audioDeviceID in AudioDevice(id: audioDeviceID) }
    }
    
    public func setAsDefault() -> Void {
        if (self.type == .unknown) {
            return
        }
        
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector:
                                                    self.type == .input
                                                    ? kAudioHardwarePropertyDefaultInputDevice
                                                    : kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope:
                                                    self.type == .input
                                                    ? kAudioObjectPropertyScopeInput
                                                    : kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        
        AudioObjectSetPropertyData(objectID,
                                   &address,
                                   0,
                                   nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size),
                                   &self.id)
    }
    
    private static func getAudioDeviceIDs() -> [AudioDeviceID] {
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32()
        AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)

        var data = (0 ..< Int(dataSize) / MemoryLayout<AudioDeviceID>.size).map { _ -> AudioDeviceID in
            return AudioDeviceID()
        }
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &data)
        
        return data;
    }
    
    private func getName() -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32()
        AudioObjectGetPropertyDataSize(self.id, &address, 0, nil, &dataSize)
        
        var data = [CChar](repeating: 0, count: 128)
        AudioObjectGetPropertyData(self.id, &address, 0, nil, &dataSize, &data)
        
        return String(cString: data)
    }
    
    private func getType() -> AudioDevice.AudioDeviceType {
        if (self.getNumberOfInputChannels() > 0) {
            return AudioDeviceType.input
        }
        
        if (self.getNumberOfOutputChannels() > 0) {
            return AudioDeviceType.output
        }
        
        return AudioDeviceType.unknown
    }
    
    private func getNumberOfInputChannels() -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32()
        AudioObjectGetPropertyDataSize(self.id, &address, 0, nil, &dataSize)
        
        let data = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        AudioObjectGetPropertyData(self.id, &address, 0, nil, &dataSize, data)
        
        return Int(UnsafeMutableAudioBufferListPointer(data).reduce(0) { $0 + $1.mNumberChannels })
    }
    
    private func getNumberOfOutputChannels() -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32()
        AudioObjectGetPropertyDataSize(self.id, &address, 0, nil, &dataSize)
        
        let data = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        AudioObjectGetPropertyData(self.id, &address, 0, nil, &dataSize, data)
        
        return Int(UnsafeMutableAudioBufferListPointer(data).reduce(0) { $0 + $1.mNumberChannels })
    }
    
    private func checkIfIsDefault() -> Bool {
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector:
                                                    self.type == .input
                                                    ? kAudioHardwarePropertyDefaultInputDevice
                                                    : kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size);
        var defaultAudioDeviceID = AudioDeviceID()
        
        AudioObjectGetPropertyData(objectID,
                                   &address,
                                   0,
                                   nil,
                                   &dataSize,
                                   &defaultAudioDeviceID)
        
        return self.id == defaultAudioDeviceID
    }
}

extension String {
  /// This converts string to UInt as a fourCharCode
  public var fourCharCodeValue: Int {
    var result: Int = 0
    if let data = self.data(using: String.Encoding.macOSRoman) {
      data.withUnsafeBytes({ (rawBytes) in
        let bytes = rawBytes.bindMemory(to: UInt8.self)
        for i in 0 ..< data.count {
          result = result << 8 + Int(bytes[i])
        }
      })
    }
    return result
  }
}

func getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = cocoaFlags.rawValue
    var newFlags: Int = 0

    if ((flags & NSEvent.ModifierFlags.control.rawValue) > 0) {
      newFlags |= controlKey
    }

    if ((flags & NSEvent.ModifierFlags.command.rawValue) > 0) {
      newFlags |= cmdKey
    }

    if ((flags & NSEvent.ModifierFlags.shift.rawValue) > 0) {
      newFlags |= shiftKey;
    }

    if ((flags & NSEvent.ModifierFlags.option.rawValue) > 0) {
      newFlags |= optionKey
    }

    if ((flags & NSEvent.ModifierFlags.capsLock.rawValue) > 0) {
      newFlags |= alphaLock
    }

    return UInt32(newFlags);
}


func registerHotkey(keyCode: Int, id: Int, modifierFlags: UInt32) {
    var hotKeyRef: EventHotKeyRef?

    var gMyHotKeyID = EventHotKeyID()
    gMyHotKeyID.id = UInt32(id)

    // Not sure what "swat" vs "htk1" do.
    gMyHotKeyID.signature = OSType("swat".fourCharCodeValue)
    // gMyHotKeyID.signature = OSType("htk1".fourCharCodeValue)

    var eventType = EventTypeSpec()
    eventType.eventClass = OSType(kEventClassKeyboard)
    eventType.eventKind = OSType(kEventHotKeyReleased)

    // Install handler.
    InstallEventHandler(GetApplicationEventTarget(), {
      (nextHanlder, theEvent, userData) -> OSStatus in
        var hkCom = EventHotKeyID()

        GetEventParameter(theEvent,
                          EventParamName(kEventParamDirectObject),
                          EventParamType(typeEventHotKeyID),
                          nil,
                          MemoryLayout<EventHotKeyID>.size,
                          nil,
                          &hkCom)
        
        setAudioDevice(id: Int(hkCom.id))
        return noErr
    }, 1, &eventType, nil, nil)

    // Register hotkey.
    let status = RegisterEventHotKey(UInt32(keyCode),
                                     modifierFlags,
                                     gMyHotKeyID,
                                     GetApplicationEventTarget(),
                                     0,
                                     &hotKeyRef)
    assert(status == noErr)
  }
