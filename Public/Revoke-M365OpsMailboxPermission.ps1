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
    if ($PermissionType -eq 'FullAccess') {
        $params = @{ Identity = $Identity; User = $User; AccessRights = 'FullAccess'; Confirm = $false }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Remove-MailboxPermission @params | Out-Null
    } else {
        $params = @{ Identity = $Identity; Trustee = $User; AccessRights = 'SendAs'; Confirm = $false }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Remove-RecipientPermission @params | Out-Null
    }
    Write-Host "Permesso $PermissionType rimosso da $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; PermissionType = $PermissionType; Revoked = $true }
}
