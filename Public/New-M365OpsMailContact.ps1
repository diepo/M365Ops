function New-M365OpsMailContact {
    <#
    .SYNOPSIS
        Crea un contatto di posta esterno. -ExtraParams passa altri parametri nativi di
        New-MailContact (es. FirstName, LastName, OrganizationalUnit) - se non sei sicuro
        del nome esatto, consulta prima lookup_ms_docs "New-MailContact".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$ExternalEmailAddress,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; ExternalEmailAddress = $ExternalEmailAddress }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $contact = New-MailContact @params
    Write-Host "Contatto creato: $($contact.DisplayName) ($ExternalEmailAddress)" -ForegroundColor Green
    $contact | Select-Object DisplayName, PrimarySmtpAddress, ExternalEmailAddress
}
