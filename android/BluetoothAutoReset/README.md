# Reset BT Auto

App Android minimale che esegue in sequenza, con un solo tocco:

1. **Disattiva il Bluetooth** e attende la conferma dello stato OFF.
2. **Termina Android Auto** (`com.google.android.projection.gearhead` e le altre varianti note del pacchetto).
3. **Riattiva il Bluetooth** e attende la conferma dello stato ON.

La GUI e' una sola schermata: descrive i tre passi *prima* di eseguirli, mostra l'esito di ognuno
mentre la sequenza avanza e al termine il pulsante diventa **OK**, che chiude l'app.

## Requisiti reali di Android

Questi limiti sono del sistema operativo, non dell'app:

| Operazione | Android <= 12 (API 32) | Android >= 13 (API 33) |
|---|---|---|
| Accendere/spegnere il Bluetooth da app | possibile con le API legacy `BluetoothAdapter.enable()/disable()` | **non possibile**: le API sono state disattivate per le app di terze parti |
| Chiudere forzatamente un'altra app | non possibile (`FORCE_STOP_PACKAGES` e' un permesso di sistema) | non possibile |

Di conseguenza l'app lavora in due modalita', rilevate automaticamente all'avvio e indicate
nella schermata:

- **Root disponibile** — la sequenza e' completamente automatica. Vengono usati
  `svc bluetooth disable` / `enable` e `am force-stop <pacchetto>` tramite shell `su`.
  Alla prima esecuzione il gestore dei permessi di root (Magisk o equivalente) chiede
  l'autorizzazione: concedila in modo permanente.
- **Senza root** — l'app fa il massimo consentito dalle API pubbliche: commuta il Bluetooth con le
  API legacy (solo fino ad Android 12) e chiama `killBackgroundProcesses()` su Android Auto, che
  chiude i soli processi in background. Ogni passo che non puo' essere completato viene segnalato
  con il motivo, senza fallire in silenzio.

Su un dispositivo non rootato con Android 13 o superiore la sequenza non puo' essere automatizzata
da nessuna app: gli stessi comandi restano eseguibili da PC collegato via ADB.

```
adb shell svc bluetooth disable
adb shell am force-stop com.google.android.projection.gearhead
adb shell svc bluetooth enable
```

## Compilazione

Il progetto e' un progetto Gradle/Android standard (Kotlin, view binding, nessuna dipendenza
esterna oltre ad AndroidX e Material).

- `compileSdk` / `targetSdk` 35, `minSdk` 24
- JDK 17, Android Gradle Plugin 8.7.3, Kotlin 2.0.21

Da Android Studio: *File > Open* su questa cartella, poi *Run*.

Da riga di comando (richiede l'Android SDK e `ANDROID_HOME` impostata):

```bash
cd android/BluetoothAutoReset
./gradlew assembleDebug
# APK in app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Permessi dichiarati

| Permesso | Uso |
|---|---|
| `BLUETOOTH`, `BLUETOOTH_ADMIN` (max API 30) | commutazione con le API legacy |
| `BLUETOOTH_CONNECT` | lettura dello stato dell'adattatore su API >= 31 |
| `KILL_BACKGROUND_PROCESSES` | fallback senza root su Android Auto |

Il blocco `<queries>` del manifest serve solo a verificare se Android Auto e' installato
(package visibility, obbligatoria da API 30).

## Struttura

```
app/src/main/java/it/m365ops/btautoreset/
  MainActivity.kt   GUI: descrizione, avanzamento, pulsante OK
  ResetRunner.kt    logica dei tre passi, root e fallback
  ResetSteps.kt     definizione dei passi e degli stati
  Shell.kt          esecuzione dei comandi tramite shell di root
```
