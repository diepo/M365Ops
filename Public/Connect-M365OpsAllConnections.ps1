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
        SOLO su AppOnly le aree Exchange/Teams/SharePoint/Compliance/Intune e il token Graph
        diretto fanno un lavoro reale: sono tutte certificato/client-secret based, quindi non
        richiedono mai interazione per definizione - stesso principio gia' verificato per
        ognuna di queste funzioni singolarmente. Su Delegated queste NON vengono tentate:
        dipendono tutte dallo stesso token utente radice (device code), che dopo una
        disconnessione completa (token+refresh token scartati) richiede sempre un nuovo login
        interattivo - tentarle comunque produrrebbe solo una raffica di errori identici e
        fuorvianti ("serve login interattivo") invece di un'indicazione chiara.

        I SERVER MCP invece vengono tentati SEMPRE, anche su Delegato (corretto il 31/08/2026,
        bug reale trovato dalla maratona di stress-test: prima venivano saltati del tutto su
        Delegato) - CLI Microsoft 365 in particolare si autentica con uno stato SEPARATO su
        disco (`m365 login`/`connection use`, vedi Connect-M365OpsCliMicrosoft365.ps1),
        INDIPENDENTE dal token utente root di questo modulo: se una connessione CLI365 per
        questo profilo esiste gia' (es. il suo sottoprocesso MCP e' stato ucciso da
        "Disconnetti tutto" ma il login CLI resta valido su disco, quella funzione NON lo
        revoca mai), la riconnessione riesce in silenzio SENZA bisogno di alcun login
        interattivo - saltarla incondizionatamente su Delegato negava questo caso reale. Se
        invece nessuna connessione CLI365 salvata esiste, il tentativo fallisce con un
        messaggio chiaro (gestito dallo stesso try/catch per passo di sotto), mai un blocco.

        Ogni passo e' tentato indipendentemente (try/catch per passo, mai un fallimento che
        blocca i fratelli) - stesso principio gia' applicato sistematicamente altrove nel
        progetto contro la classe di bug "un passo fallito blocca i passi fratelli
        indipendenti" (v0.10.17).
    #>
    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo." }
    $ctx = $script:M365OpsContext
    $isDelegated = $ctx.AuthMode -eq 'Delegated'

    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $isDelegated) {
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
        AuthMode = $ctx.AuthMode
        Results  = $results
        Message  = if ($isDelegated) { "Tenant Delegato: le aree che dipendono dal token utente root (Exchange/Teams/SharePoint/Purview/Intune/Graph diretto) richiedono sempre un nuovo login interattivo dopo una disconnessione completa - usa 'Accedi con il mio utente' qui sotto. I server MCP configurati (es. CLI Microsoft 365) sono stati comunque tentati sopra, dato che possono avere una propria connessione salvata indipendente dal login Graph generico." } else { $null }
    }
}
