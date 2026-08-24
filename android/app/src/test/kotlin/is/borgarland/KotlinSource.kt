package `is`.borgarland

/**
 * Comment stripping for the tests that guard a rule by scanning the app's own
 * source: [NoCityEndpointTest] and [AppOpenedOncePerProcessTest].
 *
 * Both need it for the same reason. A guard that matches a substring rather
 * than a structure fails the very comment that explains it, and then the rule
 * cannot be documented in the file it governs.
 *
 * It is shared rather than copied because the copy was wrong. Both tests used
 * `line.substringBefore("//")`, which does not know what a string literal is,
 * so a line like
 *
 * ```
 * val url = "https://reykjavik.is/abendingar"
 * ```
 *
 * was truncated at the `//` inside the URL and the hostname disappeared before
 * anything looked for it. That is not a cosmetic flaw in
 * [NoCityEndpointTest]: it is the guard for the one rule in AGENTS.md that the
 * whole architecture rests on, and the single most likely way for a city
 * endpoint to enter the app is inside a string literal. The guard was blind to
 * exactly its own subject.
 *
 * So this scans instead of splitting, and knows the four states Kotlin source
 * can be in: ordinary code, a line comment, a block comment (which nests in
 * Kotlin), and a string literal in either the escaped or the raw form. Newlines
 * inside a comment are kept so that line numbers do not move.
 *
 * It is not a Kotlin lexer and does not need to be. Character literals are not
 * tracked, because `'"'` is the only case that would matter and it appears
 * nowhere in this app; if it ever does, the failure is a spurious red build
 * rather than a rule that silently stops being enforced, which is the right
 * direction for a guard to fail in.
 */
object KotlinSource {

    fun stripComments(text: String): String {
        val out = StringBuilder(text.length)
        var i = 0
        var blockDepth = 0
        var inLineComment = false
        var inString = false
        var inRawString = false

        fun startsRaw(at: Int) = text.startsWith("\"\"\"", at)

        while (i < text.length) {
            val c = text[i]
            val next = if (i + 1 < text.length) text[i + 1] else ' '

            when {
                inLineComment -> {
                    if (c == '\n') {
                        inLineComment = false
                        out.append(c)
                    }
                    i++
                }

                blockDepth > 0 -> {
                    when {
                        c == '/' && next == '*' -> { blockDepth++; i += 2 }
                        c == '*' && next == '/' -> { blockDepth--; i += 2 }
                        else -> {
                            if (c == '\n') out.append(c)
                            i++
                        }
                    }
                }

                inRawString -> {
                    if (startsRaw(i)) {
                        inRawString = false
                        out.append("\"\"\"")
                        i += 3
                    } else {
                        out.append(c)
                        i++
                    }
                }

                inString -> {
                    when {
                        // A backslash escapes the next character, including a
                        // quote, so the pair has to move together or \" ends
                        // the string one character early.
                        c == '\\' && i + 1 < text.length -> {
                            out.append(c).append(text[i + 1])
                            i += 2
                        }
                        else -> {
                            if (c == '"') inString = false
                            out.append(c)
                            i++
                        }
                    }
                }

                startsRaw(i) -> {
                    inRawString = true
                    out.append("\"\"\"")
                    i += 3
                }

                c == '"' -> {
                    inString = true
                    out.append(c)
                    i++
                }

                c == '/' && next == '/' -> {
                    inLineComment = true
                    i += 2
                }

                c == '/' && next == '*' -> {
                    blockDepth = 1
                    i += 2
                }

                else -> {
                    out.append(c)
                    i++
                }
            }
        }

        return out.toString()
    }
}
