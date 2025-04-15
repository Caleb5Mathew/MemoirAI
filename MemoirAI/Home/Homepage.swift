import SwiftUI



struct HomepageView: View {
    @State private var selectedTab = 0
    let promptOfTheDay = "Tell me about your first job."
    @State private var promptCompleted: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TOP BAR
                HStack {
                    Text("MemoirAI")
                        .font(.customSerifFallback(size: 22))
                        .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))

                    Spacer()

                    Button(action: {}) {
                        Text("Go Pro")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 1, green: 0.35, blue: 0.55),
                                        Color(red: 1, green: 0.65, blue: 0.25)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(18)
                            .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
                    }

                    Button(action: {}) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 28, height: 28)
                            .foregroundColor(.gray)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Illustration
                        ZStack {
                            Image("grandparent-illustration")
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(1.03)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 4)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal)

                        // Title
                        VStack(spacing: 10) {
                            Text("Your voice.\nYour legacy.")
                                .font(.customSerifFallback(size: 30))
                                .foregroundColor(Color(red: 0.10, green: 0.22, blue: 0.14))
                                .multilineTextAlignment(.center)

                            Text("Capture your stories for future generations — no typing, just talking.")
                                .font(.subheadline)
                                .foregroundColor(Color.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Start Recording
                        NavigationLink(destination: RecordMemoryView()) {
                            Text("Start Recording")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(red: 0.83, green: 0.45, blue: 0.14))
                                )
                                .padding(.horizontal)
                                .shadow(color: Color.orange.opacity(0.25), radius: 6, x: 0, y: 3)
                        }

                        // Prompt of the Day + Timeline
                        HStack(spacing: 12) {
                            // Prompt of the Day Card
                            NavigationLink(destination: RecordMemoryView(promptOfTheDay: promptOfTheDay)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text("Prompt of the Day")
                                            .font(.footnote)
                                            .fontWeight(.bold)
                                            .foregroundColor(.black)

                                        if promptCompleted {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 16))
                                                .scaleEffect(promptCompleted ? 1.0 : 0.1)
                                                .opacity(promptCompleted ? 1 : 0)
                                                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: promptCompleted)
                                        }
                                    }

                                    Text(promptOfTheDay)
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.85))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(promptCompleted
                                    ? Color.green.opacity(0.15)
                                    : Color(red: 0.98, green: 0.93, blue: 0.80))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            }

                            // Timeline Card → Navigates to MemoryView
                            NavigationLink(destination: MemoryView()) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your Memory Timeline")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)

                                    Text("A Summer Vacation")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.85))

                                    HStack {
                                        Text("2 min")
                                        Spacer()
                                        Text("Apr 20")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.black.opacity(0.6))
                                }
                                .padding()
                                .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                .frame(maxWidth: .infinity, minHeight: 100)
                            }
                        }
                        .padding(.horizontal)

                        // Memoir Section → Navigates to MemoirView
                        NavigationLink(destination: MemoirView()) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Continue Your Memoir")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)

                                    Text("Chapter 3 of 10 Completed")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.7))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color(red: 0.98, green: 0.93, blue: 0.80))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 36)
                    }
                    .padding(.top, 24)
                }
                .onAppear {
                    resetDailyPromptIfNeeded()
                }


            }
            .background(Color(red: 0.98, green: 0.94, blue: 0.86).ignoresSafeArea())
        }
    }

    // MARK: - Check if Daily Prompt Needs Reset
    private func resetDailyPromptIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = UserDefaults.standard.object(forKey: "PromptCompletedDate") as? Date

        if lastDate == nil || Calendar.current.compare(today, to: lastDate!, toGranularity: .day) != .orderedSame {
            UserDefaults.standard.set(false, forKey: promptOfTheDay)
            UserDefaults.standard.set(today, forKey: "PromptCompletedDate")
        }

        promptCompleted = UserDefaults.standard.bool(forKey: promptOfTheDay)
    }

    // MARK: - Bottom Tab Item
    private func bottomTabItem(icon: String, title: String, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
            Text(title)
                .font(.caption2)
        }
        .foregroundColor(isSelected ? .black : .gray)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.black.opacity(0.05) : Color.clear)
        .cornerRadius(12)
    }
}

// MARK: - Preview
struct HomepageView_Previews: PreviewProvider {
    static var previews: some View {
        HomepageView()
            .previewDevice("iPhone 15 Pro")
    }
}
