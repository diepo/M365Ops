function Get-M365OpsMailUsers {
    <#
    .SYNOPSIS
        Elenca i mail user (utenti con recapito su una mailbox esterna al tenant) -
        diversi dai mail contact.
    #>
    Connect-M365OpsExchange
    Get-MailUser -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, ExternalEmailAddress
}
