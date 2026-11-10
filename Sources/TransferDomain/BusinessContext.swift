//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation

/// Business membership information.
///
/// A client-held value is not proof of server authorization.
public struct BusinessContext: Equatable, Sendable {
    public let organizationID: UUID
    public let userID: UUID
    public let roles: Set<BusinessRole>

    public init(
        organizationID: UUID,
        userID: UUID,
        roles: Set<BusinessRole>
    ) {
        self.organizationID = organizationID
        self.userID = userID
        self.roles = roles
    }
}
