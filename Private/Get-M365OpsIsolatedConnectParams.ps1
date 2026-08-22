function Get-M365OpsIsolatedConnectParams {
    <#
    .SYNOPSIS
        Costruisce l'hashtable di parametri da passare al metodo "connect" del worker isolato
        per il tenant attivo - vedi Connect-M365OpsIsolatedModule.ps1. SOLO App-only per ora
        (vedi .NOTES li'): lancia un errore chiaro per un tenant Delegato invece di un
        tentativo instabile.
    #>
    param([Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        throw "L'isolamento reattivo per il conflitto Teams/Exchange non e' ancora supportato su tenant Delegati (richiede un login interattivo dedicato al processo isolato, non ancora implementato) - riavvia il server (pulsante Manutenzione) e riprova, ripartendo dall'ordine di connessione che ha funzionato l'ultima volta."
    }

    if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
        throw "L'isolamento reattivo richiede un certificato configurato per questo profilo (ExchangeCertThumbprint) - lo stesso gia' usato per la connessione diretta. Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarne uno."
    }

    $params = @{
        AppId                 = $script:M365OpsContext.ClientId
        CertificateThumbprint = $script:M365OpsContext.ExchangeCertThumbprint
    }
    if ($ModuleType -eq 'Exchange') {
        $params.Organization = $script:M365OpsContext.TenantId
    } else {
        $params.TenantId = $script:M365OpsContext.TenantId
        # DisableWAM: stesso controllo dinamico gia' in Connect-M365OpsTeams.ps1 (il broker
        # WAM, di default dalla 7.8.1-preview in poi, fallisce in un processo senza sessione
        # interattiva) - qui pero' NON possiamo interrogare la versione del modulo REALMENTE
        # importata nel worker (vive in un altro processo) prima di provare a connettersi,
        # quindi lo passiamo sempre: il worker stesso lo applica solo se il parametro esiste
        # davvero su questa versione (vedi M365OpsIsolatedWorker.ps1), innocuo altrimenti.
        $params.DisableWAM = $true
    }
    $params
}
