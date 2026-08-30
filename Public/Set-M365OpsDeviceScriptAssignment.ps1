function Set-M365OpsDeviceScriptAssignment {
    <#
    .SYNOPSIS
        Assegna uno script di distribuzione Intune a uno o piu' gruppi - SOSTITUISCE l'intero
        elenco di assegnazioni esistenti. Corpo verificato dal vivo su Microsoft Learn per
        deviceManagementScript (Windows) il 19/08/2026 - forma semplice
        deviceManagementScriptGroupAssignments (targetGroupId diretto, non il target annidato
        piu' recente usato altrove in questo modulo, ma quella documentata come valida per
        questa specifica risorsa). La pagina ufficiale Microsoft Learn per
        deviceShellScripts: assign (macOS) e' stata verificata separatamente il 31/08/2026 e
        il suo esempio JSON riusa VERBATIM lo stesso tipo e la stessa chiave di Windows
        (#microsoft.graph.deviceManagementScriptGroupAssignment /
        deviceManagementScriptGroupAssignments) - non esiste una risorsa
        deviceShellScriptGroupAssignment separata in Graph.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Windows', 'macOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $base = if ($Platform -eq 'Windows') { "/deviceManagement/deviceManagementScripts" } else { "/deviceManagement/deviceShellScripts" }
    # Entrambe le piattaforme usano lo stesso @odata.type e la stessa chiave body - confermato
    # dal vivo sulla pagina Microsoft Learn "deviceShellScripts: assign", che riusa il tipo
    # Windows verbatim invece di una risorsa deviceShellScriptGroupAssignment (inesistente).
    $odataType = "#microsoft.graph.deviceManagementScriptGroupAssignment"
    $bodyKey = "deviceManagementScriptGroupAssignments"

    $assignments = @($TargetGroupIds | ForEach-Object { @{ "@odata.type" = $odataType; targetGroupId = $_ } })
    $body = @{ $bodyKey = $assignments }

    Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/assign" -Body $body -Beta | Out-Null
    Write-Host "Script $Identity assegnato a $($TargetGroupIds.Count) gruppo/i [$Platform]." -ForegroundColor Green
}
