function Revoke-M365OpsMailboxPermission {
    <#
    .SYNOPSIS
        Rimuove un permesso FullAccess o SendAs su una mailbox da un utente. -ExtraParams
        passa altri parametri nativi di Remove-MailboxPermission/Remove-RecipientPermission
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs
        "Remove-MailboxPermission" o "Remove-RecipientPermission".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [ValidateSet('FullAccess', 'SendAs')] [string]$PermissionType,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop su entrambi i rami: stesso bug di errore non terminante ignorato in
    # silenzio gia' trovato su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    if ($PermissionType -eq 'FullAccess') {
        $params = @{ Identity = $Identity; User = $User; AccessRights = 'FullAccess'; Confirm = $false; ErrorAction = 'Stop' }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Remove-MailboxPermission @params | Out-Null
    } else {
        $params = @{ Identity = $Identity; Trustee = $User; AccessRights = 'SendAs'; Confirm = $false; ErrorAction = 'Stop' }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Remove-RecipientPermission @params | Out-Null
    }
    Write-Host "Permesso $PermissionType rimosso da $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; PermissionType = $PermissionType; Revoked = $true }
}
