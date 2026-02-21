//
//  CaskPricingType.swift
//  CaskHub
//
//  Created by Ali Elsokary on 21/02/2026.
//

import SwiftUI

enum CaskPricingType: String, Codable {
    case free = "Free"
    case freemium = "Freemium"
    case paid = "Paid"

    var badgeColor: Color {
        switch self {
        case .free: return .green
        case .freemium: return .orange
        case .paid: return .blue
        }
    }
}
