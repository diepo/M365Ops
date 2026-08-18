function Get-M365OpsOneDriveSharingReport {
    <#
    .SYNOPSIS
        Elenca i link di condivisione attivi sulla root del OneDrive di un utente (pubblici,
        organizzativi o con utenti specifici), con tipo di link e ambito - richiede il
        permesso Graph Sites.Read.All o Files.Read.All (Application), non incluso nel set
        di permessi di default di questo modulo: va aggiunto all'App Registration e
        concesso admin consent prima dell'uso.

    .PARAMETER Upn
        UPN dell'utente di cui leggere il OneDrive (es. mario.rossi@contoso.com).

    .NOTES
        Mode: ReadOnly
    #>
    param(
        [Parameter(Mandatory)] [string]$Upn
    )

    $permissions = Invoke-M365OpsGraphRequest -Method GET -Path "/users/$Upn/drive/root/permissions"
    $permissions.value | Where-Object { $_.link } | ForEach-Object {
        [pscustomobject]@{
            Upn        = $Upn
            LinkType   = $_.link.type
            LinkScope  = $_.link.scope
            WebUrl     = $_.link.webUrl
            GrantedTo  = ($_.grantedToIdentitiesV2 | ForEach-Object { $_.user.displayName }) -join '; '
        }
    }
}
