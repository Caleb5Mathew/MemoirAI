//
//  TextEditorSheet.swift
//  MemoirAI
//
//  Created by user941803 on 7/5/25.
//


import SwiftUIstruct TextEditorSheet: View {    @Binding var text: String    let title: String    @Environment(\.dismiss) private var dismiss    var body: some View {        NavigationView {            VStack {                TextEditor(text: $text)                    .padding()                    .font(.system(size: 18, design: .serif))                    .lineSpacing(8)            }            .navigationTitle(title)            .navigationBarTitleDisplayMode(.inline)            .toolbar {                ToolbarItem(placement: .navigationBarTrailing) {                    Button("Done") {                        dismiss()                    }                }            }        }    }} 