//
//  Item.swift
//  WhisperTest
//
//  Created by B.P. Emmerzaal on 21/03/2026.
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
