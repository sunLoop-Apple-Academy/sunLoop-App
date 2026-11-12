//
//  RoomResultViews.swift
//  MyApp
//
//  Created by Duaa on 12/11/2026.
//

import SwiftUI
import SceneKit
import RoomPlan

// MARK: - Live Camera AR Overlay
struct LiveAROverlayView: View {
    let lines: [ProjectedLine]
    let badges: [ProjectedBadge]
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Canvas { context, _ in
                    for line in lines {
                        var path = Path()
                        path.move(to: line.start2D)
                        path.addLine(to: line.end2D)
                        context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                    }
                }
                
                ForEach(lines) { line in
                    Text(line.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow)
                        .cornerRadius(6)
                        .position(line.mid2D)
                }
                
                ForEach(badges) { badge in
                    VStack(spacing: 1) {
                        Text(badge.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        if !badge.subtitle.isEmpty {
                            Text(badge.subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badge.color.opacity(0.85))
                    .cornerRadius(8)
                    .position(badge.position2D)
                }
            }
        }
    }
}

// MARK: - Final 3D SceneView (SceneKit)
struct FinalRoom3DSceneView: UIViewRepresentable {
    let room: CapturedRoom
    let showWallLengths: Bool
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        let scene = SCNScene()
        var allPositions: [SIMD3<Float>] = []
        
        for (index, wall) in room.walls.enumerated() {
            let wallBox = SCNBox(width: CGFloat(wall.dimensions.x), height: CGFloat(wall.dimensions.y), length: CGFloat(max(0.06, wall.dimensions.z)), chamferRadius: 0.01)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.35)
            mat.isDoubleSided = true
            wallBox.materials = [mat]
            
            let wallNode = SCNNode(geometry: wallBox)
            wallNode.simdTransform = wall.transform
            scene.rootNode.addChildNode(wallNode)
            
            let center = SIMD3<Float>(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            allPositions.append(center)
            
            if showWallLengths {
                let labelPos = center + SIMD3<Float>(0, wall.dimensions.y / 2.0 + 0.18, 0)
                let badgeNode = makeBillboardLabelNode(text: String(format: "Wall %d: %.2fm", index + 1, wall.dimensions.x), bgColor: .systemBlue, textColor: .white, scale: 0.0035)
                badgeNode.simdPosition = labelPos
                scene.rootNode.addChildNode(badgeNode)
            }
        }
        
        for object in room.objects {
            let objBox = SCNBox(width: CGFloat(object.dimensions.x), height: CGFloat(object.dimensions.y), length: CGFloat(object.dimensions.z), chamferRadius: 0.02)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.65)
            objBox.materials = [mat]
            
            let objNode = SCNNode(geometry: objBox)
            objNode.simdTransform = object.transform
            scene.rootNode.addChildNode(objNode)
            
            let objCenter = SIMD3<Float>(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            allPositions.append(objCenter)
            
            let name = RoomGeometryHelper.readableName(for: object.category)
            let objBadge = makeBillboardLabelNode(text: String(format: "%@ (%.2f×%.2fm)", name, object.dimensions.x, object.dimensions.z), bgColor: .systemGreen, textColor: .black, scale: 0.0035)
            objBadge.simdPosition = objCenter + SIMD3<Float>(0, object.dimensions.y / 2.0 + 0.15, 0)
            scene.rootNode.addChildNode(objBadge)
            
            let clearances = RoomGeometryHelper.closestWalls(for: object, in: room.walls, maxCount: 2)
            for clearance in clearances {
                let lineNode = makeCylinderLineNode(from: clearance.start3D, to: clearance.end3D, radius: 0.012, color: .systemYellow)
                scene.rootNode.addChildNode(lineNode)
                
                let distBadge = makeBillboardLabelNode(text: "\(clearance.cmString) from \(clearance.wallName)", bgColor: .systemYellow, textColor: .black, scale: 0.0032)
                distBadge.simdPosition = clearance.mid3D + SIMD3<Float>(0, 0.08, 0)
                scene.rootNode.addChildNode(distBadge)
            }
        }
        
        let roomCenter: SIMD3<Float> = allPositions.isEmpty ? .zero : (allPositions.reduce(.zero, +) / Float(allPositions.count))
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.simdPosition = roomCenter + SIMD3<Float>(0, 4.5, 4.5)
        cameraNode.simdLook(at: roomCenter)
        scene.rootNode.addChildNode(cameraNode)
        
        scnView.scene = scene
    }
    
    private func makeCylinderLineNode(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat, color: UIColor) -> SCNNode {
        let vector = end - start
        let length = simd_length(vector)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(max(0.001, length)))
        cylinder.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (start + end) * 0.5
        let dir = simd_normalize(vector)
        let up = SIMD3<Float>(0, 1, 0)
        let dotVal = simd_dot(up, dir)
        if abs(dotVal) < 0.9999 {
            node.simdOrientation = simd_quatf(angle: acos(simd_clamp(dotVal, -1.0, 1.0)), axis: simd_normalize(simd_cross(up, dir)))
        }
        return node
    }
    
    private func makeBillboardLabelNode(text: String, bgColor: UIColor, textColor: UIColor, scale: Float) -> SCNNode {
        let font = UIFont.boldSystemFont(ofSize: 24)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let canvasSize = CGSize(width: textSize.width + 24, height: textSize.height + 14)
        
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let img = renderer.image { _ in
            bgColor.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: canvasSize), cornerRadius: 10).fill()
            (text as NSString).draw(at: CGPoint(x: 12, y: 7), withAttributes: attributes)
        }
        
        let plane = SCNPlane(width: canvasSize.width * CGFloat(scale), height: canvasSize.height * CGFloat(scale))
        plane.firstMaterial?.diffuse.contents = img
        plane.firstMaterial?.isDoubleSided = true
        plane.firstMaterial?.lightingModel = .constant
        
        let node = SCNNode(geometry: plane)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        return node
    }
}

