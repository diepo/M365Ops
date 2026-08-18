function Get-M365OpsMailContacts {
    <#
    .SYNOPSIS
        Elenca i contatti di posta esterni (mail contact) del tenant.
    #>
    Connect-M365OpsExchange
    Get-MailContact -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, ExternalEmailAddress
}
