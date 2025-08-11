//
//  BaselineSnap.swift
//  MemoirAI
//
//  Created by user941803 on 7/5/25.
//


import SwiftUI/// A lightweight helper that aligns a view's vertical padding to an 8-pt baseline grid so different text blocks line up when pages change length.struct BaselineSnap: ViewModifier {    let grid: CGFloat = 8    func body(content: Content) -> some View {        GeometryReader { geo in            let offset = geo.size.height.truncatingRemainder(dividingBy: grid)            content                .padding(.bottom, grid - offset) // push to next baseline        }    }}extension View {    /// Align the view's bottom edge to an 8-pt baseline grid.    func baselineAligned() -> some View { self.modifier(BaselineSnap()) }} 