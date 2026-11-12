//
// Copyright (c) 2026 Enjel Hutasoit
//

import SwiftUI
import TransferDomain

@MainActor
struct TransferStatusView: View {
    let state: TransferState?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.symbol)
                .font(.title2)
                .foregroundStyle(presentation.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.headline)

                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var presentation: (
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) {
        switch state {
        case .none:
            return (
                "Not submitted",
                "Approval and submission are separate steps.",
                "doc.text",
                .secondary
            )

        case .some(.created):
            return (
                "Created",
                "No bank acceptance has been confirmed.",
                "doc.badge.plus",
                .secondary
            )

        case .some(.submitting):
            return (
                "Submitting",
                "Waiting for the submission result.",
                "arrow.up.circle",
                DemoTheme.accent
            )

        case .some(.unknown):
            return (
                "Outcome unknown",
                "Check bank status. Do not submit a replacement transfer.",
                "questionmark.circle",
                DemoTheme.accent
            )

        case .some(.accepted):
            return (
                "Accepted · Processing",
                "The simulated bank accepted the transfer. Settlement is pending.",
                "clock",
                DemoTheme.accent
            )

        case .some(.settled):
            return (
                "Transfer settled",
                "Settlement was confirmed by the simulated bank.",
                "checkmark.circle.fill",
                DemoTheme.success
            )

        case .some(.rejected):
            return (
                "Transfer rejected",
                "The simulated bank confirmed rejection.",
                "xmark.circle.fill",
                DemoTheme.destructive
            )
        }
    }
}
