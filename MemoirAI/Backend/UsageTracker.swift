//
//  UsageTracker.swift
//  MemoirAI
//
//  Created by user941803 on 5/9/25.
//


import Foundationactor UsageTracker {    private(set) var promptTokens = 0    private(set) var completionTokens = 0    func record(prompt: Int, completion: Int) {        promptTokens += prompt        completionTokens += completion    }    func reset() {        promptTokens = 0        completionTokens = 0    }}