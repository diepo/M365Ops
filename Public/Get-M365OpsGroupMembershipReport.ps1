function Get-M365OpsGroupMembershipReport {
    <#
    .SYNOPSIS
        Report unico con una riga per ogni coppia gruppo-membro, per tutte le
        distribution list e mail-enabled security group del tenant. Utile per audit
        di membership su larga scala. Puo' essere lento su tenant con molti gruppi.
    #>
    Connect-M365OpsExchange
    # Ogni gruppo e' un'unita' di lavoro indipendente dalle altre (26/08/2026, stesso schema
    # gia' corretto piu' volte in questa maratona - v0.10.1/v0.10.2/v0.10.6, e appena riapplicato
    # a Get-M365OpsMailboxDelegatesReport/Get-M365OpsSharedMailboxReport/Get-M365OpsUserOverview/
    # Get-M365OpsGroupOverview): PRIMA di questo fix, Get-DistributionGroupMember veniva chiamata
    # senza protezione dentro il ForEach-Object - un solo gruppo problematico (es. oggetto rimosso
    # nel frattempo, throttling momentaneo Exchange Online) lanciava un errore terminante che
    # usciva dall'INTERO report, facendo sparire in silenzio anche i membri dei gruppi
    # precedenti/successivi, per quanto perfettamente sani. Verificato dal vivo forzando un
    # errore su un gruppo intermedio: prima del fix, zero righe restituite anche per i gruppi
    # sani; dopo, i gruppi sani restano nel report e quello fallito produce una riga di errore
    # dedicata invece di far sparire tutto.
    Get-DistributionGroup -ResultSize Unlimited | ForEach-Object {
        $group = $_
        try {
            Get-DistributionGroupMember -Identity $group.Identity -ResultSize Unlimited -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{
                    GroupDisplayName  = $group.DisplayName
                    GroupSmtpAddress  = $group.PrimarySmtpAddress
                    MemberDisplayName = $_.DisplayName
                    MemberSmtpAddress = $_.PrimarySmtpAddress
                    MemberType        = $_.RecipientType
                }
            }
        }
        catch {
            [pscustomobject]@{
                GroupDisplayName  = $group.DisplayName
                GroupSmtpAddress  = $group.PrimarySmtpAddress
                MemberDisplayName = $null
                MemberSmtpAddress = $null
                MemberType        = "Errore: impossibile leggere i membri di questo gruppo: $($_.Exception.Message)"
            }
        }
    }
}
