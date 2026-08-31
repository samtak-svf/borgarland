package `is`.borgarland

import `is`.borgarland.data.Facts
import `is`.borgarland.data.FieldSpec
import `is`.borgarland.data.RelayRequest
import `is`.borgarland.net.RelayClient
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The app builds its request from data/relay-request.json, and this test pins
 * the two together. It proves the multipart body RelayClient builds carries
 * exactly the contract's parts, in the contract's order, with our vocabulary
 * and nothing else: the city's field names, display names and summary strings
 * never reach the wire (AGENTS.md puts them in the relay's adapter alone).
 */
class RelayRequestTest {

    private val contractText: String = File("src/main/assets/relay-request.json").readText()
    private val factsText: String = File("src/main/assets/reykjavik-form.json").readText()

    @Test
    fun assetParsesToTheDocumentedContract() {
        val contract = RelayRequest.parse(contractText)

        // The field keys, in the file's order — the order the parts are
        // written in. The check script (scripts/check-relay-contract.mjs)
        // asserts the same set on the Worker side.
        assertEquals(
            listOf("reportId", "session", "category", "latitude", "longitude", "description", "email", "photo"),
            contract.fields.keys.toList(),
        )
        assertEquals("/api/reports", contract.endpoint.path)
        assertEquals("POST", contract.endpoint.method)
        assertEquals("multipart/form-data", contract.endpoint.contentType)

        assertTrue(contract.fields.getValue("category").required)
        assertTrue(contract.fields.getValue("latitude").required)
        assertTrue(contract.fields.getValue("longitude").required)
        assertTrue(contract.fields.getValue("description").required)
        // Required of the APP, not of the relay (#163). The Worker still
        // accepts a report without an address, because builds 6 and 7 send
        // none; worker/tests/contract.test.ts pins that half. This is the one
        // field where the two sides differ on purpose.
        assertTrue(contract.fields.getValue("email").required)
        assertFalse(contract.fields.getValue("photo").required)
    }

    @Test
    fun contractAgreesWithTheFactsFileWhereItClaimsTo() {
        val contract = RelayRequest.parse(contractText)
        val facts = Facts.parse(factsText)

        assertEquals(
            facts.fields.description.maxLength,
            contract.fields.getValue("description").maxLength,
        )
        assertEquals(facts.fields.files?.accept, contract.fields.getValue("photo").accept)
    }

    @Test
    fun builtBodyWritesExactlyTheContractParts() {
        val contract = RelayRequest.parse(contractText)
        val payload = Payload(
            categorySlug = "ruslafotur",
            latitude = 64.14658919,
            longitude = -21.93279823,
            description = "Full ruslafata við stíginn",
            photos = listOf(Photo(byteArrayOf(1, 2, 3), "mynd.jpg", "image/jpeg", 0)),
            email = "nafn@example.is",
        )

        val boundary = "----boundary"
        val body = RelayClient.buildBody(payload, contract, boundary).toString(Charsets.UTF_8)

        data class Part(
            val name: String?,
            val filename: String?,
            val contentType: String?,
            val value: String,
        )

        val parts = body.split("--$boundary\r\n").drop(1).takeWhile { !it.startsWith("--\r\n") }.map { raw ->
            val headersEnd = raw.indexOf("\r\n\r\n")
            val headers = raw.substring(0, headersEnd)
            val value = raw.substring(headersEnd + 4).removeSuffix("\r\n")
            Part(
                name = Regex("""name="([^"]*)"""").find(headers)?.groupValues?.get(1),
                filename = Regex("""filename="([^"]*)"""").find(headers)?.groupValues?.get(1),
                contentType = Regex("""Content-Type: ([^\r\n]*)""").find(headers)?.groupValues?.get(1),
                value = value,
            )
        }

        // The five required text parts plus the photo, in contract order.
        assertEquals(
            listOf("category", "latitude", "longitude", "description", "email", "photo"),
            parts.map { it.name },
        )
        assertEquals("ruslafotur", parts[0].value)
        assertEquals("64.14658919", parts[1].value)
        assertEquals("-21.93279823", parts[2].value)
        assertEquals("Full ruslafata við stíginn", parts[3].value)
        assertEquals("nafn@example.is", parts[4].value)
        assertEquals("mynd.jpg", parts[5].filename)
        assertEquals("image/jpeg", parts[5].contentType)

        // The city's vocabulary never reaches the wire: not as a part name,
        // not as a value.
        assertFalse(body.contains("name=\"type\""))
        assertFalse(body.contains("name=\"summary\""))
        assertFalse(body.contains("name=\"lat\""))
        assertFalse(body.contains("name=\"lng\""))
        assertFalse(body.contains("name=\"files\""))
        assertFalse(body.contains("Ruslafötur"))
        assertFalse(body.contains("Ábending"))
    }

    @Test
    fun optionalAbsentFieldsAreOmitted() {
        val contract = RelayRequest.parse(contractText)
        val payload = Payload(
            "ruslafotur", 64.14658919, -21.93279823, "lýsing", emptyList(),
            email = "nafn@example.is",
        )

        val body = RelayClient.buildBody(payload, contract, "----b").toString(Charsets.UTF_8)

        // photo is optional and this payload has none, so the part may not
        // appear. reportId is optional too and this payload carries none.
        assertFalse(body.contains("name=\"photo\""))
        assertFalse(body.contains("name=\"reportId\""))
        assertTrue(body.contains("name=\"category\""))
    }

    @Test
    fun aReportWithNoAddressCannotBeBuilt() {
        // The city answers a report by email and by nothing else, so we
        // require one though the city does not (#163). The refusal lives in
        // the same loop that refuses any missing required part — one gate, not
        // a second rule beside the UI's.
        val contract = RelayRequest.parse(contractText)
        val payload = Payload("ruslafotur", 64.14658919, -21.93279823, "lýsing", emptyList())

        assertThrows(IllegalStateException::class.java) {
            RelayClient.buildBody(payload, contract, "----b")
        }
    }

    @Test
    fun aRequiredRoleTheAppCannotFillFailsLoudly() {
        // A contract field the app has no binding for must not be silently
        // omitted: that is exactly how the app and the relay drift apart. The
        // relay would answer 400 unknown-category or worse; failing here is
        // cheaper and clearer.
        val contract = RelayRequest.parse(contractText)
        val extra = contract.copy(
            fields = contract.fields + ("future-required-field" to FieldSpec(required = true)),
        )
        val payload = Payload("ruslafotur", 64.14658919, -21.93279823, "lýsing", emptyList())

        assertThrows(IllegalStateException::class.java) {
            RelayClient.buildBody(payload, extra, "----boundary")
        }
    }
}
