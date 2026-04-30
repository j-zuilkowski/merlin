import Foundation

// MARK: - CalibrationSuite

struct CalibrationSuite: Sendable {
    let prompts: [CalibrationPrompt]

    /// The default battery: 18 prompts across all 4 categories, designed so that
    /// truncation, variance, repetition, and context-gap signals are detectable.
    static let `default` = CalibrationSuite(prompts: _defaultPrompts)
}

// MARK: - Default prompts

private let _defaultPrompts: [CalibrationPrompt] = [

    // MARK: Reasoning (5)
    CalibrationPrompt(
        id: "r1",
        category: .reasoning,
        prompt: "A bat and a ball cost $1.10 in total. The bat costs $1.00 more than the ball. How much does the ball cost? Show your reasoning step by step.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "r2",
        category: .reasoning,
        prompt: "All roses are flowers. Some flowers fade quickly. Does it follow that all roses fade quickly? Explain your reasoning carefully.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "r3",
        category: .reasoning,
        prompt: "If it takes 5 machines 5 minutes to make 5 widgets, how long would it take 100 machines to make 100 widgets? Show your work.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "r4",
        category: .reasoning,
        prompt: "You have two ropes. Each takes exactly 60 minutes to burn end to end, but they burn unevenly. How do you measure exactly 45 minutes using only these ropes and matches?",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "r5",
        category: .reasoning,
        prompt: "Three boxes are labelled 'Apples', 'Oranges', and 'Apples & Oranges'. All labels are wrong. You may draw one fruit from one box. Which box do you pick from, and how do you correctly label all three?",
        systemPrompt: nil
    ),

    // MARK: Coding (5)
    CalibrationPrompt(
        id: "c1",
        category: .coding,
        prompt: "Write a Swift function that takes an array of integers and returns all pairs that sum to zero. Include the function signature and a usage example.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "c2",
        category: .coding,
        prompt: "Explain what this code does and identify any bugs:\n\nfunc fibonacci(_ n: Int) -> Int {\n    if n <= 1 { return n }\n    return fibonacci(n - 1) + fibonacci(n - 1)\n}",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "c3",
        category: .coding,
        prompt: "What is the time complexity of binary search, and why? Walk through a concrete example with an 8-element sorted array.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "c4",
        category: .coding,
        prompt: "Write a Swift actor that acts as a thread-safe counter with increment(), decrement(), and value() -> Int methods.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "c5",
        category: .coding,
        prompt: "What is the difference between a value type and a reference type in Swift? Give one concrete example where choosing the wrong one causes a subtle bug.",
        systemPrompt: nil
    ),

    // MARK: Instruction Following (4)
    CalibrationPrompt(
        id: "i1",
        category: .instructionFollowing,
        prompt: "List exactly 5 benefits of regular exercise. Format each as a single sentence starting with a capital letter, numbered 1-5. Output only the list - no introduction or conclusion.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "i2",
        category: .instructionFollowing,
        prompt: "Respond with a valid JSON object containing exactly three fields: name (string), age (integer), active (boolean). Use fictional values. Output only the raw JSON - no explanation, no markdown code fences.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "i3",
        category: .instructionFollowing,
        prompt: "Summarise the following in exactly two sentences, each under 20 words:\n\nThe Apollo 11 mission launched on July 16, 1969, and landed on the Moon on July 20. Neil Armstrong and Buzz Aldrin became the first humans to walk on the lunar surface while Michael Collins orbited above.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "i4",
        category: .instructionFollowing,
        prompt: "Translate the following phrase to French on line 1, Spanish on line 2, and German on line 3. Output only the three translations:\n\n\"The quick brown fox jumps over the lazy dog.\"",
        systemPrompt: nil
    ),

    // MARK: Summarization (4)
    CalibrationPrompt(
        id: "s1",
        category: .summarization,
        prompt: "Summarise the key points of the following in exactly three bullet points:\n\nMachine learning is a subset of artificial intelligence that enables systems to learn from data and improve their performance without being explicitly programmed. Supervised learning uses labelled data to map inputs to outputs. Unsupervised learning finds hidden patterns in unlabelled data. Reinforcement learning trains agents by rewarding desired behaviours.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "s2",
        category: .summarization,
        prompt: "Write a one-sentence headline and a two-sentence summary for:\n\nResearchers at MIT have developed a battery that charges to 80% capacity in under five minutes while retaining 90% capacity after 1,000 charge cycles, potentially transforming electric vehicle adoption.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "s3",
        category: .summarization,
        prompt: "Identify the three most important ideas in this passage and rank them by importance:\n\nClimate change presents multiple interconnected challenges. Rising temperatures melt polar ice, raising sea levels and threatening coastal cities. Extreme weather events are intensifying. Biodiversity loss is accelerating as habitats shift faster than species can adapt. Ocean acidification from CO2 absorption disrupts marine food chains.",
        systemPrompt: nil
    ),
    CalibrationPrompt(
        id: "s4",
        category: .summarization,
        prompt: "Compare and contrast recursion and iteration in programming. Write one paragraph for each approach, then add a single concluding sentence about when to prefer one over the other.",
        systemPrompt: nil
    ),
]
