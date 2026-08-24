package `is`.borgarland

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import `is`.borgarland.ui.BorgarlandPocTheme
import `is`.borgarland.ui.CameraScreen
import `is`.borgarland.ui.FollowUpDialog
import `is`.borgarland.ui.DetailsScreen
import `is`.borgarland.ui.SummaryScreen
import `is`.borgarland.net.Telemetry

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            BorgarlandPocTheme {
                val viewModel: PocViewModel = viewModel()
                val state by viewModel.state.collectAsStateWithLifecycle()

                // A ViewModel is cleared when its Activity FINISHES, not when
                // the app is backgrounded, so init alone could carry a
                // ViewModel created before the fourteenth day for days
                // afterwards and never ask (#129). Re-checked on every resume.
                LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
                    viewModel.refreshFollowUp()
                    viewModel.deliverOutcomes()
                }

                // enableEdgeToEdge() draws under the status and navigation
                // bars, so something has to consume the insets or the title
                // sits under the clock and the buttons under the gesture bar.
                // Padding the whole tree once is the POC-sized fix; a
                // full-bleed preview with only its controls inset is a
                // refinement for the real screen, not a correctness change.
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    Box(Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        // The follow-up question, asked once about one report
                        // this phone filed a fortnight ago (#57, decision
                        // 0013). It sits over whatever screen is showing
                        // because it is not part of filing a report; it is a
                        // different conversation that happens to start when
                        // the app opens.
                        //
                        // ABOVE the factsError early return, deliberately
                        // (#129). Below it, a missing or unreadable facts file
                        // swallowed the question entirely: the app ran, the
                        // report was due, and nothing was asked.
                        state.followUp?.let { pending ->
                            FollowUpDialog(
                                categoryLabel = state.categoryDisplay[pending.categorySlug]
                                    ?: pending.categorySlug,
                                onAnswer = viewModel::answerFollowUp,
                                onDismiss = viewModel::dismissFollowUp,
                            )
                        }

                        state.factsError?.let { error ->
                            Text(
                                error,
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.padding(16.dp),
                            )
                            return@Box
                        }

                        when (state.screen) {
                            Screen.Camera -> CameraScreen(
                                state = state,
                                onPhotoCaptured = viewModel::onPhotoCaptured,
                                onPhotoError = viewModel::onPhotoError,
                                onRetakePhoto = viewModel::retakePhoto,
                                onLocationPermissionResult = viewModel::onLocationPermissionResult,
                                onLocationPermissionRechecked = viewModel::onLocationPermissionRechecked,
                                onRequestDeviceFix = viewModel::requestDeviceFix,
                            )

                            Screen.Details -> DetailsScreen(
                                state = state,
                                onSelectCategory = viewModel::selectCategory,
                                onDescriptionChange = viewModel::onDescriptionChange,
                                onContinue = viewModel::continueToSummary,
                            )

                            Screen.Summary -> {
                                val payload = viewModel.payload()
                                if (payload != null) {
                                    SummaryScreen(
                                        state = state,
                                        payload = payload,
                                        onStartOver = viewModel::startOver,
                                        onSend = viewModel::sendToRelay,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        // One of the telemetry channel's natural flush points: the buffer
        // goes out when the app leaves the foreground, so a session that ends
        // in the background is not lost (data/relay-events.json). The flush
        // never blocks: the network send runs on its own IO dispatcher.
        Telemetry.shared.flush()
    }
}
