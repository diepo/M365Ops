function Install-M365OpsPrerequisites {
    <#
    .SYNOPSIS
        Controlla i prerequisiti di sistema (Node.js, Microsoft Edge) e installa
        automaticamente quelli mancanti tramite winget - non si limita a segnalarli come fa
        Get-M365OpsSetupStatus (che da' solo istruzioni manuali). Richiesto esplicitamente
        dall'utente il 17/08/2026: "se non ci sono direttamente procede alla installazione".

        I moduli PowerShell (ImportExcel, ExchangeOnlineManagement, IntuneWin32App) NON sono
        gestiti qui: si auto-installano gia' da soli al primo uso con Install-Module
        -Scope CurrentUser dentro le rispettive cmdlet - non serve ripetere quella logica qui.

        PowerShell 7 stesso NON e' gestito qui: se manca, questa funzione non puo' nemmeno
        girare (serve pwsh per eseguirla). Il controllo/installazione di PowerShell 7 vive in
        M365Ops.bat, PRIMA di invocare pwsh.exe - l'unico punto dove ha senso, essendo un file
        .bat eseguito da cmd.exe (sempre presente) invece che da PowerShell stesso.
    .NOTES
        Installazione via winget, in modo silenzioso (nessun prompt) - coerente con la
        richiesta esplicita di procedere direttamente. Se winget non e' disponibile sul PC
        (raro su Windows 10/11 aggiornati, ma possibile su installazioni molto datate o
        Windows Server), la funzione lo segnala chiaramente invece di fallire in modo oscuro.

        Dopo un'installazione riuscita, il PATH di sistema viene ricaricato dal registro nel
        processo CORRENTE (non solo nei nuovi processi, comportamento di default di Windows) -
        altrimenti Get-Command continuerebbe a non trovare il programma appena installato
        finche' l'intero server non viene riavviato manualmente, un passaggio in piu' evitabile.
    #>
    $results = @()

    $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
    if (-not $winget) {
        return @([pscustomobject]@{
            Name   = 'winget'
            Status = 'Missing'
            Action = 'Nessuna - winget non e'' disponibile su questo PC, impossibile installare automaticamente.'
            Detail = 'Installa i pacchetti "App Installer" dal Microsoft Store, oppure installa i prerequisiti manualmente (vedi sezione 3 della guida).'
        })
    }

    $checks = @(
        @{
            Name       = 'Node.js (npx, richiesto da Lokka)'
            IsPresent  = { (Get-Command 'npx.cmd' -ErrorAction SilentlyContinue) -or (Get-Command 'npx' -ErrorAction SilentlyContinue) }
            WingetId   = 'OpenJS.NodeJS.LTS'
        },
        @{
            Name       = 'Microsoft Edge (per export PDF)'
            IsPresent  = { (Get-Command 'msedge.exe' -ErrorAction SilentlyContinue) -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") }
            WingetId   = 'Microsoft.Edge'
        }
    )

    $installedSomething = $false
    foreach ($c in $checks) {
        if (& $c.IsPresent) {
            $results += [pscustomobject]@{ Name = $c.Name; Status = 'OK'; Action = 'Gia'' presente, nessuna installazione necessaria.'; Detail = $null }
            continue
        }

        $output = & winget install --id $c.WingetId -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $installedSomething = $true

        # Aggiorna il PATH del processo corrente dal registro (Machine + User) - winget
        # scrive il nuovo percorso nel registro di sistema, ma un processo gia' avviato (questo
        # server) non lo rilegge mai da solo finche' non viene riavviato: senza questo, la
        # ri-verifica subito sotto fallirebbe sempre anche a installazione riuscita.
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

        $nowPresent = & $c.IsPresent
        $results += [pscustomobject]@{
            Name   = $c.Name
            Status = if ($nowPresent) { 'OK' } else { 'Failed' }
            Action = "Installazione tentata (winget install $($c.WingetId), exit code $exitCode)."
            Detail = if ($nowPresent) { 'Installato e rilevato correttamente.' } else { "Non rilevato dopo il tentativo di installazione - output winget: $($output.Trim())" }
        }
    }

    if ($installedSomething) {
        Write-M365OpsLog "Install-M365OpsPrerequisites: $(($results | Where-Object { $_.Status -ne 'OK' -or $_.Action -like 'Installazione*' } | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ', ')"
    }

    $results
}
