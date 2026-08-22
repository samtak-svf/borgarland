package `is`.borgarland.poc

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import `is`.borgarland.poc.ui.BorgarlandPocTheme
import `is`.borgarland.poc.ui.CameraScreen
import `is`.borgarland.poc.ui.DetailsScreen
import `is`.borgarland.poc.ui.SummaryScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            BorgarlandPocTheme {
                val viewModel: PocViewModel = viewModel()
                val state by viewModel.state.collectAsStateWithLifecycle()

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
}
