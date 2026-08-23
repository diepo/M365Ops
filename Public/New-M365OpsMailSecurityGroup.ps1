function New-M365OpsMailSecurityGroup {
    <#
    .SYNOPSIS
        Crea un gruppo di sicurezza abilitato alla posta. -ExtraParams passa altri
        parametri nativi di New-DistributionGroup (es. ManagedBy, RequireSenderAuthenticationEnabled)
        - se non sei sicuro del nome esatto, consulta prima lookup_ms_docs "New-DistributionGroup".
    #>
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$PrimarySmtpAddress,
        [string[]]$Members,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026) - mancava qui, trovato dal
    # vivo in un bug-hunt successivo (26/08/2026) scandendo sistematicamente ogni chiamata a
    # cmdlet Exchange nativi del progetto.
    $params = @{ Name = $DisplayName; DisplayName = $DisplayName; PrimarySmtpAddress = $PrimarySmtpAddress; Type = 'Security'; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }

    $grp = New-DistributionGroup @params

    # Stesso bug reale e stessa correzione di New-M365OpsDistributionGroup.ps1 (trovato dal
    # vivo il 23/08/2026, bug-hunt di 16 ore) - vedi li' per il dettaglio completo: il gruppo
    # e' gia' un fatto compiuto a questo punto, un membro non valido non deve far sparire
    # l'intera operazione dietro un'eccezione che farebbe credere al chiamante che NULLA sia
    # stato creato.
    $failedMembers = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $Members) {
        try {
            Add-DistributionGroupMember -Identity $grp.Identity -Member $m -Confirm:$false -ErrorAction Stop
        } catch {
            $failedMembers.Add("$m ($($_.Exception.Message))")
        }
    }
    if ($failedMembers.Count -gt 0) {
        Write-Host "Mail security group creato: $($grp.DisplayName) ($($grp.PrimarySmtpAddress)) - ATTENZIONE, alcuni membri NON sono stati aggiunti: $($failedMembers -join '; ')" -ForegroundColor Yellow
    } else {
        Write-Host "Mail security group creato: $($grp.DisplayName) ($($grp.PrimarySmtpAddress))" -ForegroundColor Green
    }
    $result = $grp | Select-Object DisplayName, PrimarySmtpAddress, GroupType
    if ($failedMembers.Count -gt 0) { $result | Add-Member -NotePropertyName MembriNonAggiunti -NotePropertyValue @($failedMembers) }
    $result
}
