package it.m365ops.btautoreset

import java.util.concurrent.TimeUnit

/**
 * Esecuzione di comandi tramite shell di root (`su`).
 *
 * Su Android 13+ le API pubbliche non permettono piu' a un'app di terze parti di accendere o
 * spegnere il Bluetooth, ne' di terminare un'altra applicazione: la shell di root e' l'unico modo
 * per completare la sequenza senza interazione dell'utente.
 */
object Shell {

    private const val TIMEOUT_SECONDS = 20L

    data class Result(val exitCode: Int, val output: String) {
        val isSuccess: Boolean get() = exitCode == 0
    }

    /** true se sul dispositivo e' disponibile una shell di root utilizzabile. */
    fun hasRoot(): Boolean {
        val result = exec("id")
        return result.isSuccess && result.output.contains("uid=0")
    }

    /** Esegue i comandi indicati in un'unica sessione `su`, restituendo output ed exit code. */
    fun exec(vararg commands: String): Result {
        var process: Process? = null
        return try {
            process = ProcessBuilder("su").redirectErrorStream(true).start()
            process.outputStream.bufferedWriter().use { writer ->
                commands.forEach { command ->
                    writer.write(command)
                    writer.newLine()
                }
                writer.write("exit")
                writer.newLine()
            }
            val output = process.inputStream.bufferedReader().use { it.readText() }.trim()
            if (!process.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                process.destroy()
                Result(-1, "timeout dopo $TIMEOUT_SECONDS s")
            } else {
                Result(process.exitValue(), output)
            }
        } catch (error: Exception) {
            process?.destroy()
            Result(-1, error.message ?: error.javaClass.simpleName)
        }
    }
}
