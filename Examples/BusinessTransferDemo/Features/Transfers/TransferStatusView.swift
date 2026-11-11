//
// Copyright (c) 2026 Enjel Hutasoit
//

import SwiftUI
import TransferDomain

@MainActor
struct TransferStatusView: View {
    let state: TransferState?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.title)
                .font(.headline)

            Text(presentation.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var presentation: (title: String, detail: String) {
        switch state {
        case .none:
            return ("Not submitted", "Approval and submission are separate steps.")

        case .some(.created):
            return ("Created", "No backend acceptance has been confirmed.")

        case .some(.submitting):
            return ("Submitting", "Waiting for a submission result.")

        case .some(.unknown):
            return ("Outcome unknown", "Check authoritative status before taking further action.")

        case .some(.accepted):
            return ("Accepted — processing", "Acceptance does not mean settlement.")

        case .some(.settled):
            return ("Settled", "Settlement was confirmed by the simulated bank.")

        case .some(.rejected):
            return ("Transfer rejected", "The simulated bank confirmed rejection.")
        }
    }
}
