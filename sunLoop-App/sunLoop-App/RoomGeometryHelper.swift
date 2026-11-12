//
//  RoomGeometryHelper.swift
//  MyApp
//
//  Created by Duaa on 12/11/2026.
//

import Foundation
import RoomPlan
import simd

enum RoomGeometryHelper {
    
    /// Finds the closest walls to a given scanned object
    static func closestWalls(for object: CapturedRoom.Object, in walls: [CapturedRoom.Surface], maxCount: Int) -> [WallClearance3D] {
        let objCenterY = object.transform.columns.3.y
        let corners3D = getBottomCorners3D(transform: object.transform, dimensions: object.dimensions, yHeight: objCenterY)
        
        var results: [WallClearance3D] = []
        for (index, wall) in walls.enumerated() {
            let res = closestSegmentBetweenObjectAndWall(corners3D: corners3D, wall: wall, yPlane: objCenterY)
            if res.distance <= 4.0 {
                results.append(WallClearance3D(wallName: "Wall \(index + 1)", start3D: res.start3D, end3D: res.end3D, distanceMeters: res.distance))
            }
        }
        results.sort { $0.distanceMeters < $1.distanceMeters }
        return Array(results.prefix(maxCount))
    }
    
    /// Extracts 2D endpoints of a wall surface
    static func wallEndpoints2D(wall: CapturedRoom.Surface) -> (start: SIMD2<Float>, end: SIMD2<Float>) {
        let center = SIMD2<Float>(wall.transform.columns.3.x, wall.transform.columns.3.z)
        let right = simd_normalize(SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z))
        let halfL = wall.dimensions.x / 2.0
        return (center - right * halfL, center + right * halfL)
    }
    
    /// Extracts 2D floor corners for an object
    static func getFloorCorners2D(transform: simd_float4x4, dimensions: simd_float3) -> [SIMD2<Float>] {
        let halfW = dimensions.x / 2.0
        let halfD = dimensions.z / 2.0
        let offsets: [SIMD4<Float>] = [
            SIMD4<Float>(-halfW, 0, -halfD, 1),
            SIMD4<Float>( halfW, 0, -halfD, 1),
            SIMD4<Float>( halfW, 0,  halfD, 1),
            SIMD4<Float>(-halfW, 0,  halfD, 1)
        ]
        return offsets.map {
            let world = transform * $0
            return SIMD2<Float>(world.x, world.z)
        }
    }
    
    /// Extracts 3D floor corners for an object
    static func getBottomCorners3D(transform: simd_float4x4, dimensions: simd_float3, yHeight: Float) -> [SIMD3<Float>] {
        getFloorCorners2D(transform: transform, dimensions: dimensions).map { SIMD3<Float>($0.x, yHeight, $0.y) }
    }
    
    /// Calculates the shortest distance segment between object corners and a wall
    static func closestSegmentBetweenObjectAndWall(corners3D: [SIMD3<Float>], wall: CapturedRoom.Surface, yPlane: Float) -> (start3D: SIMD3<Float>, end3D: SIMD3<Float>, distance: Float) {
        let seg = wallEndpoints2D(wall: wall)
        let wallStart = SIMD2<Float>(seg.start.x, seg.start.y)
        let wallEnd = SIMD2<Float>(seg.end.x, seg.end.y)
        
        var bestDist: Float = .greatestFiniteMagnitude
        var bestStart = SIMD3<Float>.zero
        var bestEnd = SIMD3<Float>.zero
        
        for corner in corners3D {
            let p2d = SIMD2<Float>(corner.x, corner.z)
            let projection = nearestPointOnSegment(p: p2d, a: wallStart, b: wallEnd)
            let dist = simd_distance(p2d, projection)
            
            if dist < bestDist {
                bestDist = dist
                bestStart = corner
                bestEnd = SIMD3<Float>(projection.x, yPlane, projection.y)
            }
        }
        return (bestStart, bestEnd, bestDist)
    }
    
    private static func nearestPointOnSegment(p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> SIMD2<Float> {
        let ab = b - a
        let lenSq = simd_length_squared(ab)
        if lenSq == 0 { return a }
        let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0.0, 1.0)
        return a + t * ab
    }
    
    /// Translates RoomPlan object categories into clean, readable labels
    static func readableName(for category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .table: return "Table"
        case .chair: return "Chair"
        case .sofa: return "Sofa"
        case .bed: return "Bed"
        case .refrigerator: return "Refrigerator"
        case .storage: return "Storage / Cabinet"
        case .television: return "Television"
        case .sink: return "Sink"
        case .toilet: return "Toilet"
        case .bathtub: return "Bathtub"
        case .dishwasher: return "Dishwasher"
        case .oven: return "Oven"
        case .stairs: return "Stairs"
        @unknown default: return "Object"
        }
    }
}
