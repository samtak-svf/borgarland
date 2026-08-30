package `is`.borgarland.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import `is`.borgarland.Payload
import `is`.borgarland.PocUiState

/**
 * Every field that would be posted, displayed exactly, and then the send.
 *
 * This comment used to say "nothing is sent, ever ... no INTERNET permission,
 * no HTTP client, no networking dependency". All three were true when the
 * screen was the end of the POC and none of them survived the relay: the
 * manifest declares INTERNET, RelayClient posts over HttpURLConnection, and
 * PocViewModel.sendToRelay is wired to the button below.
 *
 * What is still true is the reason the screen exists: a person sees exactly
 * what will be sent before it is sent. The relay is in dry run and forwards
 * nothing to the city (worker/src/config.ts), which is a property of the
 * server and not of this app.
 */
@Composable
fun SummaryScreen(
    state: PocUiState,
    payload: Payload,
    onStartOver: () -> Unit,
    onSend: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("Það sem yrði sent", style = MaterialTheme.typography.headlineMedium)

        Card(
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer),
        ) {
            Text(
                "Ekkert fer til borgarinnar. Þetta app sendir aðeins á okkar relay (ákvörðun 0002) og relay-ið er í þurrkeyrslu og framsendir ekkert. Hér fyrir neðan er nákvæmlega það sem færi yfir línuna.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(12.dp),
            )
        }

        if (state.outOfBounds) {
            Text(
                "Viðvörun: hnitin falla utan þess svæðis sem kort borgarinnar sýnir.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 8.dp),
            )
        }

        // First, because it is first in data/relay-request.json and because it
        // is the one field on this screen that identifies THIS report rather
        // than describing it. The screen is headed "what would be sent" and had
        // been omitting a part that is sent (#88 put it on the wire; nothing
        // put it on the screen).
        //
        // Readable matters as well as present: the id is generated when this
        // screen is reached and kept until the walk starts over, so it is the
        // one value a person can read out BEFORE sending — which is what lets
        // an operator authorise one specific report rather than one device.
        FieldRow("reportId", payload.reportId ?: "—")
        FieldRow("category", payload.categorySlug)
        FieldRow("latitude", payload.latitudeText)
        FieldRow("longitude", payload.longitudeText)
        FieldRow("description", payload.description)

        Text(
            "photo",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 12.dp),
        )
        payload.photos.forEach { file ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            ) {
                val bitmap = remember(file.bytes, file.rotationDegrees) { decodePhoto(file.bytes, file.rotationDegrees) }
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = file.name,
                    modifier = Modifier.size(64.dp).clip(RoundedCornerShape(8.dp)),
                    contentScale = ContentScale.Crop,
                )
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(file.name, style = MaterialTheme.typography.bodyLarge)
                    Text(
                        "${file.mime}, ${file.sizeBytes} bytes",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Text(
            "Staðsetning úr: ${state.locationSource.orEmpty()}",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 12.dp),
        )

        // Disabled once the relay has taken it. The button used to return to
        // its unsent state after a 201, fully live, as though nothing had been
        // sent — and a tester pressed it again and filed the same ábending
        // twice (#85). The relay now refuses to store the repeat (#88); this is
        // so nobody is invited to make one.
        val alreadySent = state.sendOutcome?.ok == true
        // And disabled once the answer cannot change. A refusal a person
        // retries is a refusal that does not read as final: a tester pressed
        // send three times against the same jurisdiction 400 because nothing
        // on the screen said the coordinate was the problem and the button was
        // the only live control (#148). Which answers are terminal is
        // data/relay-outcomes.json's call, not this screen's.
        val refusedForGood = state.sendOutcome?.outcome?.retryable == false
        Button(
            onClick = onSend,
            enabled = !state.sending && !alreadySent && !refusedForGood,
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        ) {
            Text(
                when {
                    state.sending -> "Sendi..."
                    alreadySent -> "Sent"
                    else -> "Senda á relay"
                },
            )
        }

        Text(
            // The app cannot reach the city. It posts to our relay, which is
            // in dry run and forwards nothing. Decision 0002 put that decision
            // on the server so it is a deploy away, not an App Store release.
            // Where the report goes, in words rather than a hostname. A URL tells
            // a reader nothing they can act on, and the loopback one told them
            // something false (#29).
            "Sendist á þjónustu Borgarlands, ekki beint til borgarinnar. " +
                "Þjónustan er í þurrkeyrslu og framsendir ekkert.",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )

        state.sendOutcome?.let { sent ->
            var rawShown by remember(sent) { mutableStateOf(false) }
            Card(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    // The sentence first, and in the person's language. A
                    // tester read the raw refusal off this screen and asked
                    // what it meant (#77).
                    sent.outcome?.let { outcome ->
                        Text(outcome.says, style = MaterialTheme.typography.titleSmall)
                        outcome.advice?.let { advice ->
                            Text(
                                advice,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                        // Where the person actually is, when the relay said.
                        // The refusal used to name what we would not do and
                        // never where the coordinate fell (#148). Null when the
                        // relay sent no such field, and then there is no line at
                        // all rather than one with a hole in it.
                        outcome.detail?.let { detail ->
                            Text(
                                detail,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }

                    // Still reachable, and still exactly what the relay said:
                    // it is the fastest way to see what happened, and losing it
                    // would trade one defect for another. Behind a control the
                    // person opens on purpose, so the default screen is a
                    // sentence rather than a diagnostic dump.
                    TextButton(
                        onClick = { rawShown = !rawShown },
                        modifier = Modifier.padding(top = 4.dp),
                    ) {
                        Text(if (rawShown) "Fela tæknilegt svar" else "Tæknilegt svar")
                    }
                    if (rawShown) {
                        Text(
                            sent.raw,
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }

        Button(
            onClick = onStartOver,
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        ) { Text("Byrja aftur") }
    }
}

@Composable
private fun FieldRow(label: String, value: String) {
    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(
        value,
        style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
    )
}

private fun decodePhoto(bytes: ByteArray, rotationDegrees: Int): Bitmap {
    val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        ?: return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    if (rotationDegrees % 360 == 0) return decoded
    return Bitmap.createBitmap(
        decoded, 0, 0, decoded.width, decoded.height,
        Matrix().apply { postRotate(rotationDegrees.toFloat()) }, true,
    )
}
