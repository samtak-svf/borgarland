package `is`.borgarland.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.os.SystemClock
import android.os.Build
import `is`.borgarland.data.Settings as GallerySettings
import `is`.borgarland.data.StorageAsks
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import `is`.borgarland.PocUiState
import `is`.borgarland.data.LocationAsks
import `is`.borgarland.data.LocationPermission
import `is`.borgarland.Photo
import `is`.borgarland.net.Telemetry
import `is`.borgarland.net.TelemetryEvent

/**
 * The app opens here. The camera is the entry point and there is no path that
 * starts with a form (decisions/0004). A captured photo is resolved to a
 * coordinate: EXIF GPS first, device fix as fallback, and no way forward
 * without one (the guard the city does not have).
 */
@Composable
fun CameraScreen(
    state: PocUiState,
    onPhotoCaptured: (bytes: ByteArray, rotationDegrees: Int, captureElapsedMs: Int) -> Unit,
    onPhotoError: (String) -> Unit,
    onRetakePhoto: () -> Unit,
    onLocationPermissionResult: (granted: Boolean, permanentlyDenied: Boolean) -> Unit,
    onLocationPermissionRechecked: (Boolean) -> Unit,
    onRequestDeviceFix: () -> Unit,
    onSaveToGallery: () -> Unit,
    onStoragePermissionResult: () -> Unit,
) {
    val context = LocalContext.current
    var cameraPermissionGranted by remember { mutableStateOf(hasPermission(context, Manifest.permission.CAMERA)) }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        cameraPermissionGranted = granted
        Telemetry.shared.track(TelemetryEvent.CameraPermission(granted))
    }

    // Both permissions in one request, because on Android 12 and later the
    // dialog lets the user answer a FINE request with "Approximate". Asking for
    // only FINE means that press denies us outright; asking for both means it
    // grants coarse, which is worse than a real fix and much better than none.
    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        val granted = results.values.any { it }
        // Where the permission STANDS, which is not the same question as
        // whether it is granted (#76, and the decision itself is tested in
        // data/Decisions.kt per #89).
        val standing = LocationPermission.of(granted, shouldShowLocationRationale(context))
        // Android's own way of saying "the dialog will not come back": after a
        // refusal, no rationale means the system has stopped asking, and only
        // app settings can undo it. Read AFTER the launcher answers, because
        // before the first ask it reads false too and would call an
        // unanswered permission a denied one (#76).
        onLocationPermissionResult(granted, standing == LocationPermission.DENIED_FOR_GOOD)
    }
    // The gallery save's permission cliff (#179): on API 26–28 saving a
    // photograph needs WRITE_EXTERNAL_STORAGE, and on API 29+ it needs
    // nothing. The launcher exists only where it can matter; the manifest
    // declares the permission with maxSdkVersion=28 so it never appears on
    // newer devices.
    val storagePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) onSaveToGallery()
        // The answer, either way (#201). This callback is the moment the
        // permission state changes and nothing used to recompute from it, so
        // a denial left the Details caption claiming the photograph was saved
        // until the process restarted.
        onStoragePermissionResult()
    }

    // The save is the model's job; the ASK is this screen's. When the save is
    // wanted on an API level that needs the permission and it is not granted,
    // the shutter fires the request and the model re-saves the photo it is
    // holding if the person says yes. A denial costs the gallery copy of THIS
    // photo and nothing else — the report path is untouched.
    val captureHandler: (bytes: ByteArray, rotationDegrees: Int, captureElapsedMs: Int) -> Unit =
        { bytes, rotation, elapsed ->
            if (
                Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                GallerySettings.saveToGallery(context) &&
                !hasPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            ) {
                StorageAsks.remember(context)
                storagePermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
            onPhotoCaptured(bytes, rotation, elapsed)
        }

    // The way back from app settings, which is the only place a denied
    // location permission can be opened. Without this the person returns to a
    // screen still showing the refusal they just undid (#76).
    val recheck by rememberUpdatedState(onLocationPermissionRechecked)
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                recheck(hasAnyLocationPermission(context))
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // The observed camera permission state on entry, exactly as the iOS shell
    // tracks it: a person who has already denied still gets counted, which is
    // the friction the channel measures.
    LaunchedEffect(Unit) {
        Telemetry.shared.track(TelemetryEvent.CameraPermission(hasPermission(context, Manifest.permission.CAMERA)))
    }

    LaunchedEffect(state.needsLocationPermission) {
        if (state.needsLocationPermission) {
            if (hasAnyLocationPermission(context)) {
                Telemetry.shared.track(TelemetryEvent.LocationPermission(true))
                onRequestDeviceFix()
            } else {
                askForLocation(context, locationPermissionLauncher)
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
        Text(
            "Borgarland",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(16.dp),
        )
        state.photoError?.let {
            Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp))
        }
        if (state.photo == null) {
            Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
                CameraPreview(
                    enabled = cameraPermissionGranted,
                    onPhotoCaptured = captureHandler,
                    onPhotoError = onPhotoError,
                )
            }
            Text(
                "Taktu mynd af því sem þú sérð. Staðsetningin kemur úr myndinni, annars úr tækinu.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            if (!cameraPermissionGranted) {
                Button(
                    onClick = { cameraPermissionLauncher.launch(Manifest.permission.CAMERA) },
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                ) {
                    Text("Veita aðgang að myndavélinni")
                }
            }
        } else {
            CapturedPhoto(state.photo, state, onRetakePhoto, onRequestDeviceFix, locationPermissionLauncher)
        }
    }
}

