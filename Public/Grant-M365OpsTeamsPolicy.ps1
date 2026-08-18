function Grant-M365OpsTeamsPolicy {
    <#
    .SYNOPSIS
        Assegna (o resetta al default del tenant, omettendo -PolicyName) una policy Teams a un
        utente - meeting (include registrazione/recording), messaging, app setup o app
        permission. Copre l'assegnazione di una policy ESISTENTE, non la creazione/modifica del
        contenuto della policy stessa (fuori perimetro attuale).
    .PARAMETER PolicyName
        Nome esatto della policy (da Get-M365OpsTeamsPolicies) - mai indovinato. Omesso, resetta
        l'utente alla policy globale/default del tenant.
    #>
    param(
        [Parameter(Mandatory)] [string]$Upn,
        [Parameter(Mandatory)] [ValidateSet('Meeting', 'Messaging', 'AppSetup', 'AppPermission')] [string]$PolicyType,
        [string]$PolicyName
    )
    Connect-M365OpsTeams

    # Bug reale trovato dal vivo il 18/08/2026: i cmdlet Grant-CsTeams*Policy trattano
    # -PolicyName come obbligatorio - OMETTERLO del tutto fallisce con "missing mandatory
    # parameters: PolicyName" invece di resettare al default. Per il reset va passato
    # esplicitamente -PolicyName $null (comportamento nativo Microsoft, non un default PowerShell).
    $params = @{ Identity = $Upn; PolicyName = $PolicyName }

    switch ($PolicyType) {
        'Meeting'       { Grant-CsTeamsMeetingPolicy @params }
        'Messaging'     { Grant-CsTeamsMessagingPolicy @params }
        'AppSetup'      { Grant-CsTeamsAppSetupPolicy @params }
        'AppPermission' { Grant-CsTeamsAppPermissionPolicy @params }
    }

    $policyText = if ($PolicyName) { $PolicyName } else { '(default/globale del tenant)' }
    Write-Host "Policy $PolicyType di $Upn impostata a $policyText" -ForegroundColor Green
    [pscustomobject]@{ Upn = $Upn; PolicyType = $PolicyType; PolicyName = $policyText }
}
