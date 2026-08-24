package `is`.borgarland.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

/**
 * "Was it fixed?", asked once, about one report this phone filed (#57,
 * [decision 0013](../../../../../../../decisions/0013-the-follow-up-asks-the-phone-not-the-person.md)).
 *
 * Three ways out and all of them end the question: yes, no, and not now. The
 * last one is not a postponement, because a question that comes back is a nag
 * and the model marks the report asked either way.
 *
 * The wording avoids claiming the city did anything. It asks what the person
 * can actually know, which is whether the thing is still there.
 */
@Composable
fun FollowUpDialog(
    categoryLabel: String,
    onAnswer: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Var þetta lagað?") },
        text = {
            Text(
                "Þú sendir ábendingu um $categoryLabel fyrir um tveimur vikum. " +
                    "Er búið að laga það?",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        confirmButton = {
            TextButton(onClick = { onAnswer(true) }) { Text("Já, lagað") }
        },
        dismissButton = {
            TextButton(onClick = { onAnswer(false) }) { Text("Nei, óbreytt") }
        },
    )
}
