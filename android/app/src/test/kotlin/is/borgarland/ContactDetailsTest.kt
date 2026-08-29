package `is`.borgarland

import `is`.borgarland.data.ContactDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The address the city answers to, and the rule for what counts as one (#163).
 *
 * The table below is duplicated verbatim in the iOS suite
 * (BorgarlandCoreTests/ContactDetailsTest.swift). That is deliberate: the rule
 * is written twice because the platforms share no code, and two spellings of
 * one rule drift the moment nothing compares them. Change one, change both.
 */
class ContactDetailsTest {

    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun theSharedTableOfWhatCountsAsAnAddress() {
        val accepted = listOf(
            "nafn@example.is",
            "nafn.eftirnafn@example.co.uk",
            "nafn+merki@example.is",
            "gudrodur@gmail.com",
            // Trimmed, not rejected: a keyboard's trailing space is the most
            // common way a good address arrives looking wrong.
            "  nafn@example.is  ",
            // Wrapped in non-breaking spaces, which normalise now trims from
            // both ends on both platforms — a pasted address is recoverable
            // rather than refused.
            "\u00A0nafn@example.is\u00A0",
            // A trailing byte-order mark, which normalise strips like any
            // other member of the table. An address is recovered, not refused.
            "nafn@example.is\uFEFF",
            // The other half of the boundary: a blocked scalar at the edge IS
            // trimmed, and the non-blocked one behind it survives. Both
            // platforms must keep the combining acute rather than swallow the
            // letter it belongs to.
            "\u00A0\u0301nafn@a.is",
            // An `@` followed by a combining mark. One grapheme, two scalars —
            // a cluster-wise scan would not find the `@` at all.
            "nafn@\u0301a.is",
            // Above the BMP: two surrogates on one side, one scalar on the
            // other, and nothing in the table either way.
            "nafn@a.is\uD83D\uDE00",
        )
        for (value in accepted) {
            assertTrue("should accept '$value'", ContactDetails.isValid(value))
        }

        val rejected = listOf(
            "",
            "   ",
            "nafn",
            "nafn@",
            "@example.is",
            // No dot in the domain: deliverable on some intranet, a typo from
            // somebody filing an ábending.
            "nafn@example",
            "nafn@.is",
            "nafn@example..is",
            "nafn@example.",
            "nafn@@example.is",
            "nafn@example.is nafn2@example.is",
            "nafn @example.is",
            // BOUNDARY cases, which the first version of this table lacked and
            // which is exactly why a real divergence survived it. Kotlin walks
            // UTF-16 code units and Swift walked grapheme CLUSTERS, so a
            // blocked scalar glued to the edge of a cluster behaved
            // differently: `s` + ZWJ + combining acute is one cluster, and
            // trimming it on iOS returned "nafn@a.i" — a valid-looking address
            // with the last letter of the domain eaten. Both sides now trim
            // scalar by scalar, and these are the cases that say so.
            "x\u200Dnafn@a.is",
            "nafn@a.is\u200D\u0301",
            // The case that told the two platforms apart, and that neither
            // table carried until a review found it (#163). Java's
            // Character.isWhitespace says FALSE for a non-breaking space and
            // Swift's says TRUE, so this string was accepted here and refused
            // on iOS. Both now reject it, from one explicit code-point table.
            "nafn@example\u00A0.is",
            "nafn\u00A0@example.is",
            // The zero-width family, which neither platform predicate calls
            // whitespace at all and which is invisible in a pasted address.
            "nafn@exa\u200Bmple.is",
        )
        for (value in rejected) {
            assertFalse("should reject '$value'", ContactDetails.isValid(value))
        }
    }

    @Test
    fun normaliseTrimsAndOtherwiseLeavesTheAddressAlone() {
        assertEquals("Nafn@Example.is", ContactDetails.normalise("  Nafn@Example.is \n"))
    }

    @Test
    fun anAddressSurvivesTheRoundTrip() {
        val dir = folder.newFolder()
        assertNull(ContactDetails.read(dir))
        assertTrue(ContactDetails.write(dir, "nafn@example.is"))
        assertEquals("nafn@example.is", ContactDetails.read(dir))
    }

    @Test
    fun theLastAddressWrittenIsTheOneRead() {
        val dir = folder.newFolder()
        ContactDetails.write(dir, "gamalt@example.is")
        ContactDetails.write(dir, "nytt@example.is")
        assertEquals("nytt@example.is", ContactDetails.read(dir))
    }

    @Test
    fun anEmptyOrUnreadableFileReadsAsNoAddressRatherThanAnEmptyOne() {
        val dir = folder.newFolder()
        // Cleared on purpose.
        ContactDetails.write(dir, "")
        assertNull(ContactDetails.read(dir))

        // Truncated by a process death mid-write, before the atomic rename
        // made that unreachable. Still has to read as "ask for one" rather
        // than crash (#129 is the same failure in FollowUps).
        java.io.File(dir, "contact-details.json").writeText("{\"email\": \"nafn@exa")
        assertNull(ContactDetails.read(dir))
    }
}
