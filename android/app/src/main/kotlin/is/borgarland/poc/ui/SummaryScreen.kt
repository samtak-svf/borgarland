package `is`.borgarland.poc.ui

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
import `is`.borgarland.poc.net.RelayClient
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import `is`.borgarland.poc.Payload
import `is`.borgarland.poc.PocUiState

/**
 * The POC ends here: every field that would be posted, displayed exactly.
 * Nothing is sent, ever. The send step does not exist in this app (no
 * INTERNET permission, no HTTP client, no networking dependency), so this
 * screen is the whole point.
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
                "Ekkert er sent. Þessi app hefur enga internetheimild, engan HTTP client og enga sendingargetu. Hún sýnir aðeins nákvæmlega það sem myndi fara yfir línuna.",
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

        FieldRow("type", payload.type)
        FieldRow("category", payload.category)
        FieldRow("summary", payload.summary)
        FieldRow("lat", payload.latText)
        FieldRow("lng", payload.lngText)
        FieldRow("description", payload.description)

        Text(
            "files",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(top = 12.dp),
        )
        payload.files.forEach { file ->
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

        Button(
            onClick = onSend,
            enabled = !state.sending,
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        ) { Text(if (state.sending) "Sendi..." else "Senda á relay") }

        Text(
            // The app cannot reach the city. It posts to our relay, which is
            // in dry run and forwards nothing. Decision 0002 put that decision
            // on the server so it is a deploy away, not an App Store release.
            "Sendist á ${RelayClient.BASE_URL}, ekki til borgarinnar. " +
                "Relay-ið er í þurrkeyrslu og framsendir ekkert.",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )

        state.sendResult?.let { result ->
            Card(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.secondaryContainer),
            ) {
                Text(
                    "Svar frá relay",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(start = 12.dp, top = 12.dp, end = 12.dp),
                )
                Text(
                    result,
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(12.dp),
                )
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