@Composable
private fun ColumnScope.CapturedPhoto(
    photo: Photo,
    state: PocUiState,
    onRetakePhoto: () -> Unit,
    onRequestDeviceFix: () -> Unit,
    locationPermissionLauncher: androidx.activity.result.ActivityResultLauncher<Array<String>>,
) {
    val context = LocalContext.current
    val bitmap = remember(photo.bytes, photo.rotationDegrees) { decodePhoto(photo.bytes, photo.rotationDegrees) }
    Image(
        bitmap = bitmap.asImageBitmap(),
        contentDescription = "tekin mynd",
        modifier = Modifier
            .fillMaxWidth()
            .weight(1f)
            .padding(16.dp)
            .clip(RoundedCornerShape(12.dp)),
        contentScale = ContentScale.Fit,
    )
    when {
        state.locating -> {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(16.dp),
            ) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Myndin ber enga GPS staðsetningu. Sæki staðsetningu úr tækinu...")
            }
        }

        state.locationError != null -> {
            Card(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(state.locationError, color = MaterialTheme.colorScheme.onErrorContainer)
                    Spacer(Modifier.height(8.dp))
                    Row {
                        if (state.locationDenied) {
                            // The dialog will not come back, so Reyna aftur
                            // could only return the same refusal forever. The
                            // one place the decision can be undone is app
                            // settings, so that is the button (#76).
                            Button(onClick = { openAppSettings(context) }) { Text("Opna stillingar") }
                        } else {
                            Button(onClick = {
                                if (hasAnyLocationPermission(context)) {
                                    onRequestDeviceFix()
                                } else {
                                    askForLocation(context, locationPermissionLauncher)
                                }
                            }) { Text("Reyna aftur") }
                        }
                        Spacer(Modifier.width(8.dp))
                        OutlinedButton(onClick = onRetakePhoto) { Text("Taka nýja mynd") }
                    }
                }
            }
        }

        state.coordinate != null -> {
            Text(
                "Staðsetning: ${state.locationSource.orEmpty()}",
                modifier = Modifier.padding(16.dp),
            )
        }
    }
}

@Composable
private fun CameraPreview(
    enabled: Boolean,
    onPhotoCaptured: (bytes: ByteArray, rotationDegrees: Int, captureElapsedMs: Int) -> Unit,
    onPhotoError: (String) -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { ContextCompat.getMainExecutor(context) }
    val cameraProviderFuture = remember { ProcessCameraProvider.getInstance(context) }
    val imageCapture = remember {
        ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .build()
    }
    var previewView by remember { mutableStateOf<PreviewView?>(null) }
    var bound by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.fillMaxWidth().weight(1f).background(Color.Black)) {
            AndroidView(
                modifier = Modifier.fillMaxSize(),
                factory = { ctx ->
                    PreviewView(ctx).also { view ->
                        view.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                        previewView = view
                    }
                },
            )
        }

        LaunchedEffect(enabled, previewView) {
            if (!enabled || bound || previewView == null) return@LaunchedEffect
            val provider = runCatching { cameraProviderFuture.get() }.getOrNull() ?: return@LaunchedEffect
            val view = previewView ?: return@LaunchedEffect
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(view.surfaceProvider) }
            runCatching {
                provider.unbindAll()
                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageCapture)
            }.onFailure { onPhotoError(it.message ?: "gat ekki tengst myndavélinni") }
            bound = true
        }

        DisposableEffect(Unit) {
            onDispose {
                runCatching { cameraProviderFuture.get().unbindAll() }
            }
        }

        Button(
            onClick = {
                // Shutter-to-bytes, the telemetry channel's photo-captured
                // elapsedMs. SystemClock.elapsedRealtime is monotonic, so a
                // wall-clock jump cannot skew the measurement.
                val captureStart = SystemClock.elapsedRealtime()
                imageCapture.takePicture(executor, object : ImageCapture.OnImageCapturedCallback() {
                    override fun onCaptureSuccess(image: ImageProxy) {
                        val bytes = image.jpegBytes()
                        val rotation = image.imageInfo.rotationDegrees
                        val elapsedMs = (SystemClock.elapsedRealtime() - captureStart).toInt()
                        image.close()
                        if (bytes != null) {
                            onPhotoCaptured(bytes, rotation, elapsedMs)
                        } else {
                            onPhotoError("myndin kom ekki í JPEG")
                        }
                    }

                    override fun onError(exception: ImageCaptureException) {
                        onPhotoError(exception.message ?: "myndataka mistókst")
                    }
                })
            },
            enabled = bound && enabled,
            modifier = Modifier.fillMaxWidth().padding(16.dp),
        ) { Text("Taka mynd") }
    }
}

