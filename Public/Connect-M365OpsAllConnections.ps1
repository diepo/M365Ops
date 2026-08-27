function Connect-M365OpsAllConnections {
    <#
    .SYNOPSIS
        Riconnette tutto cio' che PUO' essere riconnesso in silenzio per il TENANT ATTIVO, senza
        mai avviare un login interattivo bloccante da solo - pensato per il pulsante "Connetti
        tutto" (mostrato al posto di "Disconnetti tutto" quando nessuna connessione risulta
        attiva) e in particolare per rinforzare la connessione applicativa subito DOPO aver
        concesso un nuovo permesso Graph all'App Registration (Grant admin consent): un token o
        una sessione gia' ottenuti riflettono i permessi presenti AL MOMENTO in cui sono stati
        rilasciati, non quelli aggiunti dopo - vanno rifatti da zero per vederli, e questo e'
        richiesto esplicitamente dall'utente (27/08/2026).
    .NOTES
        SOLO su AppOnly fa un lavoro reale: ogni area (Exchange/Teams/SharePoint/Compliance/
        Intune, tutti i server MCP configurati, il token Graph diretto) e' certificato/client
        secret based, quindi non richiede mai interazione per definizione - stesso principio
        gia' verificato per ognuna di queste funzioni singolarmente. Su Delegated NON tenta
        nulla in silenzio: ogni area dipende dallo stesso token utente radice (device code),
        che dopo una disconnessione completa (token+refresh token scartati) richiede sempre un
        nuovo login interattivo - tentare comunque produrrebbe solo una raffica di errori
        identici e fuorvianti ("serve login interattivo") invece di un'indicazione chiara.

        Ogni passo AppOnly e' tentato indipendentemente (try/catch per passo, mai un
        fallimento che blocca i fratelli) - stesso principio gia' applicato sistematicamente
        altrove nel progetto contro la classe di bug "un passo fallito blocca i passi fratelli
        indipendenti" (v0.10.17).
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo." }
    $ctx = $script:M365OpsContext

    if ($ctx.AuthMode -eq 'Delegated') {
        return [pscustomobject]@{
            AuthMode = 'Delegated'
            Results  = @()
            Message  = "Tenant Delegato: dopo una disconnessione completa serve sempre un nuovo login interattivo (il token dell'utente e' la base di ogni altra connessione, incluso l'eventuale accesso a Lokka/Exchange/Teams/SharePoint/Purview/Intune) - usa 'Accedi con il mio utente' qui sotto. Una volta completato, le altre aree si riconnetteranno da sole riusando quella sessione quando servono, senza bisogno di ripetere questa azione."
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $steps = @(
        @{ Name = 'Token Microsoft Graph (app-only)'; Action = { Get-M365OpsToken | Out-Null } }
        @{ Name = 'Exchange Online';                  Action = { Connect-M365OpsExchange -Force } }
        @{ Name = 'Microsoft Teams';                  Action = { Connect-M365OpsTeams -Force } }
        @{ Name = 'SharePoint';                        Action = { Connect-M365OpsSharePoint -Force } }
        @{ Name = 'Security & Compliance (Purview)';  Action = { Connect-M365OpsCompliance -Force } }
        @{ Name = 'Intune';                            Action = { Connect-M365OpsIntune -Force } }
    )
    foreach ($step in $steps) {
        try {
            & $step.Action
            $results.Add([pscustomobject]@{ Name = $step.Name; Ok = $true; Message = $null })
        } catch {
            $results.Add([pscustomobject]@{ Name = $step.Name; Ok = $false; Message = $_.Exception.Message })
        }
    }

    foreach ($server in @(Get-M365OpsMcpServers)) {
        try {
            Connect-M365OpsMcpServer -Name $server.Name -Force | Out-Null
            $results.Add([pscustomobject]@{ Name = "MCP: $($server.Name)"; Ok = $true; Message = $null })
        } catch {
            $results.Add([pscustomobject]@{ Name = "MCP: $($server.Name)"; Ok = $false; Message = $_.Exception.Message })
        }
    }

    [pscustomobject]@{
        AuthMode = 'AppOnly'
        Results  = $results
        Message  = $null
    }
}
