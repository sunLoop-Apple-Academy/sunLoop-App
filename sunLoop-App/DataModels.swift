//
//  DataModels.swift
//  MyApp
//
//  Created by Duaa on 12/11/2026.
//
import SwiftUI
import simd

/// 3D Wall clearance/distance data model
struct WallClearance3D: Identifiable {
    let id = UUID()
    let wallName: String
    let start3D: SIMD3<Float>
    let end3D: SIMD3<Float>
    let distanceMeters: Float
    
    var mid3D: SIMD3<Float> { (start3D + end3D) * 0.5 }
    var cmString: String { "\(Int((distanceMeters * 100).rounded())) cm" }
}

/// 2D projected line for live camera overlay
struct ProjectedLine: Identifiable {
    let id = UUID()
    let start2D: CGPoint
    let end2D: CGPoint
    let mid2D: CGPoint
    let label: String
}

/// 2D floating label badge for objects and walls
struct ProjectedBadge: Identifiable {
    let id = UUID()
    let position2D: CGPoint
    let title: String
    let subtitle: String
    let color: Color
}
