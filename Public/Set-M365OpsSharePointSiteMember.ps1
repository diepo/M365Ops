function Set-M365OpsSharePointSiteMember {
    <#
    .SYNOPSIS
        Aggiunge o rimuove un utente da uno dei gruppi standard di un sito SharePoint
        (Owners/Members/Visitors) - stesso livello di Get-M365OpsSharePointSitePermissions, non
        scende a permessi granulari su singoli file/cartelle.
    .PARAMETER Role
        'Owners', 'Members' oppure 'Visitors' - il gruppo effettivo viene trovato per
        corrispondenza sul nome (stesso metodo di Get-M365OpsSharePointSitePermissions), perche'
        il nome esatto del gruppo varia da sito a sito (es. "Progetto X Owners").
    #>
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [ValidateSet('Owners', 'Members', 'Visitors')] [string]$Role,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [ValidateSet('Add', 'Remove')] [string]$Action
    )
    Connect-M365OpsSharePoint -SiteUrl $SiteUrl

    $group = Get-PnPGroup | Where-Object { $_.Title -like "*$Role*" } | Select-Object -First 1
    if (-not $group) { throw "Nessun gruppo '$Role' trovato sul sito $SiteUrl - verifica prima con Get-M365OpsSharePointSitePermissions." }

    if ($Action -eq 'Add') {
        Add-PnPGroupMember -Group $group.Title -LoginName $User | Out-Null
    } else {
        Remove-PnPGroupMember -Group $group.Title -LoginName $User | Out-Null
    }

    Write-Host "$User $(if ($Action -eq 'Add') { 'aggiunto a' } else { 'rimosso da' }) '$($group.Title)' su $SiteUrl" -ForegroundColor Green
    [pscustomobject]@{ SiteUrl = $SiteUrl; Group = $group.Title; User = $User; Action = $Action }
}
