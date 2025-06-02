//
//  PromptData.swift
//  MemoirAI
//
//  Created by user941803 on 4/21/25.
//

let allChapters: [Chapter] = [
    Chapter(number: 1, title: "Childhood", prompts: [
        MemoryPrompt(text: "What is one of your clearest early memories?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "What games or activities made you happiest as a child?", x: 0.40, y: 0.62),
        MemoryPrompt(text: "Tell me about a place you loved to spend time when you were small.", x: 0.35, y: 0.44),
        MemoryPrompt(text: "Who showed you kindness when you were young, and what did they do?", x: 0.50, y: 0.28)
    ]),
    
    Chapter(number: 2, title: "First Job", prompts: [
        MemoryPrompt(text: "How did you first earn money on your own?", x: 0.20, y: 0.80),
        MemoryPrompt(text: "What was a skill you had to learn quickly in that role?", x: 0.45, y: 0.60),
        MemoryPrompt(text: "Did someone help or guide you during those early work days?", x: 0.70, y: 0.45),
        MemoryPrompt(text: "What was the biggest lesson you learned from your work and how?", x: 0.60, y: 0.30)
    ]),

    Chapter(number: 3, title: "Love", prompts: [
        MemoryPrompt(text: "Think of someone you have loved deeply—what first drew you to them?", x: 0.22, y: 0.76),
        MemoryPrompt(text: "Describe a simple moment with that person that still warms your heart.", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What has love—romantic or otherwise—taught you about yourself?", x: 0.65, y: 0.44),
        MemoryPrompt(text: "How do you show care to the people who matter most to you today?", x: 0.48, y: 0.28)
    ]),

    Chapter(number: 4, title: "Parenthood", prompts: [
        MemoryPrompt(text: "If you are a parent, what did you feel the day you met your child? (If not, tell about nurturing someone younger than you.)", x: 0.30, y: 0.80),
        MemoryPrompt(text: "What family routine or tradition do you hope will continue?", x: 0.55, y: 0.63),
        MemoryPrompt(text: "Share a challenge you faced while caring for children and how you handled it.", x: 0.75, y: 0.44),
        MemoryPrompt(text: "What value did you try hardest to pass on, and why?", x: 0.60, y: 0.28)
    ]),

    Chapter(number: 5, title: "Life Lessons", prompts: [
        MemoryPrompt(text: "Tell about an event that changed how you see the world.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What is a mistake that later became a gift?", x: 0.42, y: 0.63),
        MemoryPrompt(text: "Which small habit has quietly improved your life?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What advice would you offer to someone starting out in life today?", x: 0.52, y: 0.28)
    ]),

    Chapter(number: 6, title: "Faith", prompts: [
        MemoryPrompt(text: "What role—if any—have faith or personal beliefs played in your life?", x: 0.25, y: 0.80),
        MemoryPrompt(text: "Describe a time you felt supported by something bigger than yourself.", x: 0.46, y: 0.60),
        MemoryPrompt(text: "Have you ever struggled with doubt? What helped you move forward?", x: 0.70, y: 0.43),
        MemoryPrompt(text: "Which practice, text, or idea gives you peace?", x: 0.56, y: 0.28)
    ]),

    Chapter(number: 7, title: "Career", prompts: [
        MemoryPrompt(text: "What kind of work has felt most meaningful to you, and why?", x: 0.24, y: 0.80),
        MemoryPrompt(text: "Tell about a mentor or co-worker who made a difference.", x: 0.45, y: 0.63),
        MemoryPrompt(text: "What was a hard decision you had to make at work?", x: 0.70, y: 0.46),
        MemoryPrompt(text: "Looking back, what part of your working life brings you pride?", x: 0.56, y: 0.30)
    ]),

    Chapter(number: 8, title: "Hard Times", prompts: [
        MemoryPrompt(text: "Describe a season when life was difficult. What helped you cope?", x: 0.30, y: 0.80),
        MemoryPrompt(text: "Who stood by you during that time?", x: 0.48, y: 0.63),
        MemoryPrompt(text: "What inner strength did you discover under pressure?", x: 0.70, y: 0.44),
        MemoryPrompt(text: "What wisdom did that experience leave you with?", x: 0.55, y: 0.30)
    ]),

    Chapter(number: 9, title: "Triumphs", prompts: [
        MemoryPrompt(text: "Tell the story of a goal you reached that mattered to you.", x: 0.26, y: 0.78),
        MemoryPrompt(text: "What obstacles did you have to overcome to get there?", x: 0.45, y: 0.61),
        MemoryPrompt(text: "How did achieving this change you or those around you?", x: 0.66, y: 0.45),
        MemoryPrompt(text: "What would you say to someone attempting something similar?", x: 0.50, y: 0.29)
    ]),

    Chapter(number: 10, title: "Legacy", prompts: [
        MemoryPrompt(text: "When future family members think of you, what do you hope they feel?", x: 0.25, y: 0.78),
        MemoryPrompt(text: "Is there a value, story, or tradition you want carried forward?", x: 0.44, y: 0.60),
        MemoryPrompt(text: "What do you see as your most lasting contribution?", x: 0.68, y: 0.45),
        MemoryPrompt(text: "If you could leave one message for people listening years from now, what would it be?", x: 0.52, y: 0.30)
    ])
]
