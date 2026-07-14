//
//  SupportContactTests.swift
//  MemoirAITests
//

import Foundation
import Testing
@testable import MemoirAI

struct SupportContactTests {

    @Test func mailtoURL_usesSupportEmailAndDefaultSubject() {
        let url = SupportContact.mailtoURL()
        #expect(url != nil)
        #expect(url?.absoluteString.hasPrefix("mailto:\(SupportContact.email)?subject=") == true)
        #expect(url?.absoluteString.contains("MemoirAI%20Support") == true)
    }

    @Test func mailtoURL_percentEncodesSubjectWithSpacesAndSymbols() {
        let url = SupportContact.mailtoURL(subject: "Order #abc123 & more")
        let str = url?.absoluteString ?? ""
        #expect(!str.contains(" "))
        #expect(!str.contains("#"))
        #expect(str.contains("Order"))
    }

    @Test func mailtoURL_orderSubjectRoundTripsBackToOriginalText() {
        let orderId = "cs_test_abc123"
        let url = SupportContact.mailtoURL(subject: "Order #\(orderId)")
        let decodedSubject = url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .first(where: { $0.name == "subject" })?
            .value
        #expect(decodedSubject == "Order #\(orderId)")
    }
}
