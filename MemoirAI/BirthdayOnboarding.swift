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
        let date = calendar.date(from: components)!
        let range = calendar.range(of: .day, in: .month, for: date)!
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
                    Text("Let’s personalize")
                        .font(.customSerifFallback(size: 26))
                        .accessibilityHeading(.h1)
                    Text("your timeline")
                        .font(.customSerifFallback(size: 26))
                }

                VStack {
                    switch currentStep {
                    case 1:
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

                    case 2:
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

                    case 3:
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

                                Button("Save") {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()

                                    withAnimation {
                                        savedBirthday = date
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
                                .accessibilityLabel("Save birthdate")
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

                    Button(currentStep < 4 ? "Next" : "Done") {
                        withAnimation {
                            if currentStep < 4 {
                                currentStep += 1
                            }
                        }
                    }
                    .disabled(
                        (currentStep == 2 && selectedMonth == nil) ||
                        (currentStep == 3 && selectedDay == nil)
                    )
                    .frame(width: 80, height: 44)
                    .background(
                        (currentStep == 2 && selectedMonth == nil) ||
                        (currentStep == 3 && selectedDay == nil)
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
