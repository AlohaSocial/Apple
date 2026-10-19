// SPDX-License-Identifier: MIT

import SwiftData

/// The store's schema, as the first version a migration plan can name.
///
/// Every model today is this version. The next change that a lightweight
/// migration cannot make — a renamed property, a split entity, a value that
/// has to be computed — adds `AlohaSchemaV2` with its own copy of the models,
/// moves the old shapes into this enum as nested types, and appends a stage
/// to `AlohaMigrationPlan`. Without a plan that change would leave the store
/// unopenable, and an unopenable store holds the accounts, the drafts and the
/// send queue (docs/04 §5).
public enum AlohaSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            AccountRecord.self,
            StatusRecord.self,
            TimelineEntry.self,
            NotificationRecord.self,
            DraftRecord.self,
            MarkerRecord.self,
            WatchPositionRecord.self,
            FilterRecord.self,
            RelationshipRecord.self,
        ]
    }
}

/// How one schema version becomes the next. One version, no stages yet: the
/// plan exists so the first real migration is a stage added here rather than a
/// store that fails to open.
public enum AlohaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [AlohaSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
