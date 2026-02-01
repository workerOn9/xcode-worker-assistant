//
//  Item.swift
//  xcode-worker-assistant
//
//  Created by Samuel Chung on 2026/2/1.
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
