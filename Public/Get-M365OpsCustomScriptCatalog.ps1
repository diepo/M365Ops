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
                Mode = $null; Synopsis = $null; Parameters = @()
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

        if (-not $synopsis -or -not $mode) {
            $missing = @(); if (-not $synopsis) { $missing += '.SYNOPSIS' }; if (-not $mode) { $missing += '.NOTES con Mode: ReadOnly|Write' }
            $scripts += [pscustomobject]@{
                Name = $functionName; File = $file.Name; Valid = $false
                Reason = "Manca $($missing -join ' e ') nel blocco di help - vedi Scripts\Custom\_TEMPLATE.ps1."
                Mode = $mode; Synopsis = $synopsis; Parameters = $parameters
            }
            continue
        }

        $scripts += [pscustomobject]@{
            Name = $functionName; File = $file.Name; Valid = $true; Reason = $null
            Mode = $mode; Synopsis = $synopsis; Parameters = $parameters
        }
    }

    $scripts
}
