function Update-M365OpsDistributionGroupMember {
    <#
    .SYNOPSIS
        SOSTITUISCE l'intera lista membri di un gruppo con quella fornita - non e' un
        aggiunta incrementale (per quello vedi Add-/Remove-M365OpsDistributionGroupMember).
        Chiunque non sia nell'elenco passato viene rimosso dal gruppo. Utile per
        sincronizzare la membership da una fonte esterna (es. un CSV), rischioso se usato
        a meta' di una lista pensando che aggiunga soltanto.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string[]]$Members
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: vedi nota in Set-M365OpsDistributionGroup.ps1 (bug reale 18/08/2026).
    Update-DistributionGroupMember -Identity $Identity -Members $Members -Confirm:$false -ErrorAction Stop
    Write-Host "Membership del gruppo '$Identity' sostituita con $($Members.Count) membri." -ForegroundColor Green
    Get-DistributionGroupMember -Identity $Identity -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress
}
