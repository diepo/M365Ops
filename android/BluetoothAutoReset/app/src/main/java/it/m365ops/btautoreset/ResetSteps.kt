package it.m365ops.btautoreset

import androidx.annotation.StringRes

/** Stato di avanzamento di un singolo passo della sequenza. */
enum class StepState { PENDING, RUNNING, DONE, WARNING, FAILED }

/** Descrizione statica di un passo, mostrata nella GUI prima ancora di avviare la sequenza. */
data class ResetStep(
    val id: Int,
    @StringRes val title: Int,
    @StringRes val description: Int
)

/** Esito di un passo: stato finale piu' un dettaglio leggibile da mostrare sotto il titolo. */
data class StepOutcome(val state: StepState, val detail: String)

object ResetSteps {

    const val ID_DISABLE_BLUETOOTH = 0
    const val ID_KILL_ANDROID_AUTO = 1
    const val ID_ENABLE_BLUETOOTH = 2

    val ALL: List<ResetStep> = listOf(
        ResetStep(ID_DISABLE_BLUETOOTH, R.string.step_disable_title, R.string.step_disable_desc),
        ResetStep(ID_KILL_ANDROID_AUTO, R.string.step_kill_title, R.string.step_kill_desc),
        ResetStep(ID_ENABLE_BLUETOOTH, R.string.step_enable_title, R.string.step_enable_desc)
    )
}
