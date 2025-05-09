//
//  CropSheetView.swift
//  MemoirAI
//
//  Created by user941803 on 4/23/25.
//


import SwiftUIstruct CropSheetView: View {    let photoData: Data    var onCropFinished: (Data) -> Void    @Environment(\.dismiss) var dismiss    var body: some View {        VStack(spacing: 20) {            Text("Crop Your Photo")                .font(.headline)            if let uiImage = UIImage(data: photoData) {                Image(uiImage: uiImage)                    .resizable()                    .scaledToFill()                    .frame(width: 250, height: 250)                    .clipShape(Rectangle())                    .clipped()                    .cornerRadius(16)            }            Button("Save Photo") {                onCropFinished(photoData) // Fake crop for now                dismiss()            }            .padding()            .frame(maxWidth: .infinity)            .background(Color.orange)            .foregroundColor(.white)            .cornerRadius(16)        }        .padding()    }}