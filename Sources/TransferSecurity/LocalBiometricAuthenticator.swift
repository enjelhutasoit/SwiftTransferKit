//
// Copyright (c) 2026 Enjel Hutasoit
//

import Foundation
import LocalAuthentication

@MainActor
public final class LocalBiometricAuthenticator: StepUpAuthenticator {
    private struct Attempt {
        let id: UUID
        let context: LAContext
    }

    private var activeAttempt: Attempt?

    public init() {}

    public func authenticate(reason: String) async throws {
        try Task.checkCancellation()

        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StepUpError.invalidReason
        }

        guard activeAttempt == nil else {
            throw StepUpError.alreadyInProgress
        }

        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &availabilityError
        ) else {
            throw StepUpError.unavailable
        }

        let attemptID = UUID()
        activeAttempt = Attempt(id: attemptID, context: context)

        defer {
            context.invalidate()

            if activeAttempt?.id == attemptID {
                activeAttempt = nil
            }
        }

        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()

                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, any Error>) in

                    context.evaluatePolicy(
                        .deviceOwnerAuthenticationWithBiometrics,
                        localizedReason: reason
                    ) { success, error in
                        if success {
                            continuation.resume(returning: ())
                        } else {
                            continuation.resume(
                                throwing: Self.mapFailure(error)
                            )
                        }
                    }
                }

                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelAttempt(id: attemptID)
                }
            }
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }

            throw error
        }
    }

    private func cancelAttempt(id: UUID) {
        guard activeAttempt?.id == id else {
            return
        }

        activeAttempt?.context.invalidate()
    }

    nonisolated private static func mapFailure(
        _ error: (any Error)?
    ) -> StepUpError {
        guard let error = error as? LAError else {
            return .failed
        }

        switch error.code {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return .cancelled

        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
            return .unavailable

        default:
            return .failed
        }
    }
}
