package it.m365ops.btautoreset

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import it.m365ops.btautoreset.databinding.ActivityMainBinding
import it.m365ops.btautoreset.databinding.ItemStepBinding
import kotlinx.coroutines.launch

/**
 * Schermata unica: descrive la sequenza, la esegue mostrando l'avanzamento passo per passo e
 * termina con il pulsante OK.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var runner: ResetRunner

    private val rows = mutableMapOf<Int, ItemStepBinding>()
    private var finished = false

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { startSequence() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        runner = ResetRunner(applicationContext)

        buildStepRows()

        binding.actionButton.setOnClickListener {
            if (finished) finishAndRemoveTask() else requestPermissionThenStart()
        }

        lifecycleScope.launch {
            val mode = runner.detectMode()
            binding.modeText.text = getString(
                if (mode == ResetRunner.Mode.ROOT) R.string.mode_root else R.string.mode_limited
            )
        }
    }

    private fun buildStepRows() {
        ResetSteps.ALL.forEachIndexed { index, step ->
            val row = ItemStepBinding.inflate(layoutInflater, binding.stepsContainer, false)
            row.stepNumber.text = getString(R.string.step_number, index + 1)
            row.stepTitle.text = getString(step.title)
            row.stepDetail.text = getString(step.description)
            binding.stepsContainer.addView(row.root)
            rows[step.id] = row
        }
    }

    private fun requestPermissionThenStart() {
        val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) !=
            PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            permissionLauncher.launch(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            startSequence()
        }
    }

    private fun startSequence() {
        binding.actionButton.isEnabled = false
        binding.actionButton.setText(R.string.action_running)
        binding.resultText.visibility = View.GONE

        lifecycleScope.launch {
            val result = runner.run { stepId, outcome -> applyOutcome(stepId, outcome) }
            showResult(result)
        }
    }

    private fun applyOutcome(stepId: Int, outcome: StepOutcome) {
        val row = rows[stepId] ?: return
        row.stepDetail.text = outcome.detail
        val (glyph, color) = when (outcome.state) {
            StepState.PENDING -> "-" to R.color.status_pending
            StepState.RUNNING -> ">" to R.color.status_running
            StepState.DONE -> "OK" to R.color.status_done
            StepState.WARNING -> "!" to R.color.status_warning
            StepState.FAILED -> "X" to R.color.status_failed
        }
        row.stepStatus.text = glyph
        row.stepStatus.setTextColor(ContextCompat.getColor(this, color))
    }

    private fun showResult(result: ResetRunner.RunResult) {
        finished = true
        binding.resultText.text = result.message
        binding.resultText.setTextColor(
            ContextCompat.getColor(
                this,
                when (result.state) {
                    StepState.FAILED -> R.color.status_failed
                    StepState.WARNING -> R.color.status_warning
                    else -> R.color.status_done
                }
            )
        )
        binding.resultText.visibility = View.VISIBLE
        binding.actionButton.setText(R.string.action_ok)
        binding.actionButton.isEnabled = true
    }
}
