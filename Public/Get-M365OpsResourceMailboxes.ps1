function Get-M365OpsResourceMailboxes {
    <#
    .SYNOPSIS
        Elenca le mailbox risorsa (sale riunioni ed attrezzature).
    #>
    Connect-M365OpsExchange
    Get-EXOMailbox -RecipientTypeDetails RoomMailbox, EquipmentMailbox -ResultSize Unlimited |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
}
