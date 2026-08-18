function New-M365OpsRemoteDomain {
    <#
    .SYNOPSIS
        Crea una voce di dominio remoto personalizzata (per controllare il comportamento
        di invio verso un dominio esterno specifico, diverso dal default del tenant).
    #>
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$DomainName
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in New-M365OpsTenantAllowBlockListSpoofItem.ps1 (bug reale 18/08/2026).
    $rd = New-RemoteDomain -Name $Name -DomainName $DomainName -Confirm:$false -ErrorAction Stop
    Write-Host "Dominio remoto creato: $Name ($DomainName)" -ForegroundColor Green
    $rd | Select-Object Name, DomainName
}
