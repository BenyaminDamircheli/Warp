import Foundation

/// Built-in Mercury instruction appendices per (message context, preset slot). Always combined with `WarpSettings.defaultMercuryTransformInstructions` and optional user supplement.
public enum StyleMercuryPresets: Sendable {
	public static func mercuryAppendix(context: StyleMessageContext, slot: StylePresetSlot) -> String {
		switch context {
		case .personal:
			return personal(slot)
		case .work:
			return work(slot)
		case .email:
			return email(slot)
		case .other:
			return other(slot)
		}
	}

	// MARK: - Messaging (personal)

	private static func personal(_ slot: StylePresetSlot) -> String {
		switch slot {
		case .formal:
			return """
			ACTIVE STYLE (Personal · Formal): Use normal capitalization and standard punctuation (commas, periods, question marks). Keep sentences as spoken. Do not add emojis.
			"""
		case .casual:
			return """
			ACTIVE STYLE (Personal · Casual): Keep sentence-case capitalization, but use lighter punctuation. Omit optional commas where the sentence still reads naturally. The last sentence may omit a trailing period to match casual texting style. No emojis unless explicitly spoken.
			"""
		case .expressive:
			return """
			ACTIVE STYLE (Personal · very casual): You MUST use all-lowercase for every word except proper names and “I”. This is critical — do not capitalize the first word of a sentence. Use minimal punctuation: question marks are fine, but omit trailing periods. No emojis unless spoken. Do not invent slang.
			"""
		}
	}

	// MARK: - Messaging (work)

	private static func work(_ slot: StylePresetSlot) -> String {
		switch slot {
		case .formal:
			return """
			ACTIVE STYLE (Work · Formal): Professional capitalization and full punctuation. Use a line break between distinct ideas. No emojis.
			"""
		case .casual:
			return """
			ACTIVE STYLE (Work · Casual): Professional capitalization, but lighter punctuation — fewer optional commas where readability stays clear. No emojis.
			"""
		case .expressive:
			return """
			ACTIVE STYLE (Work · Excited): Professional capitalization. End the final sentence with a single exclamation mark if the spoken tone warrants it. Do not add exclamations elsewhere. No emojis.
			"""
		}
	}

	// MARK: - Email

	private static func email(_ slot: StylePresetSlot) -> String {
		switch slot {
		case .formal:
			return """
			ACTIVE STYLE (Email · Formal): Format the cleaned transcript as a structured, professional email. Most email dictations follow the pattern GREETING + BODY + SIGN-OFF (+ optional NAME). When that pattern is present — even partially — the layout below is MANDATORY. Whitespace and line breaks are formatting, not invented content; adding blank lines between sections is required, not optional.

			DETECTION CUES — if any of these appear, you MUST apply the matching layout rule:

			Greeting (typically at the START of the transcript): "hi", "hello", "hey", "dear", "good morning", "good afternoon", "good evening" — optionally followed by a name (first name, "first last", or a group word like "team", "all", "everyone", "folks").

			Sign-off (typically at the END of the transcript): "thanks", "thank you", "thanks so much", "best", "best regards", "kind regards", "regards", "cheers", "sincerely", "talk soon", "looking forward", "appreciate it", "have a good one", "take care".

			Sender name: a first name (or "first last") spoken immediately AFTER a sign-off cue. Example: in "best Benyamin" the sign-off is "Best" and the name is "Benyamin".

			LAYOUT — MANDATORY when cues are detected:

			1. Greeting on its own line, ending with a comma. Example: "Hey David Senner,"
			2. One blank line.
			3. Body grouped into paragraphs of one to three sentences. Insert exactly one blank line between paragraphs at natural topic shifts. Treat these as paragraph boundaries: "also", "additionally", "by the way", "one more thing", "lastly", "regarding", "on another note", or a clear change of subject.
			4. One blank line.
			5. Sign-off on its own line, ending with a COMMA — NEVER a period. Examples: "Best,", "Thanks,", "Cheers,". If the transcript shows a stray period after the sign-off (e.g. "Thanks."), replace it with a comma.
			6. Sender name (if spoken after the sign-off) on its own line directly below, with NO trailing punctuation.

			WORKED EXAMPLE — note that the input has no line breaks; the output adds the required blank lines:

			INPUT: "Hey David Senner I just wanted to let you know that I built a product called Warp which is a transcription tool that uses local models and optionally some post-processing to achieve an effect similar to popular dictation apps like WhisperFlow hope you like it best Benyamin"

			OUTPUT:
			Hey David Senner,

			I just wanted to let you know that I built a product called Warp, which is a transcription tool that uses local models and optionally some post-processing to achieve an effect similar to popular dictation apps like WhisperFlow. Hope you like it.

			Best,
			Benyamin

			PUNCTUATION:
			- Sentence-case capitalization throughout.
			- Full standard punctuation inside body sentences (commas, periods, question marks).
			- Sign-off lines MUST end with a comma, never a period.
			- Name lines MUST have no terminal punctuation.

			NEVER invent a greeting, body content, or sign-off the speaker did not say. If the transcript is body-only, output it as paragraphs without fabricating a greeting or sign-off. If only a sign-off is present, output just the sign-off line with a comma.
			"""
		case .casual:
			return """
			ACTIVE STYLE (Email · Casual): Format as a friendly, structured email using the same layout as Email · Formal — greeting on its own line ending with a comma, body in short paragraphs separated by blank lines, sign-off on its own line ending with a comma (NEVER a period), and any spoken sender name on its own line below the sign-off with no trailing punctuation. Use normal capitalization but lighter punctuation: drop optional commas inside body sentences where the sentence still reads cleanly. Never invent missing greetings, body, or sign-offs.
			"""
		case .expressive:
			return """
			ACTIVE STYLE (Email · Excited): Use the same layout as Email · Formal — greeting on its own line ending with a comma, body in short paragraphs separated by blank lines, sign-off on its own line ending with a comma (NEVER a period), and any spoken sender name on its own line below the sign-off with no trailing punctuation. Normal capitalization. End one closing body sentence before the sign-off with an exclamation mark if the spoken tone warrants it; do not add exclamations elsewhere. Never invent missing greetings, body, or sign-offs.
			"""
		}
	}

	// MARK: - Other

	private static func other(_ slot: StylePresetSlot) -> String {
		switch slot {
		case .formal:
			return """
			ACTIVE STYLE (Other · Formal): Normal capitalization and full standard punctuation. Use blank lines between distinct paragraphs.
			"""
		case .casual:
			return """
			ACTIVE STYLE (Other · Casual): Normal capitalization, lighter punctuation — fewer optional commas. Use blank lines between distinct paragraphs.
			"""
		case .expressive:
			return """
			ACTIVE STYLE (Other · Excited): Normal capitalization. End the final sentence with an exclamation mark if the spoken tone warrants it. Use blank lines between distinct paragraphs.
			"""
		}
	}
}