// MARK: - Interactive 2D Blueprint View
struct FinalRoom2DBlueprintView: View {
    let room: CapturedRoom
    let showWallLengths: Bool
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                var allPts: [SIMD2<Float>] = []
                for wall in room.walls {
                    let seg = RoomGeometryHelper.wallEndpoints2D(wall: wall)
                    allPts.append(seg.start)
                    allPts.append(seg.end)
                }
                for obj in room.objects {
                    allPts.append(contentsOf: RoomGeometryHelper.getFloorCorners2D(transform: obj.transform, dimensions: obj.dimensions))
                }
                guard !allPts.isEmpty else { return }
                
                let minX = allPts.map(\.x).min() ?? -2
                let maxX = allPts.map(\.x).max() ?? 2
                let minZ = allPts.map(\.y).min() ?? -2
                let maxZ = allPts.map(\.y).max() ?? 2
                
                let roomW = max(0.5, CGFloat(maxX - minX))
                let roomH = max(0.5, CGFloat(maxZ - minZ))
                let finalScale = min((size.width * 0.72) / roomW, (size.height * 0.65) / roomH) * zoomScale
                
                let centerWorldX = CGFloat(minX + maxX) / 2.0
                let centerWorldZ = CGFloat(minZ + maxZ) / 2.0
                
                func toScreen(_ pt: SIMD2<Float>) -> CGPoint {
                    CGPoint(
                        x: size.width / 2.0 + (CGFloat(pt.x) - centerWorldX) * finalScale + panOffset.width,
                        y: size.height / 2.0 + (CGFloat(pt.y) - centerWorldZ) * finalScale + panOffset.height
                    )
                }
                
                for (index, wall) in room.walls.enumerated() {
                    let seg = RoomGeometryHelper.wallEndpoints2D(wall: wall)
                    let sPt = toScreen(seg.start)
                    let ePt = toScreen(seg.end)
                    
                    var wallPath = Path()
                    wallPath.move(to: sPt)
                    wallPath.addLine(to: ePt)
                    context.stroke(wallPath, with: .color(.cyan), lineWidth: 6)
                    
                    if showWallLengths {
                        let mid = CGPoint(x: (sPt.x + ePt.x) / 2, y: (sPt.y + ePt.y) / 2 - 12)
                        context.draw(Text(String(format: "W%d: %.2fm", index + 1, wall.dimensions.x)).font(.system(size: 11, weight: .bold)).foregroundColor(.cyan), at: mid)
                    }
                }
                
                for obj in room.objects {
                    let corners = RoomGeometryHelper.getFloorCorners2D(transform: obj.transform, dimensions: obj.dimensions)
                    var poly = Path()
                    if let first = corners.first {
                        poly.move(to: toScreen(first))
                        for c in corners.dropFirst() { poly.addLine(to: toScreen(c)) }
                        poly.closeSubpath()
                    }
                    context.fill(poly, with: .color(.green.opacity(0.35)))
                    context.stroke(poly, with: .color(.green), lineWidth: 2)
                    
                    for c in RoomGeometryHelper.closestWalls(for: obj, in: room.walls, maxCount: 2) {
                        let s2D = toScreen(SIMD2<Float>(c.start3D.x, c.start3D.z))
                        let e2D = toScreen(SIMD2<Float>(c.end3D.x, c.end3D.z))
                        var linePath = Path()
                        linePath.move(to: s2D)
                        linePath.addLine(to: e2D)
                        context.stroke(linePath, with: .color(.yellow), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        context.draw(Text(c.cmString).font(.system(size: 11, weight: .bold)).foregroundColor(.yellow), at: CGPoint(x: (s2D.x + e2D.x) / 2, y: (s2D.y + e2D.y) / 2))
                    }
                    
                    let objCenter2D = toScreen(SIMD2<Float>(obj.transform.columns.3.x, obj.transform.columns.3.z))
                    context.draw(Text(RoomGeometryHelper.readableName(for: obj.category)).font(.system(size: 10, weight: .bold)).foregroundColor(.white), at: objCenter2D)
                }
            }
            .background(Color(white: 0.1))
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { val in zoomScale = max(0.5, min(5.0, lastZoomScale * val)) }
                        .onEnded { _ in lastZoomScale = zoomScale },
                    DragGesture()
                        .onChanged { val in panOffset = CGSize(width: lastPanOffset.width + val.translation.width, height: lastPanOffset.height + val.translation.height) }
                        .onEnded { _ in lastPanOffset = panOffset }
                )
            )
        }
    }
}
