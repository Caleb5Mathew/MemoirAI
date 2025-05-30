///
//  BirthdayOnboarding.swift
//  MemoirAI
//
//  Created by user941803 on 4/8/25.
//

import SwiftUI

struct BirthdayOnboardingFlow: View {
    @AppStorage("userBirthday") private var savedBirthday: Date?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationManager = NotificationManager.shared

    @State private var currentStep: Int = 1
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date()) - 30
    @State private var selectedMonth: Int? = nil
    @State private var selectedDay: Int? = nil

    let years = Array(1930...Calendar.current.component(.year, from: Date()))
    let months = Calendar.current.monthSymbols

    var daysInMonth: [Int] {
        guard let month = selectedMonth else { return [] }
        var components = DateComponents()
        components.year = selectedYear
        components.month = month + 1
        let calendar = Calendar.current
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return []
        }
        return Array(range)
    }

    var composedDate: Date? {
        guard let month = selectedMonth, let day = selectedDay else { return nil }
        let components = DateComponents(year: selectedYear, month: month + 1, day: day)
        return Calendar.current.date(from: components)
    }

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.94, blue: 0.86)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Let's personalize")
                        .font(.customSerifFallback(size: 26))
                        .accessibilityHeading(.h1)
                    Text("your timeline")
                        .font(.customSerifFallback(size: 26))
                }

                VStack {
                    switch currentStep {
                    case 1:
                        VStack(spacing: 20) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Stay Connected")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Get gentle reminders to record your stories and daily prompts to inspire your memories.")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button("Enable Notifications") {
                                notificationManager.requestPermission()
                                withAnimation {
                                    currentStep += 1
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            Button("Skip for now") {
                                withAnimation {
                                    currentStep += 1
                                }
                            }
                            .foregroundColor(.gray)
                        }
                        
                    case 2:
                        VStack(spacing: 16) {
                            Text("What year were you born?")
                                .font(.headline)

                            Picker("Year", selection: $selectedYear) {
                                ForEach(years.reversed(), id: \.self) { year in
                                    Text(String(year)).tag(year) // 👈 FIXED: No comma
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(height: 150)
                            .accessibilityLabel("Year Picker")
                        }

                    case 3:
                        VStack(spacing: 16) {
                            Text("Which month?")
                                .font(.headline)

                            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(0..<months.count, id: \.self) { i in
                                    Text(months[i])
                                        .font(.body)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(selectedMonth == i ? Color.orange : Color.clear)
                                        .foregroundColor(selectedMonth == i ? .white : .black)
                                        .cornerRadius(12)
                                        .onTapGesture {
                                            withAnimation {
                                                selectedMonth = i
                                            }
                                        }
                                        .accessibilityLabel(months[i])
                                }
                            }
                            .padding(.horizontal)
                        }

                    case 4:
                        VStack(spacing: 16) {
                            Text("And the day?")
                                .font(.headline)

                            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(daysInMonth, id: \.self) { day in
                                    Text("\(day)")
                                        .frame(width: 40, height: 40)
                                        .background(selectedDay == day ? Color.orange : Color.clear)
                                        .foregroundColor(selectedDay == day ? .white : .black)
                                        .clipShape(Circle())
                                        .onTapGesture {
                                            withAnimation {
                                                selectedDay = day
                                            }
                                        }
                                        .accessibilityLabel("Day \(day)")
                                }
                            }
                            .padding(.horizontal)
                        }

                    default:
                        if let date = composedDate {
                            VStack(spacing: 12) {
                                Text("You were born on")
                                    .font(.headline)

                                Text(date.formatted(date: .long, time: .omitted))
                                    .font(.title2)
                                    .bold()
                                    .transition(.opacity.combined(with: .scale))

                                Button("Save & Start Recording") {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()

                                    withAnimation {
                                        savedBirthday = date
                                        // Schedule notifications
                                        notificationManager.scheduleDailyPrompt()
                                        notificationManager.scheduleWeeklyReminder()
                                        dismiss()
                                    }
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .padding(.horizontal)
                                .accessibilityLabel("Save birthdate and start using the app")
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                Spacer()

                // Navigation
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .foregroundColor(.gray)
                    }

                    Spacer()

                    Button(currentStep < 5 ? "Next" : "Done") {
                        withAnimation {
                            if currentStep < 5 {
                                currentStep += 1
                            }
                        }
                    }
                    .disabled(
                        (currentStep == 3 && selectedMonth == nil) ||
                        (currentStep == 4 && selectedDay == nil)
                    )
                    .frame(width: 80, height: 44)
                    .background(
                        (currentStep == 3 && selectedMonth == nil) ||
                        (currentStep == 4 && selectedDay == nil)
                            ? Color.gray.opacity(0.3)
                            : Color.orange
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 24) // 👈 FIXED: Extra horizontal padding
                .padding(.bottom, 24)
            }
        }
    }
}
