function Get-M365OpsAssignmentMatches {
    <#
    .SYNOPSIS
        Dato un percorso Graph di oggetti assegnabili (app, config profile, compliance policy)
        e un elenco di group id, restituisce quali di quegli oggetti risultano assegnati
        (direttamente al gruppo, o via 'All Users'/'All Devices'). Una sola chiamata Graph
        con $expand=assignments invece di N+1 — usata sia per la panoramica utente sia gruppo.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string[]]$GroupIds,
        [hashtable]$GroupNamesById = @{}
    )

    $items = (Invoke-M365OpsGraphRequest -Method GET -Path "$Path`?`$expand=assignments" -Beta).value
    $results = @()

    foreach ($item in $items) {
        foreach ($a in $item.assignments) {
            $t = $a.target.'@odata.type'
            $isUniversal = $t -in @('#microsoft.graph.allLicensedUsersAssignmentTarget', '#microsoft.graph.allDevicesAssignmentTarget')
            $isGroupMatch = ($t -eq '#microsoft.graph.groupAssignmentTarget') -and ($a.target.groupId -in $GroupIds)

            if ($isUniversal -or $isGroupMatch) {
                $via = if ($t -eq '#microsoft.graph.allDevicesAssignmentTarget') { 'All Devices' }
                       elseif ($t -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') { 'All Users' }
                       elseif ($GroupNamesById.ContainsKey($a.target.groupId)) { $GroupNamesById[$a.target.groupId] }
                       else { $a.target.groupId }

                $results += [pscustomobject]@{
                    Name   = $item.displayName
                    Intent = $a.intent
                    Via    = $via
                }
            }
        }
    }

    return $results
}
