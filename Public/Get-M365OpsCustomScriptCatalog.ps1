function Get-M365OpsCustomScriptCatalog {
    <#
    .SYNOPSIS
        Elenca gli script personalizzati in Scripts\Custom, con validazione della
        convenzione richiesta (vedi Scripts\Custom\README.md) e i metadati che
        Invoke-M365OpsAgentTools usa per esporli all'AI: Synopsis, parametri, Mode
        (ReadOnly = eseguibile subito, Write = solo proponibile, mai eseguita senza
        conferma umana - stesso principio di ogni altra scrittura in questo modulo).
        Uno script senza tag Mode valido viene segnalato Valid=$false e MAI esposto
        all'AI, ne' in lettura ne' in scrittura - per sicurezza, meglio ignorarlo che
        indovinarne la natura.

        CatalogTrigger/CatalogDefer (10/09/2026, richiesto esplicitamente dall'utente:
        "ho bisogno di un modo comodo per far crescere il catalogo locale che non
        richieda il fatto di interpellare te ogni volta... questa cosa deve essere
        scalabile") - tag OPZIONALI in .NOTES che permettono a uno script Mode:ReadOnly
        SENZA PARAMETRI di diventare anche una voce del catalogo comandi locale a costo
        zero (Gui\CommandCatalog.ps1, Get-M365OpsCustomCommandCatalogEntries) invece di
        restare disponibile solo come strumento richiamabile dall'IA - una domanda che
        ci passa sopra risponde SENZA alcun round IA, esattamente come le voci native
        del catalogo (TenantUserCount ecc.). Volutamente ristretto a ReadOnly+zero
        parametri: un trigger su una SCRITTURA bypasserebbe la conferma umana (mai
        accettabile), e senza IA non c'e' modo di estrarre un parametro dal testo
        libero del messaggio.
    #>
    $scripts = @()
    $files = Get-ChildItem -Path $script:M365OpsCustomScriptsPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '_*' }

    foreach ($file in $files) {
        $functionName = $file.BaseName
        $command = Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue

        if (-not $command) {
            $scripts += [pscustomobject]@{
                Name = $functionName; File = $file.Name; Valid = $false
                Reason = "Il file non definisce una funzione chiamata '$functionName' (deve corrispondere esattamente al nome del file), oppure ha un errore di sintassi non caricato all'avvio."
                Mode = $null; Synopsis = $null; Parameters = @(); CatalogTrigger = $null; CatalogDefer = $null
            }
            continue
        }

        $help = Get-Help -Name $functionName -ErrorAction SilentlyContinue
        $synopsis = if ($help -and $help.Synopsis -notmatch '^\s*$' -and $help.Synopsis -ne $functionName) { $help.Synopsis.Trim() } else { $null }
        $notesText = if ($help.alertSet.alert.Text) { ($help.alertSet.alert.Text -join "`n") } else { "" }
        $mode = if ($notesText -match '(?im)^\s*Mode:\s*(ReadOnly|Write)\s*$') { $Matches[1] } else { $null }
        # ProgressAction e' un parametro comune aggiunto da PowerShell 7.4 in poi (non esisteva
        # prima) - senza escluderlo qui trapela come falso parametro dello script nel catalogo
        # esposto all'AI (verificato dal vivo il 23/08/2026: PS 7.6.5 di questo ambiente lo
        # include gia' su qualunque funzione avanzata, es. Get-M365OpsOneDriveSharingReport
        # mostrava 'Upn, ProgressAction' invece del solo 'Upn' reale dello script).
        $parameters = @($command.Parameters.Keys | Where-Object { $_ -notin @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','Confirm','WhatIf') })
        # CatalogTrigger/CatalogDefer: vedi .SYNOPSIS sopra. Letti qui a prescindere da Mode/
        # parametri (la validazione "e' davvero utilizzabile come voce di catalogo" spetta al
        # chiamante, Get-M365OpsCustomCommandCatalogEntries in Gui\CommandCatalog.ps1 - qui solo
        # estrazione del testo grezzo, stesso principio di $mode sopra).
        $catalogTrigger = if ($notesText -match '(?im)^\s*CatalogTrigger:\s*(.+)$') { $Matches[1].Trim() } else { $null }
        $catalogDefer = if ($notesText -match '(?im)^\s*CatalogDefer:\s*(.+)$') { $Matches[1].Trim() } else { $null }

        if (-not $synopsis -or -not $mode) {
            $missing = @(); if (-not $synopsis) { $missing += '.SYNOPSIS' }; if (-not $mode) { $missing += '.NOTES con Mode: ReadOnly|Write' }
            $scripts += [pscustomobject]@{
                Name = $functionName; File = $file.Name; Valid = $false
                Reason = "Manca $($missing -join ' e ') nel blocco di help - vedi Scripts\Custom\_TEMPLATE.ps1."
                Mode = $mode; Synopsis = $synopsis; Parameters = $parameters; CatalogTrigger = $catalogTrigger; CatalogDefer = $catalogDefer
            }
            continue
        }

        $scripts += [pscustomobject]@{
            Name = $functionName; File = $file.Name; Valid = $true; Reason = $null
            Mode = $mode; Synopsis = $synopsis; Parameters = $parameters; CatalogTrigger = $catalogTrigger; CatalogDefer = $catalogDefer
        }
    }

    $scripts
}
