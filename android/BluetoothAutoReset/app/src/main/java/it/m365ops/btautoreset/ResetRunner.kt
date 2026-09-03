package it.m365ops.btautoreset

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Build
import android.provider.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Esegue la sequenza: spegni Bluetooth -> termina Android Auto -> riaccendi Bluetooth.
 *
 * Con i permessi di root la sequenza e' completamente automatica. Senza root si usa il massimo
 * consentito dalle API pubbliche (API legacy del Bluetooth fino ad Android 12 e terminazione dei
 * soli processi in background di Android Auto), segnalando all'utente cio' che non e' stato
 * possibile fare.
 */
class ResetRunner(private val context: Context) {

    enum class Mode { UNKNOWN, ROOT, LIMITED }

    data class RunResult(val state: StepState, val message: String)

    private companion object {
        /** Varianti del pacchetto di Android Auto viste sui dispositivi in circolazione. */
        val ANDROID_AUTO_PACKAGES = listOf(
            "com.google.android.projection.gearhead",
            "com.google.android.embedded.projection",
            "com.google.android.gms.car"
        )

        const val STATE_TIMEOUT_MS = 12_000L
        const val STATE_POLL_MS = 250L
        const val SETTLE_MS = 1_500L
    }

    @Volatile
    var mode: Mode = Mode.UNKNOWN
        private set

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** Verifica una sola volta la disponibilita' della shell di root. */
    suspend fun detectMode(): Mode = withContext(Dispatchers.IO) {
        val detected = if (Shell.hasRoot()) Mode.ROOT else Mode.LIMITED
        mode = detected
        detected
    }

    /**
     * Esegue i tre passi in sequenza, notificando l'avvio e l'esito di ognuno tramite [onStep].
     * I callback vengono invocati sul thread principale.
     */
    suspend fun run(onStep: (stepId: Int, outcome: StepOutcome) -> Unit): RunResult {
        if (mode == Mode.UNKNOWN) detectMode()

        if (adapter == null) {
            val message = context.getString(R.string.error_no_bluetooth)
            ResetSteps.ALL.forEach { onStep(it.id, StepOutcome(StepState.FAILED, message)) }
            return RunResult(StepState.FAILED, message)
        }

        val outcomes = mutableListOf<StepOutcome>()

        onStep(ResetSteps.ID_DISABLE_BLUETOOTH, StepOutcome(StepState.RUNNING, context.getString(R.string.detail_working)))
        val disable = setBluetooth(enabled = false)
        onStep(ResetSteps.ID_DISABLE_BLUETOOTH, disable)
        outcomes += disable

        if (disable.state == StepState.FAILED) {
            val skipped = StepOutcome(StepState.PENDING, context.getString(R.string.detail_skipped))
            onStep(ResetSteps.ID_KILL_ANDROID_AUTO, skipped)
            onStep(ResetSteps.ID_ENABLE_BLUETOOTH, skipped)
            return RunResult(StepState.FAILED, context.getString(R.string.result_failed))
        }

        onStep(ResetSteps.ID_KILL_ANDROID_AUTO, StepOutcome(StepState.RUNNING, context.getString(R.string.detail_working)))
        val kill = killAndroidAuto()
        onStep(ResetSteps.ID_KILL_ANDROID_AUTO, kill)
        outcomes += kill

        // Lascia al sistema il tempo di liberare lo stack Bluetooth prima di riaccenderlo.
        delay(SETTLE_MS)

        onStep(ResetSteps.ID_ENABLE_BLUETOOTH, StepOutcome(StepState.RUNNING, context.getString(R.string.detail_working)))
        val enable = setBluetooth(enabled = true)
        onStep(ResetSteps.ID_ENABLE_BLUETOOTH, enable)
        outcomes += enable

        return when {
            outcomes.any { it.state == StepState.FAILED } ->
                RunResult(StepState.FAILED, context.getString(R.string.result_failed))
            outcomes.any { it.state == StepState.WARNING } ->
                RunResult(StepState.WARNING, context.getString(R.string.result_partial))
            else ->
                RunResult(StepState.DONE, context.getString(R.string.result_ok))
        }
    }

