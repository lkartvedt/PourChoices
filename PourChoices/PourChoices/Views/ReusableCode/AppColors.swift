//
//  AppColors.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/14/26.
//

import SwiftUI

enum BacColors {
    static func bac(_ bac: Double) -> Color {
        switch bac {
        case 0..<0.01: return .white
        case 0.01..<0.08: return .green
        case 0.08..<0.2: return .accent
        case 0.2..<0.35: return .orange
        default: return .red
        }
    }
}
