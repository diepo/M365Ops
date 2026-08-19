function Grant-M365OpsOneDriveDelegateAccess {
    <#
    .SYNOPSIS
        Primo passo del workaround per "utente B condivide con A, A continua a ricevere accesso
        negato nonostante lo sharing sia corretto": aggiunge -AdminUpn come amministratore della
        raccolta siti sul OneDrive personale di -OwnerUpn, cosi' da poter intervenire sulla
        condivisione (vedi Remove-M365OpsOneDriveSharingRecipient) - passo temporaneo, da
        annullare con Revoke-M365OpsOneDriveDelegateAccess una volta risolto.
    .OUTPUTS
        Include anche l'URL diretto alla pagina "membri" del sito (people.aspx) - Microsoft
        Support consiglia di aprirla manualmente in un browser dopo aver ottenuto l'accesso: in
        alcuni casi la sola visita a questa pagina, insieme alla rimozione/ri-condivisione
        sottostante, sblocca lo stato di permesso incoerente lato SharePoint - passo non
        automatizzabile da qui (richiede un browser interattivo), va fatto a mano.
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
    Add-PnPSiteCollectionAdmin -Owners $AdminUpn -ErrorAction Stop

    $peopleUrl = "$oneDriveUrl/_layouts/15/people.aspx?membershipGroupId=0"
    Write-Host "$AdminUpn aggiunto come amministratore su $oneDriveUrl" -ForegroundColor Green
    [pscustomobject]@{
        OwnerUpn    = $OwnerUpn
        AdminUpn    = $AdminUpn
        OneDriveUrl = $oneDriveUrl
        PeopleUrl   = $peopleUrl
        NextStep    = "Apri manualmente $peopleUrl in un browser autenticato come $AdminUpn per verificare i membri, poi usa Remove-M365OpsOneDriveSharingRecipient per rimuovere il destinatario dalla condivisione e far riprovare la condivisione."
    }
}