    // --- Bluetooth ------------------------------------------------------------------------

    private suspend fun setBluetooth(enabled: Boolean): StepOutcome = withContext(Dispatchers.IO) {
        if (isBluetoothOn() == enabled) {
            return@withContext StepOutcome(
                StepState.DONE,
                context.getString(if (enabled) R.string.detail_bt_already_on else R.string.detail_bt_already_off)
            )
        }

        if (mode == Mode.ROOT) {
            val command = if (enabled) "svc bluetooth enable" else "svc bluetooth disable"
            val result = Shell.exec(command)
            if (result.isSuccess && waitForBluetooth(enabled)) {
                return@withContext StepOutcome(StepState.DONE, context.getString(R.string.detail_via_root))
            }
        }

        // Fallback: API legacy, funzionanti fino ad Android 12 (API 32).
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 && toggleWithLegacyApi(enabled)) {
            if (waitForBluetooth(enabled)) {
                return@withContext StepOutcome(StepState.DONE, context.getString(R.string.detail_via_legacy_api))
            }
        }

        StepOutcome(
            StepState.FAILED,
            context.getString(if (enabled) R.string.detail_bt_enable_failed else R.string.detail_bt_disable_failed)
        )
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun toggleWithLegacyApi(enabled: Boolean): Boolean = try {
        val bluetooth = adapter
        if (bluetooth == null) false else if (enabled) bluetooth.enable() else bluetooth.disable()
    } catch (error: SecurityException) {
        false
    }

    private suspend fun waitForBluetooth(enabled: Boolean): Boolean {
        val deadline = System.currentTimeMillis() + STATE_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (isBluetoothOn() == enabled) return true
            delay(STATE_POLL_MS)
        }
        return isBluetoothOn() == enabled
    }

    /**
     * Stato dell'adattatore. Su API >= 31 `isEnabled()` richiede BLUETOOTH_CONNECT: se il permesso
     * non e' stato concesso si ripiega su `Settings.Global.bluetooth_on`, leggibile senza permessi.
     */
    @SuppressLint("MissingPermission")
    private fun isBluetoothOn(): Boolean = try {
        adapter?.isEnabled ?: false
    } catch (error: SecurityException) {
        Settings.Global.getInt(context.contentResolver, "bluetooth_on", 0) == 1
    }

    // --- Android Auto ---------------------------------------------------------------------

    private suspend fun killAndroidAuto(): StepOutcome = withContext(Dispatchers.IO) {
        val installed = ANDROID_AUTO_PACKAGES.filter { isInstalled(it) }
        if (installed.isEmpty()) {
            return@withContext StepOutcome(StepState.WARNING, context.getString(R.string.detail_auto_not_installed))
        }

        if (mode == Mode.ROOT) {
            val commands = installed.map { "am force-stop $it" }.toTypedArray()
            val result = Shell.exec(*commands)
            return@withContext if (result.isSuccess) {
                StepOutcome(StepState.DONE, context.getString(R.string.detail_auto_killed, installed.size))
            } else {
                StepOutcome(StepState.FAILED, context.getString(R.string.detail_auto_kill_failed, result.output))
            }
        }

        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        installed.forEach { packageName ->
            try {
                activityManager.killBackgroundProcesses(packageName)
            } catch (error: SecurityException) {
                return@withContext StepOutcome(StepState.WARNING, context.getString(R.string.detail_auto_kill_denied))
            }
        }
        StepOutcome(StepState.WARNING, context.getString(R.string.detail_auto_killed_partial))
    }

    private fun isInstalled(packageName: String): Boolean = try {
        context.packageManager.getPackageInfo(packageName, 0)
        true
    } catch (error: Exception) {
        false
    }
}
