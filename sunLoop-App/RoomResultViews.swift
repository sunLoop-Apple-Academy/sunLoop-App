//
//  RoomResultViews.swift
//  MyApp
//
//  Created by Duaa on 12/11/2026.
//

import SwiftUI
import SceneKit
import RoomPlan
import simd

// MARK: - Legend Overlay View
struct RoomLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.caption.bold())
                .foregroundColor(.black)
                .padding(.bottom, 2)
            
            LegendRow(color: .cyan, isLine: false, text: "Wall")
            LegendRow(color: .green.opacity(0.5), isLine: false, text: "Movable Furniture")
            LegendRow(color: .red.opacity(0.5), isLine: false, text: "Immovable Furniture")
            LegendRow(color: Color(red: 0, green: 0.5, blue: 0), isLine: false, text: "Door / Opening ≥ 0.80m")
            LegendRow(color: Color(red: 0.6, green: 0, blue: 0), isLine: false, text: "Door / Opening < 0.80m")
            LegendRow(color: .yellow, isLine: true, text: "Distance: Wall to Object")
            LegendRow(color: .red, isLine: true, text: "Distance: Object to Object")
        }
        .padding(12)
        .background(Color.white.opacity(0.9))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        .padding(16)
    }
}

struct LegendRow: View {
    let color: Color
    let isLine: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            if isLine {
                Rectangle()
                    .fill(color)
                    .frame(width: 16, height: 3)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .cornerRadius(3)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black)
        }
    }
}

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

// MARK: - Final 3D Scene Wrapper (With Legend)
struct FinalRoom3DSceneView: View {
    let room: CapturedRoom
    let showWallLengths: Bool
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoomSceneKitView(room: room, showWallLengths: showWallLengths)
            RoomLegendView()
        }
    }
}

// MARK: - Final 3D SceneKit View
struct RoomSceneKitView: UIViewRepresentable {
    let room: CapturedRoom
    let showWallLengths: Bool
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor.white
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        let scene = SCNScene()
        var allPositions: [SIMD3<Float>] = []
        let allDoorsAndOpenings = room.doors + room.openings
        
        // Colors corresponding to legend
        let wallColor = UIColor.cyan.withAlphaComponent(0.35)
        let darkGreen = UIColor(red: 0, green: 0.5, blue: 0, alpha: 0.75)
        let darkRed = UIColor(red: 0.6, green: 0, blue: 0, alpha: 0.75)
        
        // 1. Draw Walls
        for (index, wall) in room.walls.enumerated() {
            let wallBox = SCNBox(width: CGFloat(wall.dimensions.x), height: CGFloat(wall.dimensions.y), length: CGFloat(max(0.06, wall.dimensions.z)), chamferRadius: 0.01)
            let mat = SCNMaterial()
            mat.diffuse.contents = wallColor
            mat.isDoubleSided = true
            wallBox.materials = [mat]
            
            let wallNode = SCNNode(geometry: wallBox)
            wallNode.simdTransform = wall.transform
            scene.rootNode.addChildNode(wallNode)
            
            let center = SIMD3<Float>(wall.transform.columns.3.x, wall.transform.columns.3.y, wall.transform.columns.3.z)
            allPositions.append(center)
            
            if showWallLengths {
                let labelPos = center + SIMD3<Float>(0, wall.dimensions.y / 2.0 + 0.18, 0)
                let badgeNode = makeBillboardLabelNode(text: String(format: "Wall %d: %.2fm", index + 1, wall.dimensions.x), bgColor: .systemCyan, textColor: .black, scale: 0.0035)
                badgeNode.simdPosition = labelPos
                scene.rootNode.addChildNode(badgeNode)
            }
        }
        
        // 2. Draw Doors & Openings
        for (index, door) in allDoorsAndOpenings.enumerated() {
            let color: UIColor = door.dimensions.x < 0.80 ? darkRed : darkGreen
            let isOpening = door.category == .opening
            let title = isOpening ? "Opening" : "Door"
            
            let thickness = CGFloat(max(0.12, door.dimensions.z + 0.08))
            let doorBox = SCNBox(width: CGFloat(door.dimensions.x), height: CGFloat(door.dimensions.y), length: thickness, chamferRadius: 0.01)
            
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.isDoubleSided = true
            doorBox.materials = [mat]
            
            let doorNode = SCNNode(geometry: doorBox)
            doorNode.simdTransform = door.transform
            scene.rootNode.addChildNode(doorNode)
            
            let center = SIMD3<Float>(door.transform.columns.3.x, door.transform.columns.3.y, door.transform.columns.3.z)
            allPositions.append(center)
            
            if showWallLengths {
                let labelPos = center + SIMD3<Float>(0, door.dimensions.y / 2.0 + 0.18, 0)
                let badgeNode = makeBillboardLabelNode(text: String(format: "%@ %d: %.2fm", title, index + 1, door.dimensions.x), bgColor: color, textColor: .white, scale: 0.0035)
                badgeNode.simdPosition = labelPos
                scene.rootNode.addChildNode(badgeNode)
            }
        }
        
