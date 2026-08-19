function Remove-M365OpsSharedMailbox {
    <#
    .SYNOPSIS
        Elimina una mailbox condivisa (usa lo stesso Remove-Mailbox nativo di sale riunioni
        e attrezzature - funziona anche su quelle, ma il nome resta specifico per coerenza
        con New-M365OpsSharedMailbox). -ExtraParams passa altri parametri nativi di
        Remove-Mailbox (es. Permanent) - se non sei sicuro del nome esatto, consulta prima
        lookup_ms_docs "Remove-Mailbox".

        Gap reale trovato dal vivo il 18/08/2026 durante uno stress test: New-/Remove- per
        le mailbox di risorsa esistevano solo per la creazione, mai per la rimozione - la
        pulizia di un test richiedeva il cmdlet nativo fuori da M365Ops.
    #>
    param(
        [Parameter(Mandatory)] [string]$Identity,
        [hashtable]$ExtraParams = @{}
    )
    Connect-M365OpsExchange
    # -ErrorAction Stop: stesso bug di errore non terminante ignorato in silenzio gia' trovato
    # su Add-M365OpsDistributionGroupMember (bug-hunt 19/08/2026).
    $params = @{ Identity = $Identity; Confirm = $false; ErrorAction = 'Stop' }
    foreach ($key in $ExtraParams.Keys) { $params[$key] = $ExtraParams[$key] }
    Remove-Mailbox @params
    Write-Host "Mailbox rimossa: $Identity" -ForegroundColor Green
    [pscustomobject]@{ Identity = $Identity; Removed = $true }
}
