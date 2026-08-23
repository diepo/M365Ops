function Format-M365OpsCommandLine {
    <#
    .SYNOPSIS
        Costruisce una riga di comando PowerShell LEGGIBILE (es. "Set-M365OpsTeam -GroupId
        '33b8...' -Description 'nuovo testo'") a partire da un nome cmdlet + hashtable di
        parametri - usata per mostrare all'utente ESATTAMENTE cosa e' stato eseguito, sia
        nella risposta post-esecuzione in chat sia nel log scritture separato (richiesto
        esplicitamente dall'utente il 27/08/2026: "scrivi anche il comando ps che sta per
        lanciare... l'importante che si sappia").

        Non e' pensata per essere ri-eseguibile alla lettera (i valori complessi - array,
        hashtable annidate - vengono resi leggibili, non necessariamente sintassi PowerShell
        valida al 100% se incollati altrove) - l'obiettivo e' la TRASPARENZA per un umano
        che legge, non un log rieseguibile a macchina.
    .PARAMETER Cmdlet
        Nome del cmdlet/funzione (es. "Set-M365OpsTeam").
    .PARAMETER Parameters
        Hashtable dei parametri passati.
    #>
    param(
        [Parameter(Mandatory)] [string]$Cmdlet,
        [hashtable]$Parameters = @{}
    )

    $parts = @($Cmdlet)
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        $formatted =
            if ($null -eq $value) { "`$null" }
            elseif ($value -is [bool]) { if ($value) { '$true' } else { '$false' } }
            elseif ($value -is [array] -or $value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                '@(' + (($value | ForEach-Object { "'$_'" }) -join ', ') + ')'
            }
            elseif ($value -is [hashtable] -or $value -is [System.Collections.Specialized.OrderedDictionary] -or $value -is [pscustomobject]) {
                ($value | ConvertTo-Json -Depth 6 -Compress)
            }
            elseif ($value -is [int] -or $value -is [double] -or $value -is [long]) { "$value" }
            else { "'$value'" }
        $parts += "-$key $formatted"
    }
    $parts -join ' '
}
