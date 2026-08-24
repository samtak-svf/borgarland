import SwiftUI
import UIKit
import AVFoundation
import BorgarlandCore

/// The app opens here. The camera is the entry point and there is no path
/// that starts with a form (decision 0004). A captured photo is resolved to
/// a coordinate: EXIF GPS first, device fix as fallback, and no way forward
/// without one (the guard the city does not have).
struct CameraScreen: View {
    @ObservedObject var model: ReportModel
    @StateObject private var camera = CameraController()
    @State private var cameraAuthorized = false

    /// Icelandic takes the singular for any count ending in 1 except 11, so
    /// 21 reports is "21 ábending bíður" and 11 is "11 ábendingar bíða". A
    /// count-is-one test would get both wrong.
    private static func isSingular(_ count: Int) -> Bool {
        count % 10 == 1 && count % 100 != 11
    }

    private static func waitingLine(count: Int) -> String {
        isSingular(count)
            ? "\(count) ábending bíður sendingar."
            : "\(count) ábendingar bíða sendingar."
    }

    private static func discardLabel(count: Int) -> String {
        isSingular(count) ? "Eyða ábendingunni" : "Eyða þeim öllum"
    }

    var body: some View {
        let state = model.state
        VStack(spacing: 0) {
            Text("Borgarland")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(16)

            // Reports waiting to be sent (#73). This is the only place a
            // queued report is visible once someone has pressed Byrja aftur,
            // so it carries both controls: try now, or throw it away.
            if state.queuedCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.waitingLine(count: state.queuedCount))
                        .font(.footnote)
                    HStack(spacing: 16) {
                        Button("Senda núna") {
                            model.deliverQueued()
                        }
                        .disabled(state.sending)
                        Button(Self.discardLabel(count: state.queuedCount), role: .destructive) {
                            model.discardAllQueued()
                        }
                    }
                    .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if let photoError = state.photoError {
                Text(photoError)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            if state.photo == nil {
                cameraBody(state: state)
            } else {
                capturedPhotoBody(state: state)
            }
        }
        .onAppear {
            camera.onPhotoCaptured = { data, captureElapsedMs in
                Task { @MainActor in
                    model.onPhotoCaptured(bytes: data, rotationDegrees: 0, captureElapsedMs: captureElapsedMs)
                }
            }
            camera.onPhotoError = { message in
                Task { @MainActor in
                    model.onPhotoError(message)
                }
            }
        }
        .task {
            // The Kotlin checks permission on first composition without
            // prompting; the prompt comes from the button below. Same here:
            // no dialog on first launch. The observed state is the camera
            // permission event — a person who has already denied still gets
            // counted, which is exactly the friction the channel measures.
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            Telemetry.shared.track(.cameraPermission(granted: status == .authorized))
            if status == .authorized {
                cameraAuthorized = true
                startCamera()
            }
        }
        .onChange(of: cameraAuthorized) { _, granted in
            if granted { startCamera() }
        }
        .task(id: model.state.needsLocationPermission) {
            // The Kotlin's LaunchedEffect(state.needsLocationPermission): a
            // photo with no usable EXIF GPS flips this flag, the permission
            // dance runs once, and the result lands in the model through the
            // same callback the Android launcher uses.
            guard model.state.needsLocationPermission else { return }
            // No `locationPermissionAsked` here. This flag is true for every
            // photo with no usable EXIF GPS, which our own capture path never
            // writes, so emitting from here recorded a dialog on every report
            // after the first answered one (#139). DeviceFix emits it from the
            // branch that actually prompts.
            let granted = await DeviceFix.shared.requestWhenInUseAuthorization()
            let standing = LocationPermission.of(granted: granted, canAskAgain: !DeviceFix.shared.isDenied)
            model.onLocationPermissionResult(granted, permanentlyDenied: standing == .deniedForGood)
        }
        .onChange(of: model.state.photo != nil) { _, hasPhoto in
            // The Kotlin unbinds the camera when the preview leaves
            // composition; stop the session while the photo is reviewed,
            // restart it on retake.
            if hasPhoto {
                camera.stop()
            } else if cameraAuthorized {
                camera.start()
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func cameraBody(state: ReportUiState) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if cameraAuthorized {
                    CameraPreview(session: camera.session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Taktu mynd af því sem þú sérð. Staðsetningin kemur úr myndinni, annars úr tækinu.")
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            if !cameraAuthorized {
                Button("Veita aðgang að myndavélinni") {
                    requestCameraAccess()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(16)
            } else {
                Button("Taka mynd") {
                    camera.capture()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(16)
                .disabled(!camera.isConfigured)
            }
        }
    }

    private func capturedPhotoBody(state: ReportUiState) -> some View {
        VStack {
            if let photo = state.photo, let image = PhotoBytes.image(from: photo.bytes) {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if state.locating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Myndin ber enga GPS staðsetningu. Sæki staðsetningu úr tækinu...")
                }
                .padding(16)
            } else if let locationError = state.locationError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(locationError)
                        .foregroundStyle(.red)
                    HStack(spacing: 8) {
                        // Through the tested decision rather than around it
                        // (#89): the screen asked `state.locationDenied`
                        // directly, so the extraction was pinned by tests the
                        // app itself did not use.
                        let standing: LocationPermission =
                            state.locationDenied ? .deniedForGood : .unanswered
                        if standing.exit == .openSystemSettings {
                            // The system does not prompt twice, so Reyna aftur
                            // would return the same refusal forever — the field
                            // test pressed it and got exactly that (#76). The
                            // only place the decision can be undone is Settings,
                            // so that is the button.
                            Button("Opna stillingar") { openSystemSettings() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Reyna aftur") { requestDeviceFixOrPermission() }
                                .buttonStyle(.borderedProminent)
                        }
                        Button("Taka nýja mynd") { model.retakePhoto() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if state.coordinate != nil {
                Text("Staðsetning: \(state.locationSource ?? "")")
                    .padding(16)
            }
        }
    }

    private func requestCameraAccess() {
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraAuthorized = true
                Telemetry.shared.track(.cameraPermission(granted: true))
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraAuthorized = granted
                Telemetry.shared.track(.cameraPermission(granted: granted))
            default:
                cameraAuthorized = false
                Telemetry.shared.track(.cameraPermission(granted: false))
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestDeviceFixOrPermission() {
        // Kotlin: if fine location is already granted, go straight to the
        // fix; otherwise run the permission launcher. DeviceFix owns the
        // CoreLocation equivalent of that launcher.
        if DeviceFix.shared.isAuthorized {
            Telemetry.shared.track(.locationPermission(granted: true))
            model.requestDeviceFix()
        } else {
            Task {
                // Not emitted here either, and here it would have double
                // counted as well: `isAuthorized` is false for `.denied` and
                // `.restricted` too, so this branch is taken when no dialog can
                // appear, and taken again alongside DeviceFix's own emit when
                // one can (#139).
                let granted = await DeviceFix.shared.requestWhenInUseAuthorization()
                let standing = LocationPermission.of(granted: granted, canAskAgain: !DeviceFix.shared.isDenied)
                model.onLocationPermissionResult(granted, permanentlyDenied: standing == .deniedForGood)
            }
        }
    }

    private func startCamera() {
        do {
            try camera.configure()
            camera.start()
        } catch {
            model.onPhotoError("myndavélin fannst ekki")
        }
    }
}

/// Owns the capture session, the photo output and the capture delegate for
/// the camera screen. Plain NSObject with no actor isolation on purpose: the
/// delegate callbacks arrive on a capture queue, and this type only marshals
/// them onto the main actor via its closures, which is the single place
/// threading is decided.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    // Session lifecycle calls go through one queue so startRunning and
    // stopRunning cannot interleave.
    private let sessionQueue = DispatchQueue(label: "is.borgarland.camera-session")

    /// Called on the main actor with the captured JPEG bytes and the
    /// shutter-to-bytes time in milliseconds (the telemetry channel's
    /// photo-captured elapsedMs).
    var onPhotoCaptured: ((Data, Int) -> Void)?
    /// Called on the main actor with a user-facing message.
    var onPhotoError: ((String) -> Void)?

    /// When the last capture was requested; the elapsed time is measured
    /// from here to the delegate callback.
    private var captureStartedAt = Date()

    /// Published, because the capture button's .disabled() reads it: without
    /// it the view never re-renders when configuration finishes and the button
    /// stays dead.
    @Published private(set) var isConfigured = false

    enum CameraError: Error {
        case noCameraDevice
    }

    func configure() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCameraDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        isConfigured = true
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() {
        guard isConfigured else { return }
        captureStartedAt = Date()
        // JPEG, explicitly, and on the request itself: this is the settings
        // object the output actually uses. The iPhone shoots HEIC by default
        // and the city accepts only image/jpeg, image/png and image/gif, so on
        // our own capture path the format is a setting rather than a transcode
        // (AGENTS.md, docs/research/photos-exif-and-formats.md). The codec is
        // spelled through rawValue because the settings dictionary bridges to
        // the ObjC API as NSString values.
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue])
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            let message = error.localizedDescription
            DispatchQueue.main.async { self.onPhotoError?(message) }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            // The Kotlin's "myndin kom ekki í JPEG" refusal, reached here
            // when the file representation comes back empty.
            DispatchQueue.main.async { self.onPhotoError?("myndin kom ekki í JPEG") }
            return
        }
        // Shutter-to-bytes, the telemetry channel's photo-captured elapsedMs.
        let elapsedMs = max(0, Int(Date().timeIntervalSince(captureStartedAt) * 1000))
        DispatchQueue.main.async { self.onPhotoCaptured?(data, elapsedMs) }
    }
}

/// The preview layer as a UIView, the pattern from Apple's docs: the layer
/// class is replaced by AVCaptureVideoPreviewLayer and the session attaches
/// to it.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
