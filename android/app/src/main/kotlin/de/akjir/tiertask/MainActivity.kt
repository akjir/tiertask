package de.akjir.tiertask

import android.Manifest
import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Address
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
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_STORAGE_CHANNEL_NAME = "de.akjir.tiertask/app_storage"
        private const val APP_VERSION_CHANNEL_NAME = "de.akjir.tiertask/app_version"
        private const val CHANNEL_NAME = "de.akjir.tiertask/location"
        private const val LINK_LAUNCHER_CHANNEL_NAME = "de.akjir.tiertask/link_launcher"
        private const val PERMISSION_REQUEST_CODE = 4102
        private const val MAX_CACHE_AGE_NANOS = 5L * 60L * 1_000_000_000L
        private const val ACTIVE_FIX_TIMEOUT_MS = 8_000L
        private const val GEOCODE_TIMEOUT_MS = 3_000L
        private const val MIN_GEOCODE_DISPLACEMENT_METERS = 100.0f

        private val BLOCKED_URI_SCHEMES: Set<String> = setOf(
            "about",
            "blob",
            "cifs",
            "cmd",
            "content",
            "cscript",
            "data",
            "file",
            "hcp",
            "intent",
            "its",
            "jar",
            "javascript",
            "jscript",
            "livescript",
            "mhtml",
            "mk",
            "ms-appinstaller",
            "ms-msdt",
            "nfs",
            "powershell",
            "res",
            "search-ms",
            "shell",
            "smb",
            "vbscript",
            "view-source",
            "wscript"
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val geocodeExecutor = Executors.newSingleThreadExecutor()
    private val pendingGeocodeTimeouts = mutableSetOf<Runnable>()

    private var appStorageChannel: MethodChannel? = null
    private var appVersionChannel: MethodChannel? = null
    private var locationChannel: MethodChannel? = null
    private var linkLauncherChannel: MethodChannel? = null

    @Volatile
    private var isEngineAttached = false
    @Volatile
    private var isActivityDestroyed = false

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var activeLocationResult: MethodChannel.Result? = null
    private var activeTimeoutRunnable: Runnable? = null
    private var activeCancellationSignal: CancellationSignal? = null
    private var activeLegacyListener: LocationListener? = null
    private var lastGeocodedLat: Double? = null
    private var lastGeocodedLon: Double? = null
    private var lastPlaceName: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        isEngineAttached = true
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        appStorageChannel = MethodChannel(messenger, APP_STORAGE_CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getFilesDirectory") {
                    result.success(applicationContext.filesDir.absolutePath)
                } else {
                    result.notImplemented()
                }
            }
        }
        appVersionChannel = MethodChannel(messenger, APP_VERSION_CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getAppVersion") {
                    result.success(getString(R.string.tiertask_full_version))
                } else {
                    result.notImplemented()
                }
            }
        }
        locationChannel = MethodChannel(messenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getLocation") {
                    handleGetLocation(result)
                } else {
                    result.notImplemented()
                }
            }
        }
        linkLauncherChannel = MethodChannel(messenger, LINK_LAUNCHER_CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "openLink") {
                    handleOpenLink(call.argument<String>("uri"), result)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        isEngineAttached = false
        appStorageChannel?.setMethodCallHandler(null)
        appStorageChannel = null
        appVersionChannel?.setMethodCallHandler(null)
        appVersionChannel = null
        locationChannel?.setMethodCallHandler(null)
        locationChannel = null
        linkLauncherChannel?.setMethodCallHandler(null)
        linkLauncherChannel = null
        cancelActiveLocationRequest()
        cancelPendingGeocodeTimeouts()
        pendingPermissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        cancelActiveLocationRequest()
        super.onStop()
    }

    override fun onDestroy() {
        isActivityDestroyed = true
        cancelActiveLocationRequest()
        cancelPendingGeocodeTimeouts()
        val permissionResult = pendingPermissionResult
        pendingPermissionResult = null
        if (permissionResult != null && !isDestroyed && isEngineAttached) {
            replySafely(permissionResult, mapOf("status" to "unavailable"))
        }
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
        if (!canDeliverResult()) {
            return
        }
        val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        if (granted) {
            resolveLocationWithPermission(result)
        } else {
            deliverUnavailable(result)
        }
    }

    private fun handleOpenLink(uri: String?, result: MethodChannel.Result) {
        if (uri == null || !isLaunchableUri(uri)) {
            result.error("INVALID_URI", "URI is invalid or uses a blocked scheme.", null)
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("LAUNCH_FAILED", "No activity found to handle URI.", null)
        } catch (_: SecurityException) {
            result.error("LAUNCH_FAILED", "Security exception launching URI.", null)
        } catch (_: RuntimeException) {
            result.error("LAUNCH_FAILED", "Failed to launch URI.", null)
        }
    }

    private fun isLaunchableUri(rawUri: String): Boolean {
        if (rawUri.isEmpty()) {
            return false
        }
        val firstChar = rawUri.first()
        val lastChar = rawUri.last()
        if (firstChar.isWhitespace() ||
            Character.isSpaceChar(firstChar) ||
            lastChar.isWhitespace() ||
            Character.isSpaceChar(lastChar)
        ) {
            return false
        }

        var colonIndex = -1
        for (index in rawUri.indices) {
            val code = rawUri[index].code
            if (code <= 0x1F ||
                code == 0x7F ||
                code in 0x80..0x9F ||
                code == 0x061C ||
                code == 0x200E ||
                code == 0x200F ||
                code == 0x2028 ||
                code == 0x2029 ||
                code in 0x202A..0x202E ||
                code in 0x2066..0x2069
            ) {
                return false
            }
            if (colonIndex == -1 && code == ':'.code) {
                colonIndex = index
            }
        }

        if (colonIndex < 2 || colonIndex == rawUri.lastIndex) {
            return false
        }
        if (!isAsciiAlpha(firstChar)) {
            return false
        }
        for (index in 1 until colonIndex) {
            if (!isSchemeContinueChar(rawUri[index])) {
                return false
            }
        }

        val scheme = rawUri.substring(0, colonIndex).lowercase(Locale.ROOT)
        return !BLOCKED_URI_SCHEMES.contains(scheme)
    }

    private fun isAsciiAlpha(character: Char): Boolean {
        return character in 'A'..'Z' || character in 'a'..'z'
    }

    private fun isSchemeContinueChar(character: Char): Boolean {
        return isAsciiAlpha(character) ||
            character in '0'..'9' ||
            character == '+' ||
            character == '.' ||
            character == '-'
    }

    private fun handleGetLocation(result: MethodChannel.Result) {
        if (hasForegroundLocationPermission()) {
            resolveLocationWithPermission(result)
            return
        }
        cancelActiveLocationRequest()
        if (pendingPermissionResult != null) {
            deliverUnavailable(result)
            return
        }
        pendingPermissionResult = result
        try {
            requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                PERMISSION_REQUEST_CODE
            )
        } catch (_: RuntimeException) {
            pendingPermissionResult = null
            deliverUnavailable(result)
        }
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
        cancelActiveLocationRequest()

        val locationManager =
            getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (locationManager == null) {
            deliverUnavailable(result)
            return
        }

        val cachedLocation = findFreshLastKnownLocation(locationManager)
        if (cachedLocation != null) {
            deliverLocationResult(cachedLocation, result)
            return
        }

        val provider = selectActiveProvider(locationManager)
        if (provider == null) {
            deliverUnavailable(result)
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
        activeLocationResult = result

        val completeOnce: (Location?) -> Unit = { location ->
            if (activeLocationResult === result) {
                activeLocationResult = null
                cancelActiveLocationRequest()
                if (location != null) {
                    deliverLocationResult(location, result)
                } else {
                    deliverUnavailable(result)
                }
            }
        }

        val timeoutRunnable = Runnable { completeOnce(null) }
        activeTimeoutRunnable = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, ACTIVE_FIX_TIMEOUT_MS)

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
        val timeoutRunnable = activeTimeoutRunnable
        if (timeoutRunnable != null) {
            mainHandler.removeCallbacks(timeoutRunnable)
            activeTimeoutRunnable = null
        }
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
        val pendingResult = activeLocationResult
        if (pendingResult != null) {
            activeLocationResult = null
            deliverUnavailable(pendingResult)
        }
    }

    private fun cancelPendingGeocodeTimeouts() {
        for (timeoutRunnable in pendingGeocodeTimeouts) {
            mainHandler.removeCallbacks(timeoutRunnable)
        }
        pendingGeocodeTimeouts.clear()
    }

    private fun deliverLocationResult(location: Location, result: MethodChannel.Result) {
        if (!canDeliverResult()) {
            return
        }
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
                deliverFoundLocation(
                    lat = lat,
                    lon = lon,
                    source = source,
                    placeName = cachedName,
                    result = result,
                    updateCache = false
                )
                return
            }
        }

        if (!Geocoder.isPresent()) {
            deliverFoundLocation(
                lat = lat,
                lon = lon,
                source = source,
                placeName = null,
                result = result,
                updateCache = false
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            resolvePlaceNameAsyncApi33(lat, lon, source, result)
        } else {
            resolvePlaceNameLegacy(lat, lon, source, result)
        }
    }

    @TargetApi(Build.VERSION_CODES.TIRAMISU)
    private fun resolvePlaceNameAsyncApi33(
        lat: Double,
        lon: Double,
        source: String,
        result: MethodChannel.Result
    ) {
        val completed = AtomicBoolean(false)
        val timeout = object : Runnable {
            override fun run() {
                pendingGeocodeTimeouts.remove(this)
                if (completed.compareAndSet(false, true)) {
                    deliverFoundLocation(
                        lat = lat,
                        lon = lon,
                        source = source,
                        placeName = null,
                        result = result,
                        updateCache = false
                    )
                }
            }
        }

        val finishOnMain: (String?) -> Unit = { resolvedName ->
            if (completed.compareAndSet(false, true)) {
                mainHandler.post {
                    mainHandler.removeCallbacks(timeout)
                    pendingGeocodeTimeouts.remove(timeout)
                    deliverFoundLocation(
                        lat = lat,
                        lon = lon,
                        source = source,
                        placeName = resolvedName,
                        result = result,
                        updateCache = resolvedName != null
                    )
                }
            }
        }

        pendingGeocodeTimeouts.add(timeout)
        mainHandler.postDelayed(timeout, GEOCODE_TIMEOUT_MS)

        try {
            val geocoder = Geocoder(applicationContext, Locale.getDefault())
            geocoder.getFromLocation(
                lat,
                lon,
                1,
                object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<Address>) {
                        finishOnMain(formatPlaceName(addresses))
                    }

                    override fun onError(errorMessage: String?) {
                        finishOnMain(null)
                    }
                }
            )
        } catch (_: Exception) {
            if (completed.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeout)
                pendingGeocodeTimeouts.remove(timeout)
                deliverFoundLocation(
                    lat = lat,
                    lon = lon,
                    source = source,
                    placeName = null,
                    result = result,
                    updateCache = false
                )
            }
        }
    }

    private fun resolvePlaceNameLegacy(
        lat: Double,
        lon: Double,
        source: String,
        result: MethodChannel.Result
    ) {
        if (isActivityDestroyed || !isEngineAttached || geocodeExecutor.isShutdown) {
            deliverFoundLocation(
                lat = lat,
                lon = lon,
                source = source,
                placeName = null,
                result = result,
                updateCache = false
            )
            return
        }

        val appContext = applicationContext
        try {
            geocodeExecutor.execute {
                if (isActivityDestroyed || !isEngineAttached) {
                    return@execute
                }
                val resolvedName = resolvePlaceNameBlocking(appContext, lat, lon)
                mainHandler.post {
                    deliverFoundLocation(
                        lat = lat,
                        lon = lon,
                        source = source,
                        placeName = resolvedName,
                        result = result,
                        updateCache = resolvedName != null
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            deliverFoundLocation(
                lat = lat,
                lon = lon,
                source = source,
                placeName = null,
                result = result,
                updateCache = false
            )
        }
    }

    private fun resolvePlaceNameBlocking(
        appContext: Context,
        lat: Double,
        lon: Double
    ): String? {
        return try {
            val geocoder = Geocoder(appContext, Locale.getDefault())
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(lat, lon, 1)
            formatPlaceName(addresses)
        } catch (_: Exception) {
            null
        }
    }

    private fun formatPlaceName(addresses: List<Address>?): String? {
        val address = addresses?.firstOrNull() ?: return null
        val locality = address.locality ?: address.subAdminArea ?: address.adminArea
        val country = address.countryName
        return when {
            !locality.isNullOrBlank() && !country.isNullOrBlank() -> "$locality, $country"
            !locality.isNullOrBlank() -> locality
            !country.isNullOrBlank() -> country
            else -> null
        }
    }

    private fun deliverFoundLocation(
        lat: Double,
        lon: Double,
        source: String,
        placeName: String?,
        result: MethodChannel.Result,
        updateCache: Boolean
    ) {
        if (!canDeliverResult()) {
            return
        }
        if (updateCache && !placeName.isNullOrBlank()) {
            lastGeocodedLat = lat
            lastGeocodedLon = lon
            lastPlaceName = placeName
        }
        val payload = mutableMapOf<String, Any>(
            "status" to "found",
            "latitude" to lat,
            "longitude" to lon,
            "source" to source
        )
        if (!placeName.isNullOrBlank()) {
            payload["placeName"] = placeName
        }
        replySafely(result, payload)
    }

    private fun deliverUnavailable(result: MethodChannel.Result) {
        if (!canDeliverResult()) {
            return
        }
        replySafely(result, mapOf("status" to "unavailable"))
    }

    private fun canDeliverResult(): Boolean {
        return !isDestroyed && !isFinishing && !isActivityDestroyed && isEngineAttached
    }

    private fun replySafely(result: MethodChannel.Result, payload: Any) {
        try {
            result.success(payload)
        } catch (_: RuntimeException) {
            // Ignore replies targeting a detached or already-completed channel call.
        }
    }
}
