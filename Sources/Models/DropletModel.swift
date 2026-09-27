import SwiftUI

public enum DropletCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case ai = "AI"
    case productivity = "Productivity"
    case media = "Media"
    
    public var id: String { rawValue }
}

public struct DropletModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tag: String
    public let category: DropletCategory
    public let iconSystemName: String
    public let summary: String
    public var isEnabled: Bool
    public var isNew: Bool
    
    public init(
        id: String,
        name: String,
        tag: String,
        category: DropletCategory,
        iconSystemName: String,
        summary: String,
        isEnabled: Bool = true,
        isNew: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tag = tag
        self.category = category
        self.iconSystemName = iconSystemName
        self.summary = summary
        self.isEnabled = isEnabled
        self.isNew = isNew
    }
}
