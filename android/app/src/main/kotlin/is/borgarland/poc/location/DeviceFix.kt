package `is`.borgarland.poc.location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Fallback location source for a photo that carries no EXIF GPS. Uses the
 * framework LocationManager only, no play-services dependency.
 *
 * Every enabled provider is asked, not just GPS. Testing on a real device
 * indoors found the reason: GPS never fixes under a roof, so a GPS-only
 * request times out and the report is refused, while the network and fused
 * providers were sitting on a three-minute-old fix accurate to eighteen
 * metres. The same happens in a courtyard, under trees and beside a tall
 * building, which is most of where these reports get made.
 *
 * Returns null only when no provider has anything, and the caller then
 * refuses to continue rather than sending a report nobody can act on.
 *
 * **On the `MissingPermission` suppression.** Every LocationManager call below
 * is wrapped in `runCatching`, so a SecurityException from a permission the
 * user revoked between the check and the call is caught and read as "this
 * provider has nothing" — exactly how the class already treats a provider that
 * cannot answer. Android lint cannot see that: it looks for an explicit
 * permission check or a named SecurityException catch at the call site and
 * finds neither. The suppression says the handling exists, not that the
 * permission does not matter; PocViewModel asks for ACCESS_FINE_LOCATION before
 * it ever constructs this, and refuses to continue without a coordinate.
 */
@SuppressLint("MissingPermission")
class DeviceFix(context: Context) {

    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    suspend fun request(timeoutMillis: Long = 15_000): Location? {
        val manager = manager ?: return null
        lastKnown(manager)?.let { return it }
        return liveFix(manager, timeoutMillis)
    }

    /** The freshest usable fix any provider is already holding. */
    private fun lastKnown(manager: LocationManager): Location? =
        providers(manager)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { usable(it) }
            .maxByOrNull { it.time }

    private fun providers(manager: LocationManager): List<String> =
        runCatching { manager.getProviders(true) }.getOrNull()
            ?.takeIf { it.isNotEmpty() }
            ?: listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)

    private suspend fun liveFix(manager: LocationManager, timeoutMillis: Long): Location? {
        var listener: LocationListener? = null
        val fix = withTimeoutOrNull(timeoutMillis) {
            suspendCancellableCoroutine { cont ->
                val l = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        if (!cont.isCompleted) cont.resume(location)
                    }
                }
                listener = l
                // Ask every enabled provider at once and take whichever
                // answers first. Indoors that is the network provider; outside
                // it is usually GPS, and outside is where the accuracy matters.
                val requested = providers(manager).count { provider ->
                    runCatching {
                        manager.requestLocationUpdates(
                            provider, 0L, 0f, l, Looper.getMainLooper(),
                        )
                    }.isSuccess
                }
                if (requested == 0) cont.resume(null)
                cont.invokeOnCancellation { runCatching { manager.removeUpdates(l) } }
            }
        }
        listener?.let { runCatching { manager.removeUpdates(it) } }
        return fix?.takeIf { usable(it) }
    }

    private fun usable(location: Location): Boolean =
        location.latitude.isFinite() && location.longitude.isFinite()
}