        // 3. Draw Objects & Clearances to Walls
        let objects = room.objects
        for object in objects {
            let objBox = SCNBox(width: CGFloat(object.dimensions.x), height: CGFloat(object.dimensions.y), length: CGFloat(object.dimensions.z), chamferRadius: 0.02)
            let mat = SCNMaterial()
            let isMovable = [.chair].contains(object.category)
            
            mat.diffuse.contents = isMovable ? UIColor.systemGreen.withAlphaComponent(0.5) : UIColor.systemRed.withAlphaComponent(0.5)
            objBox.materials = [mat]
            
            let objNode = SCNNode(geometry: objBox)
            objNode.simdTransform = object.transform
            scene.rootNode.addChildNode(objNode)
            
            let objCenter = SIMD3<Float>(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z)
            allPositions.append(objCenter)
            
            let name = RoomGeometryHelper.readableName(for: object.category)
            let objBadgeColor = isMovable ? UIColor.systemGreen : UIColor.systemRed
            let objBadge = makeBillboardLabelNode(text: String(format: "%@ (%.2f×%.2fm)", name, object.dimensions.x, object.dimensions.z), bgColor: objBadgeColor, textColor: .white, scale: 0.0035)
            objBadge.simdPosition = objCenter + SIMD3<Float>(0, object.dimensions.y / 2.0 + 0.15, 0)
            scene.rootNode.addChildNode(objBadge)
            
            // Get all possible clearances
            let wallClearances = RoomGeometryHelper.closestWalls(for: object, in: room.walls, maxCount: 100)
            let doorClearances = RoomGeometryHelper.closestDoors(for: object, in: allDoorsAndOpenings, maxCount: 100)
            
            // Filter out distances < 0.30m (30cm) and > 2.50m (250cm), then sort
            let validClearances = (wallClearances + doorClearances)
                .filter { $0.distanceMeters >= 0.30 && $0.distanceMeters <= 2.50 }
                .sorted { $0.distanceMeters < $1.distanceMeters }
            
            // Draw only the single nearest valid clearance (if any exist)
            if let nearestClearance = validClearances.first {
                if !isMovable {
                    let lineNode = makeCylinderLineNode(from: nearestClearance.start3D, to: nearestClearance.end3D, radius: 0.012, color: .systemYellow)
                    scene.rootNode.addChildNode(lineNode)
                }
                
                let distBadge = makeBillboardLabelNode(text: "\(nearestClearance.cmString) from \(nearestClearance.wallName)", bgColor: .systemYellow, textColor: .black, scale: 0.0032)
                distBadge.simdPosition = nearestClearance.mid3D + SIMD3<Float>(0, 0.08, 0)
                scene.rootNode.addChildNode(distBadge)
            }
        }
        
