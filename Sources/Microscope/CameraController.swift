import AppKit
import AVFoundation
import CoreImage

enum ImageFileType: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// Owns the capture session: picks the microscope, follows hot-plug events,
/// keeps the most recent frame around so snapshots are full sensor resolution.
final class CameraController: NSObject, ObservableObject {
    /// AVFoundation modelID of the USB microscope ("GENERAL - UVC", 0x1B3F:0x2002).
    static let microscopeModelID = "VendorID_6975 ProductID_8194"

    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var currentDevice: AVCaptureDevice?
    @Published private(set) var resolutions: [String] = []
    @Published private(set) var resolution: String = ""
    @Published private(set) var status = "Starting…"
    @Published private(set) var permissionDenied = false
    @Published private(set) var lastSaved: URL?
    @Published private(set) var flash = false
    /// Pixel size of the frames actually arriving (what a snapshot will be).
    @Published private(set) var frameSize: CGSize?

    /// Camera to open on launch / reconnect. nil = automatic (the microscope if present).
    @Published var preferredDeviceID: String? {
        didSet {
            defaults.set(preferredDeviceID, forKey: "deviceID")
            refreshDevices(forceTarget: true)
        }
    }

    @Published var fileType: ImageFileType {
        didSet { defaults.set(fileType.rawValue, forKey: "fileType") }
    }
    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: "saveFolder") }
    }

    let session = AVCaptureSession()
    private let defaults = UserDefaults.standard
    private let sessionQueue = DispatchQueue(label: "microscope.session")
    private let videoQueue = DispatchQueue(label: "microscope.video")
    private let output = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var formatsByLabel: [String: AVCaptureDevice.Format] = [:]
    /// Device we hold a configuration lock on (only touched on sessionQueue).
    private var lockedDevice: AVCaptureDevice?

    override init() {
        fileType = ImageFileType(rawValue: UserDefaults.standard.string(forKey: "fileType") ?? "") ?? .png
        saveFolder = UserDefaults.standard.string(forKey: "saveFolder")
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultSaveFolder
        preferredDeviceID = UserDefaults.standard.string(forKey: "deviceID")
        super.init()

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)

        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshDevices() }
        }
        start()
    }

    // MARK: - Permission & device discovery

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            refreshDevices()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.refreshDevices() } else { self.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
            status = "Camera access denied"
        }
    }

    static let defaultSaveFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Microscope", isDirectory: true)

    static func isMicroscope(_ d: AVCaptureDevice) -> Bool { d.modelID.contains(microscopeModelID) }

    static func displayName(_ d: AVCaptureDevice) -> String {
        isMicroscope(d) ? "Microscope" : d.localizedName
    }

    /// Re-scan cameras and pick which one to show. Order of preference:
    /// the camera the user explicitly chose → the current one → the microscope → anything.
    /// `forceTarget` re-evaluates even if the current camera is still connected.
    func refreshDevices(forceTarget: Bool = false) {
        guard !permissionDenied else { return }
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices.filter(\.isConnected)

        let byID = { (id: String?) in self.devices.first { $0.uniqueID == id } }
        let target = byID(preferredDeviceID)
            ?? (forceTarget ? nil : byID(currentDevice?.uniqueID))
            ?? devices.first(where: Self.isMicroscope)
            ?? devices.first

        if let target {
            if target.uniqueID != currentDevice?.uniqueID { select(target, remember: false) }
        } else {
            currentDevice = nil
            resolutions = []
            resolution = ""
            clearFrame()
            sessionQueue.async {
                self.session.inputs.forEach(self.session.removeInput)
                self.releaseLock()
            }
            status = "No camera connected — plug in the microscope"
        }
    }

    // MARK: - Selection

    func select(_ device: AVCaptureDevice, remember: Bool = true) {
        if remember, preferredDeviceID != device.uniqueID {
            preferredDeviceID = device.uniqueID  // didSet re-runs selection
            return
        }

        // One entry per resolution, largest first.
        formatsByLabel = [:]
        var labels: [(String, Int32)] = []
        for f in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            let label = "\(d.width)×\(d.height)"
            if formatsByLabel[label] == nil {
                formatsByLabel[label] = f
                labels.append((label, d.width * d.height))
            }
        }
        resolutions = labels.sorted { $0.1 > $1.1 }.map(\.0)

        let saved = defaults.string(forKey: "resolution-\(device.uniqueID)")
        resolution = resolutions.contains(saved ?? "") ? saved! : (resolutions.first ?? "")
        currentDevice = device
        configure(device: device, format: formatsByLabel[resolution])
    }

    func selectResolution(_ label: String) {
        guard let device = currentDevice, let format = formatsByLabel[label] else { return }
        defaults.set(label, forKey: "resolution-\(device.uniqueID)")
        resolution = label
        configure(device: device, format: format)
    }

    private func configure(device: AVCaptureDevice, format: AVCaptureDevice.Format?) {
        status = "Opening \(Self.displayName(device))…"
        clearFrame()
        sessionQueue.async {
            let s = self.session
            s.beginConfiguration()
            s.inputs.forEach(s.removeInput)
            self.releaseLock()
            if !s.outputs.contains(self.output), s.canAddOutput(self.output) { s.addOutput(self.output) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard s.canAddInput(input) else {
                    throw NSError(domain: "Microscope", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "the camera is busy or unsupported"])
                }
                s.addInput(input)
                // On macOS the session re-applies its preset (1080p for this camera) whenever
                // its topology changes — e.g. when the preview layer attaches — overriding
                // activeFormat. Holding the configuration lock while in use prevents that.
                try device.lockForConfiguration()
                self.lockedDevice = device
                if let format { device.activeFormat = format }
                s.commitConfiguration()
                if !s.isRunning { s.startRunning() }
                DispatchQueue.main.async { self.status = Self.displayName(device) }
            } catch {
                s.commitConfiguration()
                DispatchQueue.main.async {
                    self.status = "Couldn't open \(device.localizedName): \(error.localizedDescription)"
                }
            }
        }
    }

    private func releaseLock() {
        lockedDevice?.unlockForConfiguration()
        lockedDevice = nil
    }

    // MARK: - Frames

    private func clearFrame() {
        frameLock.lock(); latestFrame = nil; frameLock.unlock()
        frameSize = nil
    }

    private func currentImage() -> CIImage? {
        frameLock.lock(); defer { frameLock.unlock() }
        return latestFrame.map { CIImage(cvPixelBuffer: $0) }
    }

    func capture() {
        guard let image = currentImage() else {
            NSSound.beep()
            status = "No image yet — is the microscope connected?"
            return
        }
        flash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flash = false }

        let folder = saveFolder
        let type = fileType
        let stamp = Self.timestampFormatter.string(from: Date())
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("microscope_\(stamp).\(type.fileExtension)")
                guard let data = self.encode(image, as: type) else {
                    throw NSError(domain: "Microscope", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "image encoding failed"])
                }
                try data.write(to: url, options: .withoutOverwriting)
                DispatchQueue.main.async {
                    self.lastSaved = url
                    self.status = "Saved \(url.lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async { self.status = "Save failed: \(error.localizedDescription)" }
            }
        }
    }

    func copyToClipboard() {
        guard let image = currentImage(), let data = encode(image, as: .png) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
        status = "Copied image to clipboard"
    }

    private func encode(_ image: CIImage, as type: ImageFileType) -> Data? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        switch type {
        case .png:
            return ciContext.pngRepresentation(of: image, format: .RGBA8, colorSpace: sRGB)
        case .jpeg:
            let q = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]
            return ciContext.jpegRepresentation(of: image, colorSpace: sRGB, options: q)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return f
    }()

    // MARK: - Folder

    func showInFinder() {
        if let lastSaved, FileManager.default.fileExists(atPath: lastSaved.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastSaved])
        } else {
            try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(saveFolder)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveFolder
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url }
    }

    func resetSaveFolder() { saveFolder = Self.defaultSaveFolder }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock(); latestFrame = pb; frameLock.unlock()
        let size = CGSize(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        DispatchQueue.main.async {
            if self.frameSize != size {
                NSLog("Frame size now %d×%d", Int(size.width), Int(size.height))
                self.frameSize = size
            }
        }
    }
}