/**
 * The two location permissions, always requested together. See the manifest for
 * why: on Android 12 and later, asking for FINE alone lets the user press
 * "Approximate" and get us nothing at all.
 */
private val LOCATION_PERMISSIONS = arrayOf(
    Manifest.permission.ACCESS_FINE_LOCATION,
    Manifest.permission.ACCESS_COARSE_LOCATION,
)

/**
 * Whether the app can ask for a position at all. Either permission counts:
 * coarse is not accurate enough to find a bin, and the report is still better
 * placed than one with no coordinate, which the relay refuses outright.
 */
private fun hasAnyLocationPermission(context: Context): Boolean =
    LOCATION_PERMISSIONS.any { hasPermission(context, it) }

private fun hasPermission(context: Context, permission: String): Boolean =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

/**
 * Fire the permission launcher, and count it as an ask only when one is
 * actually going to be shown (#139).
 *
 * The launcher runs either way, because its callback is what tells the model
 * where the permission stands and puts the Opna stillingar exit in front of
 * somebody who needs it. What is conditional is the EVENT: on a phone that has
 * refused for good the launcher answers immediately with no dialog, and
 * `onPhotoCaptured` clears `locationDenied` on every photo, so an unguarded
 * emit here re-counted an ask that never happened for every subsequent photo
 * with no usable EXIF GPS.
 *
 * The order matters. [LocationAsks.remember] runs AFTER the decision is taken,
 * because the decision is about the state before this ask.
 */
private fun askForLocation(
    context: Context,
    launcher: androidx.activity.result.ActivityResultLauncher<Array<String>>,
) {
    val willPrompt = LocationPermission.willPrompt(
        granted = hasAnyLocationPermission(context),
        canAskAgain = shouldShowLocationRationale(context),
        askedBefore = LocationAsks.asked(context),
    )
    if (willPrompt) {
        Telemetry.shared.track(TelemetryEvent.LocationPermissionAsked)
    }
    LocationAsks.remember(context)
    launcher.launch(LOCATION_PERMISSIONS)
}

/**
 * Whether Android would still show the permission dialog. False after a
 * refusal means it has stopped asking, and only app settings can change the
 * answer. Meaningful ONLY after a request has been answered: before the first
 * ask it is false as well, and reading it then calls an unanswered permission
 * a denied one (#76).
 *
 * Any of the two counts, matching [hasAnyLocationPermission]: while the system
 * will still offer either, the dialog is worth showing.
 */
private fun shouldShowLocationRationale(context: Context): Boolean {
    // TRUE when the question cannot be asked. The caller reads a false answer
    // as "denied for good" and sends the person to system settings, so an
    // unanswerable question must fail towards the retry that might work rather
    // than towards a screen telling somebody their own device is locked when it
    // is not. Reliable today, because this screen is only ever composed from
    // MainActivity, where LocalContext IS the Activity.
    val activity = context as? Activity ?: return true
    return LOCATION_PERMISSIONS.any { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
}

/**
 * The app's own page in system settings, where a denied permission is undone.
 * Package-scoped rather than the general location settings screen: the general
 * one is about the device, and the decision that blocks this walk is about this
 * app (#76).
 */
private fun openAppSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null),
    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
    runCatching { context.startActivity(intent) }
}

private fun ImageProxy.jpegBytes(): ByteArray? {
    if (format != ImageFormat.JPEG) return null
    val buffer = planes[0].buffer
    val bytes = ByteArray(buffer.remaining())
    buffer.get(bytes)
    return bytes
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
