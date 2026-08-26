function Get-M365OpsGroupsOverviewReport {
    <#
    .SYNOPSIS
        Report aggregato di tutti i tipi di gruppo lato Exchange (distribution list,
        mail-enabled security group, dynamic distribution group) con conteggio membri.
    #>
    Connect-M365OpsExchange
    $static = Get-DistributionGroup -ResultSize Unlimited
    $dynamic = Get-DynamicDistributionGroup -ResultSize Unlimited

    # Ogni gruppo e' un'unita' di lavoro indipendente dalle altre (26/08/2026, stesso schema
    # gia' corretto piu' volte in questa maratona - v0.10.1/v0.10.2/v0.10.6, e appena riapplicato
    # al report gemello Get-M365OpsGroupMembershipReport): PRIMA di questo fix, il conteggio
    # membri per UN solo gruppo problematico (es. oggetto rimosso nel frattempo, throttling
    # momentaneo Exchange Online) lanciava un errore terminante che usciva dall'INTERO report,
    # facendo sparire in silenzio anche i gruppi sani gia' elaborati con successo.
    $staticRows = $static | ForEach-Object {
        $type = if ($_.GroupType -match 'SecurityEnabled') { 'MailSecurityGroup' } else { 'DistributionList' }
        try {
            $memberCount = (Get-DistributionGroupMember -Identity $_.Identity -ResultSize Unlimited -ErrorAction Stop).Count
        }
        catch {
            $memberCount = "Errore: $($_.Exception.Message)"
        }
        [pscustomobject]@{ DisplayName = $_.DisplayName; PrimarySmtpAddress = $_.PrimarySmtpAddress; Type = $type; MemberCount = $memberCount }
    }
    $dynamicRows = $dynamic | ForEach-Object {
        [pscustomobject]@{ DisplayName = $_.DisplayName; PrimarySmtpAddress = $_.PrimarySmtpAddress; Type = 'DynamicDistributionGroup'; MemberCount = $null }
    }

    @($staticRows) + @($dynamicRows)
}