        // 4. Draw Shortest Edge-to-Edge Distances Between Objects (Red)
        for i in 0..<objects.count {
            for j in (i + 1)..<objects.count {
                let obj1 = objects[i]
                let obj2 = objects[j]
                
                let isMovable1 = [.chair].contains(obj1.category)
                let isMovable2 = [.chair].contains(obj2.category)
                
                if !isMovable1 && !isMovable2 {
                    let res = shortestDistanceBetween(obj1: obj1, obj2: obj2)
                    
                    if res.dist < 2.5 {
                        let yHeight: Float = min(obj1.transform.columns.3.y, obj2.transform.columns.3.y) - 0.1
                        let p1_3D = SIMD3<Float>(res.p1.x, yHeight, res.p1.y)
                        let p2_3D = SIMD3<Float>(res.p2.x, yHeight, res.p2.y)
                        
                        let lineNode = makeCylinderLineNode(from: p1_3D, to: p2_3D, radius: 0.008, color: .systemRed)
                        scene.rootNode.addChildNode(lineNode)
                        
                        let cmDist = Int((res.dist * 100).rounded())
                        let mid3D = (p1_3D + p2_3D) * 0.5
                        let distBadge = makeBillboardLabelNode(text: "\(cmDist) cm", bgColor: .systemRed, textColor: .white, scale: 0.0032)
                        distBadge.simdPosition = mid3D + SIMD3<Float>(0, 0.15, 0)
                        scene.rootNode.addChildNode(distBadge)
                    }
                }
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
            ZStack(alignment: .bottomTrailing) {
                Canvas { context, size in
                    var allPts: [SIMD2<Float>] = []
                    let allDoorsAndOpenings = room.doors + room.openings
                    let objects = room.objects
                    
                    let darkGreen = Color(red: 0, green: 0.5, blue: 0)
                    let darkRed = Color(red: 0.6, green: 0, blue: 0)
                    
                    for wall in room.walls {
                        let seg = RoomGeometryHelper.wallEndpoints2D(wall: wall)
                        allPts.append(seg.start)
                        allPts.append(seg.end)
                    }
                    
                    for door in allDoorsAndOpenings {
                        let seg = RoomGeometryHelper.wallEndpoints2D(wall: door)
                        allPts.append(seg.start)
                        allPts.append(seg.end)
                    }
                    
                    for obj in objects {
                        allPts.append(contentsOf: RoomGeometryHelper.getFloorCorners2D(transform: obj.transform, dimensions: obj.dimensions))
                    }
                    
                    guard !allPts.isEmpty else { return }
                    
                    let minX = allPts.map(\.x).min() ?? -2
                    let maxX = allPts.map(\.x).max() ?? 2
                    let minZ = allPts.map(\.y).min() ?? -2
                    let maxZ = allPts.map(\.y).max() ?? 2
                    
                    let roomW = max(0.5, CGFloat(maxX - minX))
                    let roomH = max(0.5, CGFloat(maxZ - minZ))
                    let finalScale = min((size.width - 0.72) / roomW, (size.height - 0.65) / roomH) * zoomScale
                    
                    let centerWorldX = CGFloat(minX + maxX) / 2.0
                    let centerWorldZ = CGFloat(minZ + maxZ) / 2.0
                    
                    func toScreen(_ pt: SIMD2<Float>) -> CGPoint {
                        CGPoint(
                            x: size.width / 2.0 + (CGFloat(pt.x) - centerWorldX) * finalScale + panOffset.width,
                            y: size.height / 2.0 + (CGFloat(pt.y) - centerWorldZ) * finalScale + panOffset.height
                        )
                    }
                    
                    // Draw Walls
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
                    
                    // Draw Doors & Openings
                    for (index, door) in allDoorsAndOpenings.enumerated() {
                        let color: Color = door.dimensions.x < 0.80 ? darkRed : darkGreen
                        let isOpening = door.category == .opening
                        let prefix = isOpening ? "Opn" : "D"
                        
                        let seg = RoomGeometryHelper.wallEndpoints2D(wall: door)
                        let sPt = toScreen(seg.start)
                        let ePt = toScreen(seg.end)
                        
                        var doorPath = Path()
                        doorPath.move(to: sPt)
                        doorPath.addLine(to: ePt)
                        context.stroke(doorPath, with: .color(color), lineWidth: 10)
                        
                        if showWallLengths {
                            let mid = CGPoint(x: (sPt.x + ePt.x) / 2, y: (sPt.y + ePt.y) / 2 - 12)
                            context.draw(Text(String(format: "%@%d: %.2fm", prefix, index + 1, door.dimensions.x)).font(.system(size: 11, weight: .bold)).foregroundColor(color), at: mid)
                        }
                    }
                    
                    // Draw Shortest Edge-to-Edge Clearances (Red)
                    for i in 0..<objects.count {
                        for j in (i + 1)..<objects.count {
                            let obj1 = objects[i]
                            let obj2 = objects[j]
                            
                            let isMovable1 = [.chair].contains(obj1.category)
                            let isMovable2 = [.chair].contains(obj2.category)
                            
                            if !isMovable1 && !isMovable2 {
                                let res = shortestDistanceBetween(obj1: obj1, obj2: obj2)
                                
                                if res.dist < 2.5 {
                                    let s2D = toScreen(res.p1)
                                    let e2D = toScreen(res.p2)
                                    var linePath = Path()
                                    linePath.move(to: s2D)
                                    linePath.addLine(to: e2D)
                                    
                                    context.stroke(linePath, with: .color(.red), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                    
                                    let cmDist = Int((res.dist * 100).rounded())
                                    let mid2D = CGPoint(x: (s2D.x + e2D.x) / 2, y: (s2D.y + e2D.y) / 2)
                                    context.draw(Text("\(cmDist) cm").font(.system(size: 10, weight: .bold)).foregroundColor(.red), at: mid2D)
                                }
                            }
                        }
                    }
                    
                    // Draw Objects
                    for obj in objects {
                        let corners = RoomGeometryHelper.getFloorCorners2D(transform: obj.transform, dimensions: obj.dimensions)
                        var poly = Path()
                        if let first = corners.first {
                            poly.move(to: toScreen(first))
                            for c in corners.dropFirst() { poly.addLine(to: toScreen(c)) }
                            poly.closeSubpath()
                        }
                        
                        let isMovable = [.chair].contains(obj.category)
                        
                        if isMovable {
                            context.fill(poly, with: .color(.green.opacity(0.35)))
                            context.stroke(poly, with: .color(.green), lineWidth: 2)
                        } else {
                            context.fill(poly, with: .color(.red.opacity(0.35)))
                            context.stroke(poly, with: .color(.red), lineWidth: 2)
                        }
                        
                        let wallClearances = RoomGeometryHelper.closestWalls(for: obj, in: room.walls, maxCount: 100)
                        let doorClearances = RoomGeometryHelper.closestDoors(for: obj, in: allDoorsAndOpenings, maxCount: 100)
                        
                        // Filter out distances < 0.30m (30cm) and > 2.50m (250cm), then sort
                        let validClearances = (wallClearances + doorClearances)
                            .filter { $0.distanceMeters >= 0.30 && $0.distanceMeters <= 2.50 }
                            .sorted { $0.distanceMeters < $1.distanceMeters }
                        
                        // Draw only the single nearest valid clearance (if any exist)
                        if let nearestClearance = validClearances.first {
                            let s2D = toScreen(SIMD2<Float>(nearestClearance.start3D.x, nearestClearance.start3D.z))
                            let e2D = toScreen(SIMD2<Float>(nearestClearance.end3D.x, nearestClearance.end3D.z))
                            var linePath = Path()
                            linePath.move(to: s2D)
                            linePath.addLine(to: e2D)
                            if !isMovable {
                                context.stroke(linePath, with: .color(.yellow), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                context.draw(Text(nearestClearance.cmString).font(.system(size: 11, weight: .bold)).foregroundColor(.yellow), at: CGPoint(x: (s2D.x + e2D.x) / 2, y: (s2D.y + e2D.y) / 2))
                            }
                        }
                        
                        let objCenter2D = toScreen(SIMD2<Float>(obj.transform.columns.3.x, obj.transform.columns.3.z))
                        context.draw(Text(RoomGeometryHelper.readableName(for: obj.category)).font(.system(size: 10, weight: .bold)).foregroundColor(.black), at: objCenter2D)
                    }
                }
                
                RoomLegendView() // Legend overlay inside the ZStack
            }
            .background(Color.white)
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

// MARK: - Math Helpers for Object-to-Object Clearances
fileprivate func shortestDistanceBetween(obj1: CapturedRoom.Object, obj2: CapturedRoom.Object) -> (p1: SIMD2<Float>, p2: SIMD2<Float>, dist: Float) {
    let corners1 = RoomGeometryHelper.getFloorCorners2D(transform: obj1.transform, dimensions: obj1.dimensions)
    let corners2 = RoomGeometryHelper.getFloorCorners2D(transform: obj2.transform, dimensions: obj2.dimensions)
    
    var bestDist: Float = .greatestFiniteMagnitude
    var bestP1 = SIMD2<Float>.zero
    var bestP2 = SIMD2<Float>.zero
    
    // Check corners of Obj1 against edges of Obj2
    for i in 0..<4 {
        let c1 = corners1[i]
        for j in 0..<4 {
            let eStart = corners2[j]
            let eEnd = corners2[(j+1)%4]
            let proj = pointOnSegment(p: c1, a: eStart, b: eEnd)
            let d = simd_distance(c1, proj)
            if d < bestDist { bestDist = d; bestP1 = c1; bestP2 = proj }
        }
    }
    
    // Check corners of Obj2 against edges of Obj1
    for i in 0..<4 {
        let c2 = corners2[i]
        for j in 0..<4 {
            let eStart = corners1[j]
            let eEnd = corners1[(j+1)%4]
            let proj = pointOnSegment(p: c2, a: eStart, b: eEnd)
            let d = simd_distance(c2, proj)
            if d < bestDist { bestDist = d; bestP1 = proj; bestP2 = c2 }
        }
    }
    
    return (bestP1, bestP2, bestDist)
}

fileprivate func pointOnSegment(p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> SIMD2<Float> {
    let ab = b - a
    let lenSq = simd_length_squared(ab)
    if lenSq == 0 { return a }
    let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0.0, 1.0)
    return a + t * ab
}
