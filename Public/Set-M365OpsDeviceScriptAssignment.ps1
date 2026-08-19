function Set-M365OpsDeviceScriptAssignment {
    <#
    .SYNOPSIS
        Assegna uno script di distribuzione Intune a uno o piu' gruppi - SOSTITUISCE l'intero
        elenco di assegnazioni esistenti. Corpo verificato dal vivo su Microsoft Learn per
        deviceManagementScript (Windows) il 19/08/2026 - forma semplice
        deviceManagementScriptGroupAssignments (targetGroupId diretto, non il target annidato
        piu' recente usato altrove in questo modulo, ma quella documentata come valida per
        questa specifica risorsa). La forma per macOS (deviceShellScriptGroupAssignments) segue
        per coerenza la stessa convenzione di naming Microsoft gia' verificata per Windows, non
        verificata dal vivo separatamente - se dovesse differire, l'errore Graph lo segnalerebbe
        chiaramente (nome proprieta' non riconosciuto), mai un fallimento silenzioso.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Windows', 'macOS')] [string]$Platform,
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $base = if ($Platform -eq 'Windows') { "/deviceManagement/deviceManagementScripts" } else { "/deviceManagement/deviceShellScripts" }
    $odataType = if ($Platform -eq 'Windows') { "microsoft.graph.deviceManagementScriptGroupAssignment" } else { "microsoft.graph.deviceShellScriptGroupAssignment" }
    $bodyKey = if ($Platform -eq 'Windows') { "deviceManagementScriptGroupAssignments" } else { "deviceShellScriptGroupAssignments" }

    $assignments = @($TargetGroupIds | ForEach-Object { @{ "@odata.type" = $odataType; targetGroupId = $_ } })
    $body = @{ $bodyKey = $assignments }

    Invoke-M365OpsGraphRequest -Method POST -Path "$base/$Identity/assign" -Body $body -Beta | Out-Null
    Write-Host "Script $Identity assegnato a $($TargetGroupIds.Count) gruppo/i [$Platform]." -ForegroundColor Green
}
