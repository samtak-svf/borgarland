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
