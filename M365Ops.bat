@echo off
setlocal

rem Cerca pwsh.exe (PowerShell 7): prima nel PATH, poi nel percorso di installazione standard.
rem Deve stare qui in .bat (cmd.exe, sempre presente) e non in Launch-M365Ops.ps1: se manca
rem proprio PowerShell 7, non c'e' nessun modo di eseguire codice PowerShell per sistemarlo da
rem solo - questo e' l'unico punto dove il controllo/installazione ha senso.
set "PWSH="
where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
    set "PWSH=pwsh.exe"
) else if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
)

rem Percorso comune (tutto gia' presente): nessuna finestra, avvio diretto e silenzioso,
rem esattamente come prima. La GUI di installazione (22/08/2026, richiesta esplicitamente
rem dall'utente: "una gui che segua l'installazione dei moduli. aggrega dentro
rem l'installazione dei prereq anche nodejs") scatta SOLO se manca almeno uno tra
rem PowerShell 7, winget o Node.js - vedi Show-M365OpsPrereqInstaller.ps1, che gestisce da
rem sola l'intero flusso (incluso il bootstrap di winget stesso se assente, riusando
rem Bootstrap-Winget.ps1) invece delle sottoroutine di solo testo usate prima qui.
set "NEEDS_PREREQ_GUI=0"
if "%PWSH%"=="" set "NEEDS_PREREQ_GUI=1"
where winget.exe >nul 2>nul
if %errorlevel% neq 0 set "NEEDS_PREREQ_GUI=1"
where npx.cmd >nul 2>nul
if %errorlevel% neq 0 set "NEEDS_PREREQ_GUI=1"

if "%NEEDS_PREREQ_GUI%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Show-M365OpsPrereqInstaller.ps1"

    rem Bug reale segnalato dal vivo il 22/08/2026 su Windows Sandbox: dopo che la GUI
    rem installava tutto con successo (lentamente), M365Ops.bat proseguiva usando il
    rem %PATH% di QUESTO processo cmd.exe, mai aggiornato dopo il bootstrap - un processo
    rem figlio (pwsh.exe per Launch-M365Ops.ps1) eredita il PATH del genitore AL MOMENTO
    rem in cui viene creato, non quello vero e attuale del registro. Risultato: winget
    rem risultava di nuovo "non trovato" dentro quel processo, facendo scattare un secondo
    rem bootstrap ridondante (Install-Module Microsoft.WinGet.Client, stavolta sotto
    rem PowerShell 7 invece di Windows PowerShell 5.1 - percorso moduli diverso, quindi
    rem nessuna cache riusata dal primo tentativo) - probabile causa reale del timeout di
    rem avvio del server visto dall'utente. Corretto rileggendo qui il PATH vero dal
    rem registro (Machine+User) PRIMA di procedere, cosi' il processo che sta per essere
    rem avviato eredita gia' tutto cio' che la GUI ha appena installato.
    for /f "usebackq delims=" %%P in (`powershell.exe -NoProfile -Command "[System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')"`) do set "PATH=%%P"

    set "PWSH="
    where pwsh.exe >nul 2>nul
    if %errorlevel% equ 0 (
        set "PWSH=pwsh.exe"
    ) else if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
    )
)

if "%PWSH%"=="" exit /b 1

start "" "%PWSH%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-M365Ops.ps1"
exit /b 0
