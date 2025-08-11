//
//  BookishBackground.swift
//  MemoirAI
//
//  Created by user941803 on 7/6/25.
//


import SwiftUIstruct BookishBackground: View {    var body: some View {        ZStack {            LinearGradient(                gradient: Gradient(colors: [Color(hex: "2c3e50")!, Color(hex: "34495e")!]),                startPoint: .top,                endPoint: .bottom            ).ignoresSafeArea()                        // Optional: Add a subtle texture overlay in the future            // Image("desk_texture")            //     .resizable()            //     .scaledToFill()            //     .blendMode(.multiply)            //     .opacity(0.1)            //     .ignoresSafeArea()        }    }} 