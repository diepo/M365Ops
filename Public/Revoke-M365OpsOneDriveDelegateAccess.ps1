function Revoke-M365OpsOneDriveDelegateAccess {
    <#
    .SYNOPSIS
        Ultimo passo del workaround "accesso negato nonostante lo sharing OneDrive": rimuove
        -AdminUpn dagli amministratori della raccolta siti sul OneDrive di -OwnerUpn - da usare
        DOPO aver verificato che il destinatario e' riuscito a riottenere l'accesso (annulla
        l'accesso temporaneo concesso da Grant-M365OpsOneDriveDelegateAccess).
    #>
    param(
        [Parameter(Mandatory)] [string]$OwnerUpn,
        [Parameter(Mandatory)] [string]$AdminUpn
    )

    $drive = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$OwnerUpn/drive?`$select=webUrl"
    if (-not $drive.webUrl) { throw "Impossibile trovare il OneDrive di '$OwnerUpn' (utente inesistente o senza licenza OneDrive)." }
    $oneDriveUrl = ($drive.webUrl -replace '/Documents/?$', '')

    Connect-M365OpsSharePoint -SiteUrl $oneDriveUrl
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026), qui sul modulo PnP.PowerShell.
    Remove-PnPSiteCollectionAdmin -Owners $AdminUpn -ErrorAction Stop

    Write-Host "$AdminUpn rimosso dagli amministratori di $oneDriveUrl" -ForegroundColor Green
    [pscustomobject]@{ OwnerUpn = $OwnerUpn; AdminUpn = $AdminUpn; OneDriveUrl = $oneDriveUrl; Removed = $true }
}
