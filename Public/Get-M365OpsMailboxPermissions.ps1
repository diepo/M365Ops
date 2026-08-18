function Get-M365OpsMailboxPermissions {
    <#
    .SYNOPSIS
        Restituisce i permessi (FullAccess, SendAs, SendOnBehalf) su una mailbox specifica.
        Dato Exchange Online, non disponibile via Graph.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity
    )
    Connect-M365OpsExchange

    $fullAccess = Get-EXOMailboxPermission -Identity $Identity |
        Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.IsInherited -eq $false } |
        Select-Object @{n = 'User'; e = { $_.User.ToString() } }, @{n = 'Rights'; e = { $_.AccessRights -join ',' } }, @{n = 'Type'; e = { 'FullAccess' } }

    $sendAs = Get-EXORecipientPermission -Identity $Identity |
        Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" } |
        Select-Object @{n = 'User'; e = { $_.Trustee.ToString() } }, @{n = 'Rights'; e = { $_.AccessRights -join ',' } }, @{n = 'Type'; e = { 'SendAs' } }

    $mailbox = Get-EXOMailbox -Identity $Identity -Properties GrantSendOnBehalfTo
    $sendOnBehalf = $mailbox.GrantSendOnBehalfTo | ForEach-Object {
        [pscustomobject]@{ User = $_; Rights = 'SendOnBehalf'; Type = 'SendOnBehalf' }
    }

    @($fullAccess) + @($sendAs) + @($sendOnBehalf)
}
