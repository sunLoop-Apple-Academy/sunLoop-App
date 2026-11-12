//
//  SafeRoomPlanContainer.swift
//  MyApp
//
//  Created by Duaa on 12/11/2026.
//

import SwiftUI
import RoomPlan
import ARKit

// MARK: - UIViewControllerRepresentable Container
struct SafeRoomPlanContainer: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    @Binding var isProcessingFinalRoom: Bool
    @Binding var finalCapturedRoom: CapturedRoom?
    @Binding var projectedLines: [ProjectedLine]
    @Binding var projectedBadges: [ProjectedBadge]
    @Binding var showWallLengths: Bool
    
    func makeUIViewController(context: Context) -> RoomScannerViewController {
        let vc = RoomScannerViewController()
        vc.coordinator = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: RoomScannerViewController, context: Context) {
        context.coordinator.showWallLengths = showWallLengths
        uiViewController.setScanning(isScanning)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, RoomCaptureSessionDelegate {
        var parent: SafeRoomPlanContainer
        var showWallLengths = true
        weak var captureView: RoomCaptureView?
        private let roomBuilder = RoomBuilder(options: [.beautifyObjects])
        private var lastOverlayUpdate: TimeInterval = 0
        
        init(_ parent: SafeRoomPlanContainer) {
            self.parent = parent
        }
        
        // Updates AR overlays safely (max 10 times/sec to prevent memory spikes)
        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            let now = CACurrentMediaTime()
            guard now - lastOverlayUpdate > 0.1 else { return }
            lastOverlayUpdate = now
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let view = self.captureView else { return }
                let viewport = view.bounds.size
                guard viewport.width > 10, viewport.height > 10 else { return }
                let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
                
                autoreleasepool {
                    guard let frame = session.arSession.currentFrame else { return }
                    let camera = frame.camera
                    
                    var newLines: [ProjectedLine] = []
                    var newBadges: [ProjectedBadge] = []
                    
                    if self.showWallLengths {
                        for (index, wall) in room.walls.enumerated() {
                            let center3D = SIMD3<Float>(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
                            if let pt2D = Self.project3DPoint(center3D, camera: camera, orientation: orientation, viewport: viewport) {
                                newBadges.append(
                                    ProjectedBadge(
                                        position2D: pt2D,
                                        title: String(format: "Wall %d: %.2fm", index + 1, wall.dimensions.x),
                                        subtitle: String(format: "H: %.2fm", wall.dimensions.y),
                                        color: .blue
                                    )
                                )
                            }
                        }
                    }
                    
                    for object in room.objects {
                        let objCenter3D = SIMD3<Float>(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
                        let top3D = objCenter3D + SIMD3<Float>(0, object.dimensions.y / 2.0 + 0.1, 0)
                        
                        if let badgePt = Self.project3DPoint(top3D, camera: camera, orientation: orientation, viewport: viewport) {
                            newBadges.append(
                                ProjectedBadge(
                                    position2D: badgePt,
                                    title: RoomGeometryHelper.readableName(for: object.category),
                                    subtitle: String(format: "%.2fm × %.2fm", object.dimensions.x, object.dimensions.z),
                                    color: .green
                                )
                            )
                        }
                        
                        let clearances = RoomGeometryHelper.closestWalls(for: object, in: room.walls, maxCount: 2)
                        for measure in clearances {
                            if let start2D = Self.project3DPoint(measure.start3D, camera: camera, orientation: orientation, viewport: viewport),
                               let end2D = Self.project3DPoint(measure.end3D, camera: camera, orientation: orientation, viewport: viewport) {
                                let mid2D = CGPoint(x: (start2D.x + end2D.x) / 2.0, y: (start2D.y + end2D.y) / 2.0)
                                newLines.append(ProjectedLine(start2D: start2D, end2D: end2D, mid2D: mid2D, label: "\(measure.cmString) (\(measure.wallName))"))
                            }
                        }
                    }
                    
                    self.parent.projectedLines = newLines
                    self.parent.projectedBadges = newBadges
                }
            }
        }
        
        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
            Task {
                do {
                    let finalRoom = try await roomBuilder.capturedRoom(from: data)
                    await MainActor.run {
                        self.parent.finalCapturedRoom = finalRoom
                        self.parent.isProcessingFinalRoom = false
                        self.parent.isScanning = false
                    }
                } catch {
                    await MainActor.run {
                        self.parent.isProcessingFinalRoom = false
                        self.parent.isScanning = false
                    }
                }
            }
        }
        
        private static func project3DPoint(_ point: SIMD3<Float>, camera: ARCamera, orientation: UIInterfaceOrientation, viewport: CGSize) -> CGPoint? {
            let worldPoint4 = SIMD4<Float>(point.x, point.y, point.z, 1.0)
            let cameraSpacePoint = camera.viewMatrix(for: orientation) * worldPoint4
            guard cameraSpacePoint.z < -0.1 else { return nil }
            let projected = camera.projectPoint(point, orientation: orientation, viewportSize: viewport)
            guard projected.x.isFinite, projected.y.isFinite else { return nil }
            return projected
        }
    }
}

// MARK: - Safe UIViewController Wrapper
class RoomScannerViewController: UIViewController {
    var captureView: RoomCaptureView?
    weak var coordinator: SafeRoomPlanContainer.Coordinator?
    private var isRunning = false
    private var wantsToScan = false
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if captureView == nil && view.bounds.width > 10 && view.bounds.height > 10 {
            let cv = RoomCaptureView(frame: view.bounds)
            cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cv.captureSession.delegate = coordinator
            view.addSubview(cv)
            self.captureView = cv
            coordinator?.captureView = cv
            
            if wantsToScan {
                startSessionIfNeeded()
            }
        }
    }
    
    func setScanning(_ scan: Bool) {
        wantsToScan = scan
        if scan {
            startSessionIfNeeded()
        } else {
            stopSessionIfNeeded()
        }
    }
    
    private func startSessionIfNeeded() {
        guard !isRunning, let cv = captureView, view.window != nil else { return }
        isRunning = true
        let config = RoomCaptureSession.Configuration()
        cv.captureSession.run(configuration: config)
    }
    
    private func stopSessionIfNeeded() {
        guard isRunning, let cv = captureView else { return }
        isRunning = false
        coordinator?.parent.isProcessingFinalRoom = true
        cv.captureSession.stop()
    }
}
