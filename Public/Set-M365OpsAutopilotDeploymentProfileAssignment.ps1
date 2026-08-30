function Set-M365OpsAutopilotDeploymentProfileAssignment {
    <#
    .SYNOPSIS
        Assegna un profilo di distribuzione Autopilot a uno o piu' gruppi. AGGIUNGE una
        assegnazione per ciascun gruppo (comportamento additivo, NON sostituisce l'elenco
        esistente - a differenza di Set-M365OpsConfigurationPolicyAssignment).
        I gruppi target devono essere gruppi di DISPOSITIVI (dynamic device group basato su
        seriale/gruppo Autopilot, tipico "groupTag"), non gruppi di utenti.
    .NOTES
        Verificato dal vivo su Microsoft Learn il 31/08/2026: l'azione
        /deviceManagement/windowsAutopilotDeploymentProfiles/{id}/assign accetta SOLO il
        parametro "deviceIds" (String collection) - non supporta assegnazioni a gruppi e non
        e' quindi utilizzabile per questa funzione. La risorsa windowsAutopilotDeploymentProfile
        espone invece una relationship "assignments" (collection di
        windowsAutopilotDeploymentProfileAssignment, "The list of group assignments for the
        profile") su cui si puo' fare POST diretto con un oggetto { target:
        { "@odata.type": "#microsoft.graph.groupAssignmentTarget", groupId } } - lo stesso
        approccio usato dal modulo community WindowsAutopilotIntune
        (Set-AutopilotProfileAssignedGroup). Questa funzione ora usa quel percorso, un POST
        per gruppo; essendo una collection additiva (non un'azione "assign" sostitutiva), le
        assegnazioni esistenti non vengono rimosse.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$TargetGroupIds
    )
    $result = @($TargetGroupIds | ForEach-Object {
        $body = @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $_ } }
        Invoke-M365OpsGraphRequest -Method POST -Path "/deviceManagement/windowsAutopilotDeploymentProfiles/$Identity/assignments" -Body $body -Beta
    })
    Write-Host "Profilo Autopilot $Identity assegnato a $($TargetGroupIds.Count) gruppo/i." -ForegroundColor Green
    $result
}
