//  ChatPhrases.swift
//  Bobbly/Chat — randomized phrase banks so the scripted bot feels alive.
//  "{app}", "{min}", "{sec}" and "{alt}" are substituted by ChatEngine.

import Foundation

enum ChatPhrases {
    static let greetings = [
        "Hey, it's Bobbly! 👋",
        "Oh hi! Bobbly here.",
        "Hello friend! It's me, Bobbly.",
        "Hiya! Got a sec to chat?",
    ]

    static let askApp = [
        "Which app do you want to open?",
        "What app are we talking about?",
        "Which app is calling your name?",
    ]

    static let askReason = [
        "Why do you want to open {app}?",
        "What do you need {app} for right now?",
        "Tell me: what's the plan with {app}?",
        "Before we open {app}: what for?",
    ]

    static let askStudyReason = [
        "You want to end {app} early? What's up?",
        "Leaving {app} already? Tell me why.",
    ]

    static let clarify = [
        "Hmm, can you tell me a little more?",
        "I didn't quite get that. What do you need it for?",
        "Say it another way? Work, school, messaging someone…?",
    ]

    static let approve = [
        "That makes sense. {app} is open for {min} minutes. Go get it done!",
        "Totally fair. You've got {min} minutes on {app}.",
        "Okay! {min} minutes of {app}. I'll be right here.",
        "Sounds legit. Unlocking {app} for {min} minutes.",
    ]

    static let approveStudyEnd = [
        "Okay, ending your study session. Good effort today!",
        "Alright, study session over. Be proud of what you did.",
    ]

    static let emergency = [
        "If it's a real emergency, don't wait on me. Unlocking {app} for {min} minutes.",
        "Go, go! {app} is open for {min} minutes. The Emergency button is always free too.",
    ]

    static let pushback = [
        "Hmm, sounds like boredom talking. How about {alt} instead?",
        "I get it, but {app} will still be there later. Maybe {alt}?",
        "Honest moment: is it worth it? You could {alt}.",
        "Your brain wants a snack. What about {alt}?",
    ]

    static let alternatives = [
        "a 5-minute walk",
        "a glass of water",
        "stretching for a minute",
        "texting a friend instead",
        "reading a few pages",
        "doodling something",
        "tidying one small thing",
        "three slow breaths",
    ]

    static let commitmentIntro = [
        "Okay. To unlock anyway, type this exactly:",
        "If you really want in, type this sentence:",
    ]

    static let commitmentSentences = [
        "I choose to open {app} even though I'm bored",
        "I am opening {app} on purpose and I will close it soon",
        "I know {app} can wait but I am opening it anyway",
    ]

    static let commitmentMismatch = [
        "That's not quite it. Type it exactly, or wait out the timer.",
        "Close! It has to match exactly.",
    ]

    static let cooldownStart = [
        "Okay, let's breathe for {sec} seconds first.",
        "Waiting {sec} seconds. Notice how it feels to wait.",
    ]

    static let cooldownNotDone = [
        "Still {sec} seconds to go. Hang in there.",
    ]

    static let grantedAfterEffort = [
        "Alright, you earned it. {app} is open for {min} minutes.",
        "Deal. {min} minutes of {app}. Make them count.",
    ]

    static let declined = [
        "Yes! Proud of you. 💛",
        "That's my friend! Bobbly is doing a happy dance.",
        "Great call. Future you says thanks.",
    ]

    static let lifeWarning = [
        "Heads up: this unlock is past your limits for today, so it costs me a life.",
        "This one costs me a life… 🥺",
    ]

    static let overLimit = [
        "You've already used {used} of your {limit} minutes on {app} today.",
        "{app} is past its daily limit ({used}/{limit} min), so I'm keeping this short.",
    ]

    static let outOfLives = [
        "I'm out of lives today, but I'll still let you decide.",
    ]

    static let strictness = [
        "That's unlock #{n} today, so I'm keeping it shorter.",
    ]
}
