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

if "%PWSH%"=="" (
    echo PowerShell 7 non trovato su questo PC - installazione automatica in corso tramite winget...
    where winget.exe >nul 2>nul
    if %errorlevel% neq 0 (
        echo winget non disponibile su questo PC: installa PowerShell 7 manualmente da https://aka.ms/powershell-release
        echo poi rilancia M365Ops.bat.
        pause
        exit /b 1
    )
    winget install --id Microsoft.PowerShell -e --silent --accept-package-agreements --accept-source-agreements
    if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
        echo PowerShell 7 installato correttamente.
    ) else (
        echo Installazione completata ma pwsh.exe non risulta nel percorso atteso.
        echo Chiudi questa finestra e rilancia M365Ops.bat - se il problema persiste, installa manualmente da https://aka.ms/powershell-release
        pause
        exit /b 1
    )
)

start "" "%PWSH%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-M365Ops.ps1"
