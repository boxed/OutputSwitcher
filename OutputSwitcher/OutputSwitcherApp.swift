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

let audioDevices = AudioDevice.getAll()
let inputAudioDevices = audioDevices.filter { $0.type == .input }
let outputAudioDevices = audioDevices.filter { $0.type == .output }


@main
struct OutputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.close()
        }
        
        statusBar = StatusBarController.init()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

func setAudioDevice(id: Int) {
    guard let outputAudioDevice = outputAudioDevices.first(where: { $0.id == id }) else {
        print("The AudioDeviceID doesn't exist!")
        return
    }
        
    outputAudioDevice.setAsDefault()
}
  

class StatusBarController {
    private var statusBar: NSStatusBar
    private var lineOutItem: NSStatusItem
    private var headPhoneItem: NSStatusItem
    
    init() {
        do {
            let jsonEncodedData = try JSONEncoder().encode(audioDevices)
            let data = String(data: jsonEncodedData, encoding: .utf8)!
            
            print(data)
        }
        catch {
            
        }
        
        // 81 = RODE
        // 61 = line out

        statusBar = NSStatusBar.init()

        // Creating a status bar item having a fixed length
        headPhoneItem = statusBar.statusItem(withLength: 28.0)
        lineOutItem = statusBar.statusItem(withLength: 28.0)

        if let statusBarButton = headPhoneItem.button {
            statusBarButton.title = "🎧"

            statusBarButton.action = #selector(output_head_phones(sender:))
            statusBarButton.target = self
        }

        if let statusBarButton = lineOutItem.button {
            statusBarButton.title = "🔈"

            statusBarButton.action = #selector(output_line_out(sender:))
            statusBarButton.target = self
        }

        registerHotkey(keyCode: kVK_F16, id: 61)
        registerHotkey(keyCode: kVK_F17, id: 81)
    }
    
    @objc func output_line_out(sender: AnyObject) {
        setAudioDevice(id: 61)
    }

    @objc func output_head_phones(sender: AnyObject) {
        setAudioDevice(id: 81)
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


func registerHotkey(keyCode: Int, id: Int) {
    var hotKeyRef: EventHotKeyRef?
    let modifierFlags: UInt32 = getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags.command)

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
        
        NSLog("Command + R Released! %d", hkCom.id)

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
