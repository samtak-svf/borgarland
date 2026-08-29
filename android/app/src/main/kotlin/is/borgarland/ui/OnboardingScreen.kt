package `is`.borgarland.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import `is`.borgarland.PocUiState

/**
 * Asked once, on the first launch, and never again (#163).
 *
 * The city answers an ábending by email and by nothing else — its form has no
 * phone field and the app shows no ticket handle — so a report filed without
 * an address goes into silence. Asking here rather than on the report screen
 * is the difference between answering a question once and being asked it on
 * every walk.
 *
 * **This does not make a form the entry point.** AGENTS.md says the camera is,
 * and no path into a REPORT starts with a form: this screen is not on that
 * path. It appears when the phone holds no address and never afterwards, and
 * the report flow behind it still opens on the camera.
 *
 * Deliberately emits no telemetry. `screen-left` in data/relay-events.json
 * carries a fixed enum of screen names, and adding one to it is a relay
 * deploy that must land BEFORE any build that sends it — otherwise the whole
 * event batch is refused as invalid-event-batch and the app is never told.
 * That cost is not worth a count of a screen shown once per install, and the
 * address itself deliberately carries no telemetry of any kind.
 */
@Composable
fun OnboardingScreen(
    state: PocUiState,
    onEmailChange: (String) -> Unit,
    onDone: () -> Unit,
) {
    Column(
        // imePadding BEFORE verticalScroll, the same ordering #110 was about
        // and Google's edge-to-edge skill states as a MUST: the keyboard's
        // height has to become padding on the SCROLLABLE container so the
        // scroll range grows past it. This screen has one field and one
        // button, so the keyboard covers the button on a short display.
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Velkomin í Borgarland", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Borgin svarar ábendingum í tölvupósti og hvergi annars staðar. Hún sendir " +
                "staðfestingu með tilvísunarnúmeri á netfangið þitt, og það er eina leiðin " +
                "sem þú heyrir frá henni.",
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            "Netfangið er geymt hér í símanum og hvergi annars staðar. Það fylgir hverri " +
                "ábendingu til borgarinnar, en við geymum það ekki.",
            style = MaterialTheme.typography.bodyMedium,
        )

        OutlinedTextField(
            value = state.email,
            onValueChange = onEmailChange,
            label = { Text("Netfang") },
            isError = state.email.isNotBlank() && !state.emailValid,
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Done,
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        Button(
            onClick = onDone,
            enabled = state.emailValid,
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Áfram") }

        if (!state.emailValid) {
            Text(
                "Sláðu inn netfang til að halda áfram. Þú getur breytt því síðar á skjánum þar sem ábendingin er skrifuð.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
