function Get-M365OpsDelegatedPermissionsCheck {
    <#
    .SYNOPSIS
        Equivalente di Get-M365OpsAppPermissionsCheck per un tenant Delegato: su un tenant
        Delegato non esiste un'App Registration da verificare (l'accesso dipende dal ruolo
        Entra ID/Exchange dell'utente reale con cui si e' fatto login), quindi non ha senso
        controllare permessi Graph - si controllano invece i RUOLI RBAC EXCHANGE REALI
        dell'utente (21/08/2026, richiesto esplicitamente dall'utente dopo aver notato che
        il pulsante "Stato permessi" su un tenant Delegato si limitava a un errore: "non
        sarebbe meglio listare i ruoli attivi dell'utente e dirgli cosa puo'/non puo' fare
        con quei ruoli?").
    .NOTES
        Copre SOLO Exchange Online RBAC per ora, deliberatamente - e' l'area dove questo
        progetto ha gia' verificato dal vivo quali ruoli servono per cosa (sezione 6.4/6.5
        della guida). L'accesso Graph (Intune/Entra ID/Teams/SharePoint) in modalita'
        Delegated dipende dal ruolo DIRECTORY Entra ID dell'utente, un controllo diverso non
        ancora implementato qui - segnalato esplicitamente come nota nel risultato invece di
        ometterlo in silenzio o fingere di saperlo.
        Mappatura area->ruolo RBAC radicata SOLO in cio' che e' stato verificato dal vivo in
        questo progetto (non un catalogo esaustivo di tutti i ruoli Exchange): "Remote and
        Accepted Domains" per Accepted/Remote Domain (verificato 21/08/2026, login reale con
        diego@vnsys.it), "Transport Hygiene" per anti-spam/anti-phishing/malware (verificato
        21/08/2026 in App-only, stesso ruolo gia' presente anche lato Delegated). Le altre
        righe sono dedotte dal NOME del ruolo (marcate esplicitamente come tali nella nota) -
        non ancora confermate con una scrittura reale in modalita' Delegated.
    #>
    param([Parameter(Mandatory)] $Context)

    if (-not $Context.DelegatedUpn) {
        throw "Il profilo '$($Context.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato."
    }

    Connect-M365OpsExchange
    $assignments = Get-ManagementRoleAssignment -RoleAssignee $Context.DelegatedUpn -ErrorAction Stop
    $heldRoles = @($assignments | Select-Object -ExpandProperty Role -Unique)

    $areaDefs = @(
        @{ Area = 'Domini accettati e domini remoti'; WriteRoles = @('Remote and Accepted Domains')
           Note = "Verificato dal vivo il 21/08/2026: con questo ruolo Get-AcceptedDomain funziona subito in Delegated." }
        @{ Area = 'Anti-spam / anti-phishing / filtro malware'; WriteRoles = @('Transport Hygiene')
           Note = "Verificato dal vivo il 21/08/2026 (in App-only, stesso ruolo): copre criteri e regole per tutte e tre le aree." }
        @{ Area = 'Connettori Inbound/Outbound, impostazioni trasporto globali'; WriteRoles = @('Organization Transport Settings')
           Note = "Mappatura dedotta dal nome del ruolo - NON ancora verificata dal vivo con una scrittura reale in modalita' Delegated, a differenza delle righe sopra." }
        @{ Area = 'Mailbox, gruppi di distribuzione, destinatari'; WriteRoles = @('Mail Recipients'); ReadRoles = @('View-Only Recipients')
           Note = "Mappatura dedotta dal nome del ruolo - non ancora verificata dal vivo in Delegated." }
        @{ Area = 'Regole di trasporto (mail flow rules)'; WriteRoles = @('Transport Rules')
           Note = "Mappatura dedotta dal nome del ruolo - non ancora verificata dal vivo in Delegated." }
        @{ Area = 'Ruoli RBAC Exchange (Role Management)'; WriteRoles = @('Role Management')
           Note = "Mappatura dedotta dal nome del ruolo - non ancora verificata dal vivo in Delegated." }
    )

    $results = foreach ($def in $areaDefs) {
        $hasWrite = @($def.WriteRoles | Where-Object { $heldRoles -contains $_ }).Count -gt 0
        $hasRead = $hasWrite -or (@($def.ReadRoles) | Where-Object { $heldRoles -contains $_ }).Count -gt 0
        $status = if ($hasWrite) { 'lettura+scrittura' } elseif ($hasRead) { 'lettura' } else { 'nessun accesso' }
        [pscustomobject]@{
            Area            = $def.Area
            Resource        = "Ruolo RBAC Exchange di $($Context.DelegatedUpn)"
            Status          = $status
            MissingForRead  = if (-not $hasRead) { @($def.ReadRoles) } else { @() }
            MissingForWrite = if (-not $hasWrite) { @($def.WriteRoles) } else { @() }
            Note            = $def.Note
        }
    }

    $results += [pscustomobject]@{
        Area            = "Elenco completo ruoli RBAC EXCHANGE posseduti da $($Context.DelegatedUpn)"
        Resource        = 'Exchange Online RBAC (Get-ManagementRoleAssignment)'
        Status          = 'informativo'
        MissingForRead  = @()
        MissingForWrite = @()
        Note            = if ($heldRoles.Count -gt 0) { ($heldRoles | Sort-Object) -join ', ' } else { '(nessun ruolo Exchange assegnato a questo utente)' }
    }

    # Ruoli DIRECTORY Entra ID (21/08/2026, aggiunto dopo che l'utente ha segnalato dal vivo:
    # "mi aspettavo di vedere i miei ruoli, tipo Global Admin nel mio caso" - i ruoli RBAC
    # Exchange sopra sono un sistema COMPLETAMENTE SEPARATO dai ruoli directory Entra ID che
    # governano Intune/Entra ID/Teams/SharePoint via Graph. Usa lo stesso token Graph delegato
    # gia' ottenuto con "Accedi a Microsoft Graph col mio utente" (Invoke-M365OpsGraphRequest
    # sceglie gia' da solo il token giusto in base all'AuthMode, nessun codice nuovo per quello) -
    # se quel login non e' mai stato fatto, questa chiamata fallisce e viene segnalato onestamente
    # invece di far fallire l'intera funzione.
    $directoryRoles = @()
    $graphError = $null
    try {
        $roleResp = Invoke-M365OpsGraphRequest -Method GET -Path '/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=displayName'
        $directoryRoles = @($roleResp.value | Select-Object -ExpandProperty displayName)
    } catch {
        $graphError = $_.Exception.Message
    }

    $results += [pscustomobject]@{
        Area            = "Elenco completo ruoli DIRECTORY Entra ID di $($Context.DelegatedUpn)"
        Resource        = 'Microsoft Entra ID (GET /me/transitiveMemberOf/directoryRole)'
        Status          = 'informativo'
        MissingForRead  = @()
        MissingForWrite = @()
        Note            = if ($graphError) { "Lettura fallita (serve prima un login Graph delegato attivo - vedi tab Tenant, 'Accedi a Microsoft Graph con il mio utente'): $graphError" }
                           elseif ($directoryRoles.Count -gt 0) { ($directoryRoles | Sort-Object) -join ', ' }
                           else { '(nessun ruolo directory Entra ID assegnato a questo utente)' }
    }

    # Mappatura area->ruolo directory per Intune/Entra ID/Teams/SharePoint via Graph - nomi di
    # ruolo standard Microsoft (documentati), non dedotti. "Global Administrator" copre tutto.
    if (-not $graphError) {
        $graphAreaDefs = @(
            @{ Area = 'Intune (dispositivi, app, configurazioni) - via Graph'; WriteRoles = @('Global Administrator', 'Intune Administrator') }
            @{ Area = 'Entra ID (utenti, gruppi) - via Graph'; WriteRoles = @('Global Administrator', 'User Administrator', 'Groups Administrator') }
            @{ Area = 'Teams (admin center/Graph)'; WriteRoles = @('Global Administrator', 'Teams Administrator') }
            @{ Area = 'SharePoint (admin center/Graph)'; WriteRoles = @('Global Administrator', 'SharePoint Administrator') }
        )
        foreach ($def in $graphAreaDefs) {
            $hasWrite = @($def.WriteRoles | Where-Object { $directoryRoles -contains $_ }).Count -gt 0
            $results += [pscustomobject]@{
                Area            = $def.Area
                Resource        = "Ruolo directory Entra ID di $($Context.DelegatedUpn)"
                Status          = if ($hasWrite) { 'lettura+scrittura' } else { 'nessun accesso' }
                MissingForRead  = if (-not $hasWrite) { $def.WriteRoles } else { @() }
                MissingForWrite = if (-not $hasWrite) { $def.WriteRoles } else { @() }
                Note            = "Verifica per nome di ruolo directory standard Microsoft - non ancora confermato con una scrittura reale in Delegated per quest'area specifica."
            }
        }
    }

    return $results
}
