package `is`.borgarland.poc.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import `is`.borgarland.poc.PocUiState

/**
 * The suggestion slot sits above the category picker and is empty in this POC.
 * Per decisions/0008 a suggestion may arrive late or never and must never
 * block, so the flow completes without it: the slot is present, the send path
 * does not depend on it.
 */
@Composable
fun DetailsScreen(
    state: PocUiState,
    onSelectCategory: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onContinue: () -> Unit,
) {
    Column(
        // imePadding BEFORE verticalScroll, which is the whole of #110: the
        // keyboard's height has to become padding on the scrollable container
        // so the scroll range grows past it. After the scroll modifier the
        // padding lands inside the scrolling content and the send button stays
        // where the keyboard is. Google's edge-to-edge skill states the order
        // as a MUST.
        //
        // Their preferred form is Modifier.fitInside(WindowInsetsRulers.Ime.current),
        // which is not in Compose BOM 2026.04.01 (foundation-layout 1.11.0 has
        // no WindowInsetsRulers at all), so this is their option 2. There is no
        // Scaffold in this app, so no contentWindowInsets is already applying
        // the IME inset and there is nothing to double up with.
        modifier = Modifier
            .fillMaxWidth()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("Skrá ábendingu", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Staðsetning: ${state.locationSource.orEmpty()}",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 4.dp),
        )

        OutlinedCard(modifier = Modifier.fillMaxWidth().padding(top = 16.dp)) {
            Column(modifier = Modifier.padding(12.dp)) {
                Text("Tillaga úr myndinni", style = MaterialTheme.typography.titleSmall)
                Text(
                    "Engin tillaga í þessari POC. Þegar greining verður til birtist tillagan hér, seint eða aldrei. Hún kemur aldrei í veg fyrir áframhald.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        Text(
            "Flokkur",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 16.dp, bottom = 4.dp),
        )
        state.categories.forEach { category ->
            val selected = state.selectedSlug == category.slug
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = selected,
                        onClick = { onSelectCategory(category.slug) },
                    )
                    .padding(vertical = 6.dp),
            ) {
                RadioButton(selected = selected, onClick = null)
                Column {
                    // Our name for the category where we have one, the city's
                    // otherwise (data/category-labels.json). The model resolves
                    // it, so this screen never learns that an override exists.
                    Text(
                        state.categoryDisplay[category.slug] ?: category.category,
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    // The line under it is a help string for a category whose
                    // scope is not obvious, and most categories have none.
                    //
                    // This used to render the city's general/specific `type`,
                    // which put "Almenn ábending" under a category also called
                    // "Almenn ábending" (#40). That subtitle was the city's own
                    // taxonomy and told a walker nothing they could act on;
                    // removing it fixes the collision at the root rather than
                    // renaming one half of it.
                    state.categoryHelp[category.slug]?.let { help ->
                        Text(
                            help,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        OutlinedTextField(
            value = state.description,
            onValueChange = onDescriptionChange,
            label = { Text("Lýsing") },
            supportingText = {
                Text("${state.description.length} / ${state.descriptionMaxLength}")
            },
            minLines = 4,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )

        Button(
            onClick = onContinue,
            enabled = state.selectedSlug != null && state.description.isNotBlank(),
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        ) { Text("Áfram") }
        if (state.selectedSlug == null || state.description.isBlank()) {
            Text(
                "Veldu flokk og skrifaðu lýsingu til að halda áfram. Borgin krefst lýsingar.",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
