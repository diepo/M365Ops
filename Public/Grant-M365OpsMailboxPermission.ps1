function Grant-M365OpsMailboxPermission {
    <#
    .SYNOPSIS
        Assegna un permesso FullAccess o SendAs su una mailbox a un utente. -ExtraParams
        passa altri parametri nativi di Add-MailboxPermission/Add-RecipientPermission (es.
        Deny, InheritanceType, AutoMapping) - se non sei sicuro del nome esatto, consulta
        prima lookup_ms_docs "Add-MailboxPermission" o "Add-RecipientPermission".
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [ValidateSet('FullAccess', 'SendAs')] [string]$PermissionType,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    if ($PermissionType -eq 'FullAccess') {
        $params = @{ Identity = $Identity; User = $User; AccessRights = 'FullAccess'; InheritanceType = 'All'; AutoMapping = $true }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Add-MailboxPermission @params | Out-Null
    } else {
        $params = @{ Identity = $Identity; Trustee = $User; AccessRights = 'SendAs'; Confirm = $false }
        foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
        Add-RecipientPermission @params | Out-Null
    }
    Write-Host "Permesso $PermissionType concesso a $User su $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; User = $User; PermissionType = $PermissionType; Granted = $true }
}
