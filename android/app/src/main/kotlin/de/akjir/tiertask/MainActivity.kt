package de.akjir.tiertask

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_VERSION_CHANNEL_NAME = "de.akjir.tiertask/app_version"
        private const val CHANNEL_NAME = "de.akjir.tiertask/location"
        private const val LINK_LAUNCHER_CHANNEL_NAME = "de.akjir.tiertask/link_launcher"
        private const val PERMISSION_REQUEST_CODE = 4102
        private const val MAX_CACHE_AGE_NANOS = 5L * 60L * 1_000_000_000L
        private const val ACTIVE_FIX_TIMEOUT_MS = 8_000L
        private const val MIN_GEOCODE_DISPLACEMENT_METERS = 100.0f
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val geocodeExecutor = Executors.newSingleThreadExecutor()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var activeCancellationSignal: CancellationSignal? = null
    private var activeLegacyListener: LocationListener? = null
    private var lastGeocodedLat: Double? = null
    private var lastGeocodedLon: Double? = null
    private var lastPlaceName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_VERSION_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAppVersion") {
                    result.success(getString(R.string.tiertask_full_version))
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "getLocation") {
                    handleGetLocation(result)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINK_LAUNCHER_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "openLink") {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("INVALID_URI", "URI is empty.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (error: ActivityNotFoundException) {
                        result.error("LAUNCH_FAILED", error.message ?: "No activity found to handle URI.", null)
                    } catch (error: SecurityException) {
                        result.error("LAUNCH_FAILED", error.message ?: "Security exception launching URI.", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onStop() {
        cancelActiveLocationRequest()
        pendingPermissionResult?.success(mapOf("status" to "unavailable"))
        pendingPermissionResult = null
        super.onStop()
    }

    override fun onDestroy() {
        cancelActiveLocationRequest()
        geocodeExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) {
            return
        }
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            resolveLocationWithPermission(result)
        } else {
            result.success(mapOf("status" to "unavailable"))
        }
    }

    private fun handleGetLocation(result: MethodChannel.Result) {
        if (hasForegroundLocationPermission()) {
            resolveLocationWithPermission(result)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            PERMISSION_REQUEST_CODE
        )
    }

    private fun hasForegroundLocationPermission(): Boolean {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @SuppressLint("MissingPermission")
    private fun resolveLocationWithPermission(result: MethodChannel.Result) {
        val locationManager =
            getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }

        val cachedLocation = findFreshLastKnownLocation(locationManager)
        if (cachedLocation != null) {
            deliverLocationResult(cachedLocation, result)
            return
        }

        val provider = selectActiveProvider(locationManager)
        if (provider == null) {
            result.success(mapOf("status" to "unavailable"))
            return
        }

        requestSingleActiveLocation(locationManager, provider, result)
    }

    @SuppressLint("MissingPermission")
    private fun findFreshLastKnownLocation(locationManager: LocationManager): Location? {
        val nowNanos = SystemClock.elapsedRealtimeNanos()
        val providers = listOf("fused", LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
        var bestLocation: Location? = null

        for (provider in providers) {
            val candidate = try {
                locationManager.getLastKnownLocation(provider)
            } catch (_: Exception) {
                null
            } ?: continue

            val ageNanos = nowNanos - candidate.elapsedRealtimeNanos
            if (ageNanos < 0L || ageNanos > MAX_CACHE_AGE_NANOS) {
                continue
            }
            val currentBest = bestLocation
            if (currentBest == null ||
                candidate.elapsedRealtimeNanos > currentBest.elapsedRealtimeNanos
            ) {
                bestLocation = candidate
            }
        }
        return bestLocation
    }

    private fun selectActiveProvider(locationManager: LocationManager): String? {
        val candidates = listOf("fused", LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
        for (provider in candidates) {
            val enabled = try {
                locationManager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
            if (enabled) {
                return provider
            }
        }
        return null
    }

    @SuppressLint("MissingPermission")
    private fun requestSingleActiveLocation(
        locationManager: LocationManager,
        provider: String,
        result: MethodChannel.Result
    ) {
        cancelActiveLocationRequest()
        var completed = false

        val completeOnce: (Location?) -> Unit = { location ->
            if (!completed) {
                completed = true
                cancelActiveLocationRequest()
                if (location != null) {
                    deliverLocationResult(location, result)
                } else {
                    result.success(mapOf("status" to "unavailable"))
                }
            }
        }

        mainHandler.postDelayed({ completeOnce(null) }, ACTIVE_FIX_TIMEOUT_MS)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val signal = CancellationSignal()
                activeCancellationSignal = signal
                locationManager.getCurrentLocation(
                    provider,
                    signal,
                    mainExecutor
                ) { location ->
                    completeOnce(location)
                }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        completeOnce(location)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onStatusChanged(p: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(p: String) {}
                    override fun onProviderDisabled(p: String) {
                        completeOnce(null)
                    }
                }
                activeLegacyListener = listener
                @Suppress("DEPRECATION")
                locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
            }
        } catch (_: Exception) {
            completeOnce(null)
        }
    }

    private fun cancelActiveLocationRequest() {
        activeCancellationSignal?.cancel()
        activeCancellationSignal = null
        val listener = activeLegacyListener
        if (listener != null) {
            val locationManager =
                getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            try {
                locationManager?.removeUpdates(listener)
            } catch (_: Exception) {
            }
            activeLegacyListener = null
        }
    }

    private fun deliverLocationResult(location: Location, result: MethodChannel.Result) {
        val lat = location.latitude
        val lon = location.longitude
        val source = if (location.provider == LocationManager.GPS_PROVIDER) "gps" else "system"
        val prevLat = lastGeocodedLat
        val prevLon = lastGeocodedLon
        val cachedName = lastPlaceName

        if (prevLat != null && prevLon != null && cachedName != null) {
            val distance = FloatArray(1)
            Location.distanceBetween(prevLat, prevLon, lat, lon, distance)
            if (distance[0] < MIN_GEOCODE_DISPLACEMENT_METERS) {
                result.success(
                    mapOf(
                        "status" to "found",
                        "latitude" to lat,
                        "longitude" to lon,
                        "placeName" to cachedName,
                        "source" to source
                    )
                )
                return
            }
        }

        if (!Geocoder.isPresent()) {
            result.success(
                mapOf(
                    "status" to "found",
                    "latitude" to lat,
                    "longitude" to lon,
                    "source" to source
                )
            )
            return
        }

        geocodeExecutor.execute {
            val resolvedName = resolvePlaceNameBlocking(lat, lon)
            mainHandler.post {
                if (resolvedName != null) {
                    lastGeocodedLat = lat
                    lastGeocodedLon = lon
                    lastPlaceName = resolvedName
                }
                val payload = mutableMapOf<String, Any>(
                    "status" to "found",
                    "latitude" to lat,
                    "longitude" to lon,
                    "source" to source
                )
                if (resolvedName != null) {
                    payload["placeName"] = resolvedName
                }
                result.success(payload)
            }
        }
    }

    private fun resolvePlaceNameBlocking(lat: Double, lon: Double): String? {
        return try {
            val geocoder = Geocoder(this, Locale.getDefault())
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(lat, lon, 1)
            val address = addresses?.firstOrNull() ?: return null
            val locality = address.locality ?: address.subAdminArea ?: address.adminArea
            val country = address.countryName
            when {
                !locality.isNullOrBlank() && !country.isNullOrBlank() -> "$locality, $country"
                !locality.isNullOrBlank() -> locality
                !country.isNullOrBlank() -> country
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }
}
