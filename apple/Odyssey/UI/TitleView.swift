import SwiftUI

struct TitleView: View {
    let model: GameModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.10, blue: 0.20), Color(red: 0.10, green: 0.25, blue: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Odyssey")
                    .font(.blackletter(96))
                    .foregroundStyle(Color.parchment)
                Text("The Compleat Apventure")
                    .font(.fell(26, italic: true))
                    .foregroundStyle(Color.parchment.opacity(0.85))
                Spacer().frame(height: 30)
                if model.phase == .loading {
                    ProgressView().tint(.parchment)
                    Text("Charting the Sargalo Sea…").font(.fell(18, italic: true)).foregroundStyle(Color.parchment)
                } else {
                    Text("Hail, wanderer. Art embarking on a new quest in the dread Sargalo?")
                        .font(.fell(20))
                        .foregroundStyle(Color.parchment)
                        .multilineTextAlignment(.center)
                    Button { model.newQuest() } label: {
                        Text("Begin a New Quest").font(.fell(22)).padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.12, blue: 0.10))
                    .keyboardShortcut(.defaultAction)
                    if let error = model.loadError {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }
            }
            .padding(30)
        }
    }
}
