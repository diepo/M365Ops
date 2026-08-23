function Set-M365OpsRoleAssignment {
    <#
    .SYNOPSIS
        Crea un'assegnazione per un ruolo RBAC Intune: collega gruppi di amministratori
        (-AdminGroupIds, chi puo' usare il ruolo) a uno scope di gestione (-ScopeType e/o
        -ScopeGroupIds, su cosa puo' agire).
    .NOTES
        BUG REALE trovato e corretto il 23/08/2026 durante la maratona di debug (test dal vivo
        su vnsys-test): il codice precedente faceva POST su
        "/deviceManagement/roleDefinitions/{id}/roleAssignments", che sembra corretto leggendo la
        pagina "Create roleAssignment" di Microsoft Learn - ma quella pagina documenta il tipo
        BASE astratto (roleAssignment), che il backend reale (servizio
        "StatelessRoleAdministrationFEService") rifiuta con 400 "No OData route exists that match
        template" per QUALSIASI POST, verificato dal vivo. Il tipo concreto usato da Intune e'
        deviceAndAppManagementRoleAssignment, la cui rotta di creazione documentata (pagina
        separata "Create deviceAndAppManagementRoleAssignment") e' invece POST sulla collezione di
        primo livello "/deviceManagement/roleAssignments", con "@odata.type" esplicito e il ruolo
        collegato via "roleDefinition@odata.bind" (relazione, non piu' parte del path) - schema
        confermato dal vivo su questo tenant dopo la correzione (assegnazione creata con successo).
        Corretto anche il campo per gli admin: "scopeMembers" (nome fuorviante, in realta' i
        gruppi di SCOPE ulteriori) non e' il campo giusto per "chi puo' usare il ruolo" - quello e'
        "members" (proprieta' propria di deviceAndAppManagementRoleAssignment, non ereditata).
        Mantenuto anche "scopeMembers" popolato con gli stessi AdminGroupIds per compatibilita',
        dato che alcune viste Intune la leggono ancora.
        SECONDO BUG REALE trovato subito dopo, nello stesso test dal vivo: con un solo gruppo in
        -ScopeGroupIds, il body JSON inviato aveva "resourceScopes" come STRINGA scalare invece di
        array di un elemento - Graph rispondeva 400 "ModelValidationFailure ... A 'StartArray' node
        was expected". Causa: `resourceScopes = if ($ScopeGroupIds) { $ScopeGroupIds } else { @() }`
        fa passare l'array attraverso l'output di uno statement if/else, che in PowerShell
        "spacchetta" un array con un solo elemento nello scalare contenuto (comportamento noto
        della pipeline di PowerShell, diverso da un'assegnazione diretta di variabile come
        `members = $AdminGroupIds`, che invece preserva l'array anche con un solo elemento -
        verificato dal vivo confrontando l'output di ConvertTo-Json prima/dopo). Corretto forzando
        l'array con l'operatore di subespressione array `@(...)` attorno all'intero if/else.
    #>
    param(
        [Parameter(Mandatory)] [string]$RoleDefinitionId,
        [Parameter(Mandatory)] [string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)] [string[]]$AdminGroupIds,
        [ValidateSet('resourceScope', 'allDevices', 'allLicensedUsers', 'allDevicesAndLicensedUsers')] [string]$ScopeType = 'resourceScope',
        [string[]]$ScopeGroupIds
    )
    if ($ScopeType -eq 'resourceScope' -and -not $ScopeGroupIds) { throw "-ScopeGroupIds e' obbligatorio quando -ScopeType e' 'resourceScope'." }

    $body = @{
        "@odata.type"              = "#microsoft.graph.deviceAndAppManagementRoleAssignment"
        displayName                = $DisplayName
        description                = $Description
        members                    = $AdminGroupIds
        scopeMembers               = $AdminGroupIds
        scopeType                  = $ScopeType
        resourceScopes             = @(if ($ScopeGroupIds) { $ScopeGroupIds } else { @() })
        "roleDefinition@odata.bind" = "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions('$RoleDefinitionId')"
    }
    $assignment = Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/roleAssignments" -Body $body -Beta
    Write-Host "Assegnazione ruolo creata: $($assignment.displayName) ($($assignment.id)) su ruolo $RoleDefinitionId." -ForegroundColor Green
    $assignment
}
