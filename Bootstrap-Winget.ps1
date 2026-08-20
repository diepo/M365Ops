<#
    Installa winget da zero quando manca del tutto, usando SOLO Windows PowerShell 5.1
    (sempre presente su Windows 10/11, a differenza di PowerShell 7) - pensato per essere
    chiamato da M365Ops.bat con "powershell.exe -File" PRIMA che PowerShell 7 esista, nel
    caso piu' minimale possibile: PC pulito senza ne' pwsh ne' winget.

    Bug reale segnalato dal vivo il 22/08/2026 (v0.9.26 gia' installata): l'utente ha
    ritrovato ESATTAMENTE lo stesso blocco "ps7 assente e winget non disponibile" gia'
    segnalato prima della v0.9.25. Causa: il bootstrap winget aggiunto in v0.9.25
    (Install-M365OpsPrerequisites.ps1) vive nel MODULO PowerShell, che richiede un
    ambiente PowerShell gia' funzionante per essere importato - inutile per il caso reale,
    che scatta in M365Ops.bat, dentro cmd.exe, PRIMA che esista anche solo PowerShell 7.
    Questo script e' la correzione vera: stesso bootstrap ufficiale Microsoft
    (Microsoft.WinGet.Client / Repair-WinGetPackageManager) ma eseguito dal punto giusto
    della catena, in un file .ps1 separato invece che inline nel .bat (i molti parentesi
    del codice PowerShell romperebbero il parsing degli if annidati di cmd.exe).

    Uscita: exit code 0 se winget e' disponibile alla fine (gia' presente o installato
    ora), 1 se il tentativo fallisce - M365Ops.bat legge %errorlevel% per decidere se
    proseguire o mostrare le istruzioni di installazione manuale.
#>

if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    Write-Host "winget gia' disponibile."
    exit 0
}

try {
    # TLS 1.2 esplicito: la causa piu' comune di "Install-Module" che fallisce silenziosamente
    # (o con un errore di connessione poco chiaro) su un Windows datato/appena installato e'
    # che .NET/Windows PowerShell 5.1 negozia di default un protocollo piu' vecchio non
    # accettato piu' da PowerShell Gallery - non un'ipotesi, e' il problema numero uno
    # documentato da Microsoft per questo identico scenario (PC pulito, Install-Module).
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    # Il provider NuGet e' un prerequisito SEPARATO di Install-Module, non incluso da
    # -Force su Install-Module stesso - su un PC dove non e' mai stato installato,
    # Install-Module lo richiederebbe interattivamente (prompt "install now?"), che in
    # questo contesto (finestra .bat visibile ma non presidiata) rischierebbe di restare
    # bloccato in attesa di una risposta mai data. Preinstallato qui esplicitamente con
    # -Force per evitare del tutto il prompt.
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Host "Provider NuGet non trovato, lo installo..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
    }

    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
        Write-Host "Modulo Microsoft.WinGet.Client non trovato, lo installo..."
        Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
    }
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    Repair-WinGetPackageManager -ErrorAction Stop
}
catch {
    Write-Host "Bootstrap di winget fallito: $($_.Exception.Message)"
    exit 1
}

# Stesso identico problema di PATH gia' documentato altrove nel progetto
# (Install-M365OpsPrerequisites.ps1): l'installazione scrive il nuovo percorso nel
# registro, ma QUESTO processo powershell.exe non lo rilegge da solo. Qui pero' conta
# anche il processo cmd.exe CHIAMANTE (M365Ops.bat), che ha il proprio PATH ereditato
# all'avvio e non lo rilegge mai in automatico neanche dopo che questo script finisce -
# per questo M365Ops.bat, dopo aver richiamato questo script, non si affida al solo
# "where winget.exe" ma controlla anche il percorso noto diretto come fallback.
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    Write-Host "winget installato correttamente."
    exit 0
}
if (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe") {
    Write-Host "winget installato correttamente (rilevato in WindowsApps)."
    exit 0
}

Write-Host "Bootstrap completato ma winget non risulta ancora rilevabile in questa sessione."
exit 1
