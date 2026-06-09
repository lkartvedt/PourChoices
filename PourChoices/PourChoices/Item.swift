//
//  Item.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
