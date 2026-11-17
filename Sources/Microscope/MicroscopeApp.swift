import AppKit
import AVFoundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MicroscopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var camera = CameraController()

    var body: some Scene {
        Window("Microscope", id: "main") {
            ContentView()
                .environmentObject(camera)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Capture Image") { camera.capture() }
                    .keyboardShortcut("s")
                Button("Show in Finder") { camera.showInFinder() }
                    .keyboardShortcut("r")
                Button("Choose Save Folder…") { camera.chooseFolder() }
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Image") { camera.copyToClipboard() }
                    .keyboardShortcut("c")
            }
            CommandMenu("Camera") {
                CameraMenu().environmentObject(camera)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(camera)
        }
    }
}

struct CameraMenu: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        ForEach(Array(camera.devices.enumerated()), id: \.element.uniqueID) { index, device in
            item(device, shortcut: index < 9 ? KeyEquivalent(Character(String(index + 1))) : nil)
        }
        if camera.devices.isEmpty { Text("No cameras connected") }
        Divider()
        Button("Automatic (prefer microscope)") { camera.preferredDeviceID = nil }
        Button("Rescan Devices") { camera.refreshDevices(forceTarget: true) }
    }

    private func item(_ device: AVCaptureDevice, shortcut: KeyEquivalent?) -> some View {
        let isOn = Binding<Bool>(
            get: { camera.currentDevice?.uniqueID == device.uniqueID },
            set: { if $0 { camera.select(device) } }
        )
        return Toggle(CameraController.displayName(device), isOn: isOn)
            .keyboardShortcut(shortcut.map { KeyboardShortcut($0) })
    }
}

struct SettingsView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Save folder") {
                    HStack {
                        Text(camera.saveFolder.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(camera.saveFolder.path)
                        Button("Choose…") { camera.chooseFolder() }
                    }
                }
                HStack {
                    Spacer()
                    Button("Reveal in Finder") { camera.showInFinder() }
                    Button("Reset to Default") { camera.resetSaveFolder() }
                        .disabled(camera.saveFolder == CameraController.defaultSaveFolder)
                }
                Picker("File format", selection: $camera.fileType) {
                    Text("PNG (lossless)").tag(ImageFileType.png)
                    Text("JPEG (smaller)").tag(ImageFileType.jpeg)
                }
            }
            Section {
                Picker("Default camera", selection: $camera.preferredDeviceID) {
                    Text("Automatic (prefer microscope)").tag(String?.none)
                    ForEach(camera.devices, id: \.uniqueID) { d in
                        Text(CameraController.displayName(d)).tag(Optional(d.uniqueID))
                    }
                    if let id = camera.preferredDeviceID,
                       !camera.devices.contains(where: { $0.uniqueID == id }) {
                        Text("Disconnected camera").tag(Optional(id))
                    }
                }
            } header: {
                Text("Camera")
            } footer: {
                Text("Opened on launch and whenever it is plugged back in. Choosing a camera in the main window or the Camera menu (⌘1…⌘9) also sets this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ContentView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if camera.permissionDenied {
                    permissionPrompt
                } else {
                    PreviewView(session: camera.session)
                    if camera.currentDevice == nil {
                        Text(camera.status).foregroundStyle(.secondary)
                    }
                }
                Color.white
                    .opacity(camera.flash ? 0.5 : 0)
                    .animation(.easeOut(duration: 0.25), value: camera.flash)
                    .allowsHitTesting(false)
            }
            Divider()
            controls
        }
    }

    /// Device name plus the size of frames actually arriving, e.g. "Microscope · live 3840×2160".
    private var statusText: String {
        guard let size = camera.frameSize,
              camera.status == camera.currentDevice.map(CameraController.displayName) else {
            return camera.status
        }
        return "\(camera.status) · live \(Int(size.width))×\(Int(size.height))"
    }

    private var permissionPrompt: some View {
        VStack(spacing: 12) {
            Text("Microscope needs camera access.").font(.headline)
            Button("Open Camera Privacy Settings") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
            }
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.macro")
                .foregroundStyle(.secondary)
                .help("Camera (also in the Camera menu, ⌘1…⌘9)")
            Picker("Camera", selection: Binding(
                get: { camera.currentDevice?.uniqueID ?? "" },
                set: { id in
                    if let d = camera.devices.first(where: { $0.uniqueID == id }) { camera.select(d) }
                }
            )) {
                if camera.currentDevice == nil { Text("None").tag("") }
                ForEach(camera.devices, id: \.uniqueID) { d in
                    Text(CameraController.displayName(d)).tag(d.uniqueID)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Picker("Resolution", selection: Binding(
                get: { camera.resolution },
                set: { camera.selectResolution($0) }
            )) {
                if camera.resolutions.isEmpty { Text("—").tag("") }
                ForEach(camera.resolutions, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)

            Picker("Format", selection: $camera.fileType) {
                ForEach(ImageFileType.allCases) { Text($0.rawValue.uppercased()).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { camera.showInFinder() } label: { Image(systemName: "folder") }
                .help("Show saved images (⌘R) — save folder: \(camera.saveFolder.path)")
            Button { camera.copyToClipboard() } label: { Image(systemName: "doc.on.doc") }
                .help("Copy current frame (⌘C)")
            Button { camera.capture() } label: { Label("Capture", systemImage: "camera.fill") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])
                .help("Save current frame (Space or ⌘S)")
        }
        .padding(10)
    }
}

/// Hosts an AVCaptureVideoPreviewLayer (GPU-backed, no per-frame SwiftUI work).
struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
