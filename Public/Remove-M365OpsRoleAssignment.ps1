function Remove-M365OpsRoleAssignment {
    <#
    .SYNOPSIS
        Rimuove un'assegnazione di ruolo RBAC Intune.
    .NOTES
        BUG REALE trovato e corretto il 23/08/2026 (stessa causa di Set-M365OpsRoleAssignment,
        vedi le sue .NOTES): il tipo concreto usato da Intune
        (deviceAndAppManagementRoleAssignment) espone DELETE solo sulla collezione di primo
        livello "/deviceManagement/roleAssignments/{id}", non annidata sotto roleDefinitions - la
        vecchia rotta annidata avrebbe fallito con lo stesso 400 "No OData route" della create
        (mai verificato dal vivo prima d'ora perche' nessuna assegnazione era mai stata creata con
        successo). -RoleDefinitionId mantenuto nella firma per compatibilita' con i chiamanti
        esistenti ma non piu' usato nel path.
    #>
    param(
        [Parameter(Mandatory)] [string]$RoleDefinitionId,
        [Parameter(Mandatory)] [string]$AssignmentId
    )
    Invoke-M365OpsGraphRequest -Method DELETE -Path "/deviceManagement/roleAssignments/$AssignmentId" -Beta | Out-Null
    Write-Host "Assegnazione ruolo $AssignmentId rimossa dal ruolo $RoleDefinitionId." -ForegroundColor Green
}
