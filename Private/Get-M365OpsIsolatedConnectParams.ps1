function Get-M365OpsIsolatedConnectParams {
    <#
    .SYNOPSIS
        Costruisce l'hashtable di parametri da passare al metodo "connect" del worker isolato
        per il tenant attivo - vedi Connect-M365OpsIsolatedModule.ps1. Supporta sia App-only
        (certificato) sia Delegato (27/08/2026, richiesto con massima priorita' dal vivo
        dall'utente: conflitto reale Teams+Exchange poi Purview su un tenant Delegato,
        isolamento fino a qui disponibile solo per App-only - vedi
        M365OpsIsolatedWorker.ps1 per il dettaglio completo del ramo Delegato aggiunto).
    .NOTES
        Delegato: NIENTE device-code (-Device) qui, a differenza di Connect-M365OpsExchange.ps1
        nel processo principale - il worker isolato usa stdout per il protocollo JSON-RPC
        stesso (il chiamante legge ogni riga aspettandosi JSON), e -Device stampa il
        codice+URL come testo semplice su quello stesso stream: nessun umano lo leggerebbe
        mai li', e la richiesta "connect" resterebbe bloccata fino al timeout senza che
        l'utente sappia mai che un codice era stato generato (stessa classe di bug gia' vista
        con Connect-MicrosoftTeams -UseDeviceAuthentication, sezione 17.14, causa diversa
        stesso sintomo). Si usa invece il flusso interattivo a solo -UserPrincipalName (popup
        browser/WAM, una finestra GUI separata che non tocca affatto stdout) - lo stesso
        identico principio gia' in uso per Teams delegato e per Purview delegato standalone
        nel processo principale (vedi Connect-M365OpsTeams.ps1/Connect-M365OpsCompliance.ps1).
    #>
    param([Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $script:M365OpsContext.DelegatedUpn) {
            throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
        }
        if ($ModuleType -eq 'Exchange') {
            # Popup interattivo (browser/WAM) nel processo isolato - vedi .NOTES sopra per il
            # perche' non e' un device-code. L'utente dovra' completare un secondo login (oltre
            # a quello gia' fatto nel processo principale) perche' un token/sessione non
            # attraversa mai il confine tra processi - costo accettato una tantum per la vita
            # di questo worker, non ripetuto per ogni comando successivo.
            return @{ UserPrincipalName = $script:M365OpsContext.DelegatedUpn }
        }
        # Teams: stesso identico flusso popup gia' verificato dal vivo funzionante nel
        # processo principale (Connect-M365OpsTeams.ps1) - TenantId da solo (nessun
        # certificato: e' proprio l'assenza di CertificateThumbprint che nel worker fa
        # scegliere il ramo Delegato invece di quello App-only, vedi M365OpsIsolatedWorker.ps1).
        return @{
            TenantId   = $script:M365OpsContext.TenantId
            DisableWAM = $true
        }
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
