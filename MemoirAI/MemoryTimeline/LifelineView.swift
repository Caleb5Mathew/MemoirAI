//
//  LifelineView.swift
//  MemoirAI
//
//  Created by user941803 on 4/23/25.
//
import SwiftUI

struct LifelineView: View {
    var allYears: [Int]
    var spacing: CGFloat
    @Binding var selectedEntry: MockMemoryEntry?
    var memoriesFor: (Int) -> [MockMemoryEntry]
    var colorForAge: (Int) -> Color
    var labelStep: Int

    var body: some View {
        GeometryReader { geo in
            let dotY = geo.size.height * 0.6

            ZStack {
                ForEach(0..<allYears.count - 1, id: \.self) { i in
                    let x1 = CGFloat(i) * spacing
                    let x2 = CGFloat(i + 1) * spacing
                    let midX = (x1 + x2) / 2
                    let age1 = allYears[i]
                    let age2 = allYears[i + 1]

                    Path { path in
                        path.move(to: CGPoint(x: x1, y: dotY))
                        path.addLine(to: CGPoint(x: midX, y: dotY))
                    }
                    .stroke(colorForAge(age1), lineWidth: 2)

                    Path { path in
                        path.move(to: CGPoint(x: midX, y: dotY))
                        path.addLine(to: CGPoint(x: x2, y: dotY))
                    }
                    .stroke(colorForAge(age2), lineWidth: 2)
                }

                ForEach(Array(allYears.enumerated()), id: \.1) { index, age in
                    let x = CGFloat(index) * spacing
                    Group {
                        if age % labelStep == 0 {
                            Text("\(age)")
                                .font(.caption2)
                                .foregroundColor(.black)
                                .position(x: age == 0 ? x + 10 : x, y: dotY - 18)
                                .id(age)
                        }

                        Circle()
                            .fill(colorForAge(age))
                            .frame(width: 12, height: 12)
                            .position(x: age == 0 ? x + 10 : x, y: dotY)
                            .onTapGesture {
                                if let first = memoriesFor(age).first {
                                    selectedEntry = first
                                }
                            }
                            .id(age)
                    }
                }
            }
            // ✅ Attach GeometryReader *here* to track scroll position

        }
    }
}
