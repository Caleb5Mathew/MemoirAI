//
//  PromptData.swift
//  MemoirAI
//
//  Created by user941803 on 4/21/25.
//

let allChapters: [Chapter] = [
    Chapter(number: 1, title: "Childhood", prompts: [
        MemoryPrompt(text: "What kind of kid were you?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Did you have a favorite toy or game you couldn’t get enough of?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "What did a normal day look like when you were little?", x: 0.35, y: 0.44),
        MemoryPrompt(text: "Was there a place you loved to go as a kid?", x: 0.50, y: 0.28)
    ]),
    
    Chapter(number: 2, title: "First Job", prompts: [
        MemoryPrompt(text: "What was your very first job — and how did you get it?", x: 0.20, y: 0.80),
        MemoryPrompt(text: "What did you spend your first paycheck on?", x: 0.45, y: 0.60),
        MemoryPrompt(text: "Was there anything funny or awkward that happened at work early on?", x: 0.70, y: 0.45),
        MemoryPrompt(text: "Did that job teach you anything that stuck with you?", x: 0.60, y: 0.30)
    ]),

    Chapter(number: 3, title: "Love", prompts: [
        MemoryPrompt(text: "How did you and [spouse/loved one] meet?", x: 0.22, y: 0.76),
        MemoryPrompt(text: "What do you think makes a relationship last?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "Was there ever a moment where you just knew someone cared about you?", x: 0.65, y: 0.44),
        MemoryPrompt(text: "Any funny or sweet date stories you still remember?", x: 0.48, y: 0.28)
    ]),

    Chapter(number: 4, title: "Parenthood", prompts: [
        MemoryPrompt(text: "What do you remember about the day your first child was born?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Was there a time your kid made you laugh really hard?", x: 0.55, y: 0.63),
        MemoryPrompt(text: "What was your favorite part about being a parent?", x: 0.75, y: 0.44),
        MemoryPrompt(text: "If your kids were here, what do you think they’d say you taught them?", x: 0.60, y: 0.28)
    ]),

    Chapter(number: 5, title: "Life Lessons", prompts: [
        MemoryPrompt(text: "What’s something you used to believe that you’ve changed your mind about?", x: 0.26, y: 0.78),
        MemoryPrompt(text: "Is there a bit of advice you heard once that actually turned out to be true?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "Have you ever learned something important by messing up?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "If you could go back and give your 20-year-old self a tip, what would it be?", x: 0.52, y: 0.28)
    ]),

    Chapter(number: 6, title: "Faith", prompts: [
        MemoryPrompt(text: "Did you grow up going to church or anything like that?", x: 0.25, y: 0.80),
        MemoryPrompt(text: "Have your beliefs changed over time, or mostly stayed the same?", x: 0.46, y: 0.60),
        MemoryPrompt(text: "Was there a time when you really needed faith to get through something?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "Are there any traditions or prayers that still mean something to you?", x: 0.56, y: 0.28)
    ]),

    Chapter(number: 7, title: "Career", prompts: [
        MemoryPrompt(text: "What kind of work made you feel proud?", x: 0.24, y: 0.80),
        MemoryPrompt(text: "Was there ever a job you didn’t love, but did anyway?", x: 0.45, y: 0.63),
        MemoryPrompt(text: "Who was someone you looked up to professionally?", x: 0.70, y: 0.46),
        MemoryPrompt(text: "If someone wanted to follow in your footsteps, what would you tell them?", x: 0.56, y: 0.30)
    ]),

    Chapter(number: 8, title: "Hard Times", prompts: [
        MemoryPrompt(text: "Was there a time in life that felt really tough — and how’d you get through it?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Who or what helped you during a rough patch?", x: 0.48, y: 0.63),
        MemoryPrompt(text: "Is there a moment that seemed hard at the time but taught you something later?", x: 0.70, y: 0.44),
        MemoryPrompt(text: "Looking back, was there something that helped you stay hopeful?", x: 0.55, y: 0.30)
    ]),

    Chapter(number: 9, title: "Triumphs", prompts: [
        MemoryPrompt(text: "What’s something you accomplished that you’re really proud of?", x: 0.26, y: 0.78),
        MemoryPrompt(text: "Was there ever a moment where things just *clicked* and life changed?", x: 0.45, y: 0.61),
        MemoryPrompt(text: "What’s a small win that might not look impressive — but mattered to you?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "Did you ever make a big decision that turned out to be the right one?", x: 0.50, y: 0.29)
    ]),

    Chapter(number: 10, title: "Legacy", prompts: [
        MemoryPrompt(text: "What’s something about you you hope people remember?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "What would you want your great-grandkids to know about your life?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "If someone wrote a book about you, what would the title be?", x: 0.68, y: 0.45),
        MemoryPrompt(text: "What’s something you hope the next generation keeps doing — or stops doing?", x: 0.52, y: 0.30)
    ])
]
