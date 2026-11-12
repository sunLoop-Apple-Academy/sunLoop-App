import SwiftUI
import RoomPlan
import AVFoundation

struct ContentView: View {
    @State private var cameraPermissionGranted = false
    @State private var isScanning = false
    @State private var isProcessingFinalRoom = false
    @State private var finalCapturedRoom: CapturedRoom?
    @State private var resultViewMode: Int = 0 // 0 = 3D Map, 1 = 2D Blueprint
    
    @State private var lines: [ProjectedLine] = []
    @State private var badges: [ProjectedBadge] = []
    @State private var showWallLengths = true
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if !RoomCaptureSession.isSupported {
                Text("This device does not have a LiDAR scanner.")
                    .padding()
                    .multilineTextAlignment(.center)
            } else if !cameraPermissionGranted {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Checking camera permissions...")
                        .font(.subheadline)
                }
                .onAppear(perform: checkCameraPermission)
            } else {
                // 1. RoomPlan Scanner Container
                SafeRoomPlanContainer(
                    isScanning: $isScanning,
                    isProcessingFinalRoom: $isProcessingFinalRoom,
                    finalCapturedRoom: $finalCapturedRoom,
                    projectedLines: $lines,
                    projectedBadges: $badges,
                    showWallLengths: $showWallLengths
                )
                .ignoresSafeArea()
                
                // 2. Live AR Overlay during scanning
                if isScanning {
                    LiveAROverlayView(lines: lines, badges: badges)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                
                // 3. Final Room Results (3D or 2D)
                if let finalRoom = finalCapturedRoom, !isScanning {
                    ZStack(alignment: .top) {
                        Color(UIColor.systemBackground).ignoresSafeArea()
                        
                        if resultViewMode == 0 {
                            FinalRoom3DSceneView(room: finalRoom, showWallLengths: showWallLengths)
                                .ignoresSafeArea()
                        } else {
                            FinalRoom2DBlueprintView(room: finalRoom, showWallLengths: showWallLengths)
                                .ignoresSafeArea()
                        }
                        
                        VStack(spacing: 10) {
                            Picker("Map Mode", selection: $resultViewMode) {
                                Text("3D Map + Distances").tag(0)
                                Text("2D Blueprint").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 24)
                            
                            Text(resultViewMode == 0 ? "1 finger: rotate • 2 fingers: pan & zoom" : "Pinch to zoom • Drag to pan")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(8)
                        }
                        .padding(.top, 24)
                    }
                }
                
                // 4. Processing overlay loader
                if isProcessingFinalRoom {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(.white).scaleEffect(1.4)
                            Text("Generating 3D Map & Measurements...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(16)
                    }
                }
                
                // 5. Bottom Control Bar
                HStack(spacing: 16) {
                    Button(action: {
                        if isScanning {
                            isScanning = false
                        } else {
                            finalCapturedRoom = nil
                            lines = []
                            badges = []
                            isScanning = true
                        }
                    }) {
                        Text(isScanning ? "Stop Scanning" : (finalCapturedRoom == nil ? "Start Scanning" : "New Scan"))
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                            .background(isScanning ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    if isScanning || finalCapturedRoom != nil {
                        Button(action: {
                            showWallLengths.toggle()
                        }) {
                            Text(showWallLengths ? "Hide Walls" : "Show Walls")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.black.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraPermissionGranted = granted
                }
            }
        default:
            break
        }
    }
}
