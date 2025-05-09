//
//  SpeechTranscriber.swift
//  MemoirAI
//
//  Created by user941803 on 5/3/25.
//


// SpeechTranscriber.swiftimport Foundationimport Speech/// A shared helper for on-device, URL-based transcription.final class SpeechTranscriber {  static let shared = SpeechTranscriber()  private let recognizer = SFSpeechRecognizer()    private init() {    SFSpeechRecognizer.requestAuthorization { _ in }  }    /// Transcribe the given file URL, calling back on the main queue.  func transcribe(url: URL, completion: @escaping (Result<String, Error>) -> Void) {    let req = SFSpeechURLRecognitionRequest(url: url)    recognizer?.recognitionTask(with: req) { result, error in      if let err = error {        DispatchQueue.main.async { completion(.failure(err)) }      } else if let text = result?.bestTranscription.formattedString,                result?.isFinal == true {        DispatchQueue.main.async { completion(.success(text)) }      }    }  }}