// Features/Squad/GroupVideoCallView.swift — authenticated Stream squad call.

import SwiftUI
import Combine
import StreamVideo
import StreamVideoSwiftUI

struct GroupVideoCallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let squadId: String
    let squadName: String

    @State private var session: GroupVideoSession?
    @State private var failureMessage: String?
    @State private var retryNumber = 0
    @State private var isLoading = true

    var body: some View {
        Group {
            if let session {
                StreamSquadCallView(
                    session: session,
                    squadId: squadId,
                    squadName: squadName,
                    userName: env.userState.currentUserName,
                    userState: env.userState
                )
            } else {
                callSetupState
            }
        }
        .task(id: retryNumber) {
            await prepareCall()
        }
    }

    private var callSetupState: some View {
        ZStack {
            PujaColors.bgDark.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: isLoading ? "video.badge.waveform" : "video.slash.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(PujaColors.festivalGold)
                Text(isLoading ? "Joining \(squadName)…" : "Couldn’t join the call")
                    .font(PujaTypography.rounded(21, weight: .bold))
                    .foregroundStyle(.white)
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(failureMessage ?? "Please check your connection and try again.")
                        .font(PujaTypography.rounded(14))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        isLoading = true
                        failureMessage = nil
                        retryNumber += 1
                    }
                    .font(PujaTypography.rounded(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(PujaColors.durgaRed))
                }
                Button("Close") { dismiss() }
                    .font(PujaTypography.rounded(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 6)
            }
            .padding(28)
        }
    }

    @MainActor
    private func prepareCall() async {
        isLoading = true
        failureMessage = nil
        do {
            let identity = try await env.userState.ensureFirebaseIdentity()
            let newSession = try await GroupVideoApi.shared.requestSession(
                squadId: squadId,
                firebaseIdToken: identity.idToken,
                userName: identity.displayName
            )
            guard !Task.isCancelled else { return }
            session = newSession
        } catch {
            guard !Task.isCancelled else { return }
            failureMessage = error.localizedDescription
            isLoading = false
        }
    }
}

@MainActor
private struct StreamSquadCallView: View {
    @Environment(\.dismiss) private var dismiss

    let session: GroupVideoSession
    let squadId: String
    let squadName: String
    let userName: String
    let userState: UserStateService

    @StateObject private var callController: StreamCallController

    init(
        session: GroupVideoSession,
        squadId: String,
        squadName: String,
        userName: String,
        userState: UserStateService
    ) {
        self.session = session
        self.squadId = squadId
        self.squadName = squadName
        self.userName = userName
        self.userState = userState

        _callController = StateObject(wrappedValue: StreamCallController(
            session: session,
            squadId: squadId,
            userName: userName,
            userState: userState
        ))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PujaColors.bgDark.ignoresSafeArea()
            StreamCallContent(viewModel: callController.viewModel, squadName: squadName)

            Button {
                callController.hangUp()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 14)
        }
        .task {
            callController.joinCall()
        }
        .onDisappear {
            callController.hangUp()
        }
    }
}

@MainActor
private final class StreamCallController: ObservableObject {
    let viewModel: CallViewModel
    private let streamClient: StreamVideo
    private let session: GroupVideoSession
    @Published private(set) var hasStarted = false
    private var hasEnded = false

    init(session: GroupVideoSession, squadId: String, userName: String, userState: UserStateService) {
        self.session = session
        let streamUser = User(id: session.userId, name: userName)
        streamClient = StreamVideo(
            apiKey: session.apiKey,
            user: streamUser,
            token: .init(stringLiteral: session.token),
            tokenProvider: { completion in
                Task { @MainActor in
                    do {
                        let freshIdentity = try await userState.ensureFirebaseIdentity()
                        let refreshedSession = try await GroupVideoApi.shared.requestSession(
                            squadId: squadId,
                            firebaseIdToken: freshIdentity.idToken,
                            userName: freshIdentity.displayName
                        )
                        completion(.success(.init(stringLiteral: refreshedSession.token)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        )
        viewModel = CallViewModel()
    }

    func joinCall() {
        guard !hasStarted else { return }
        viewModel.joinCall(callType: session.callType, callId: session.callId)
        hasStarted = true
    }

    func hangUp() {
        guard !hasEnded else { return }
        hasEnded = true
        if viewModel.call != nil { viewModel.hangUp() }
    }
}

private struct StreamCallContent: View {
    @ObservedObject var viewModel: CallViewModel
    let squadName: String

    var body: some View {
        Group {
            if viewModel.call != nil {
                CallContainer(viewFactory: DefaultViewFactory.shared, viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Connecting to \(squadName)…")
                        .font(PujaTypography.rounded(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
