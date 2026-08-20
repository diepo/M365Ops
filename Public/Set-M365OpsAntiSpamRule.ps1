function Set-M365OpsAntiSpamRule {
    <#
    .SYNOPSIS
        Modifica una regola anti-spam esistente (es. RecipientDomainIs, Priority) via
        -ExtraParams - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Set-HostedContentFilterRule". Per abilitare/disabilitare usa invece
        Enable-M365OpsAntiSpamRule/Disable-M365OpsAntiSpamRule: verificato dal vivo il
        21/08/2026 che Set-HostedContentFilterRule NON ha un parametro -Enabled (a
        differenza di quanto suggerito dalla documentazione Microsoft in alcuni punti) - la
        lista reale dei parametri del cmdlet, letta live con Get-Command, non lo contiene.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [hashtable]$ExtraParams
    )
    Connect-M365OpsExchange
    $params = @{ Identity = $Identity }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Set-HostedContentFilterRule @params -ErrorAction Stop
    Write-Host "Regola anti-spam aggiornata: $Identity" -ForegroundColor Green
}
