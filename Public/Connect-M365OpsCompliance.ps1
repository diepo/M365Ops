function Connect-M365OpsCompliance {
    <#
    .SYNOPSIS
        Connette a Security & Compliance PowerShell (Purview) usando il tenant attivo - stesso
        modulo ExchangeOnlineManagement gia' usato per Exchange Online, ma un endpoint diverso
        (Connect-IPPSSession invece di Connect-ExchangeOnline). Stesso identico principio di
        governance di Connect-M365OpsExchange: silenziosa su AppOnly (stesso certificato), su
        Delegato richiede -AllowInteractive esplicito perche' il server e' a thread singolo e
        un login bloccante qui congelerebbe l'intera app per chiunque, non solo per chi ha
        fatto la richiesta.
    #>
    param([switch]$Force, [switch]$AllowInteractive)

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    if ($script:M365OpsComplianceConnected -and -not $Force) { return }

    if ($script:M365OpsContext.AuthMode -eq 'Delegated' -and -not $AllowInteractive) {
        throw "Sessione Security & Compliance (Purview) non ancora attiva per questo tenant delegato. Il server non avvia mai un login interattivo da solo (bloccherebbe l'intera app per tutti, essendo a thread singolo) - vai al tab Tenant (sezione 'Stato connessioni'), Purview/Compliance, e clicca 'Connetti / Test connessione Purview' per farlo esplicitamente, poi riprova."
    }

    # GUARDIA RIMOSSA QUI il 24/08/2026 (vedi Connect-M365OpsExchange.ps1 per il dettaglio
    # completo): il conflitto MicrosoftTeams/ExchangeOnlineManagement non e' bidirezionale,
    # Teams-poi-Exchange/Purview e' sicuro con il pin 3.9.0 sotto (verificato dal vivo anche su
    # Connect-IPPSSession specificamente, non solo Connect-ExchangeOnline) - l'ordine inverso
    # resta rotto e la sua guardia vive in Connect-M365OpsTeams.ps1.
    #
    # Versione FISSATA a 3.9.0, confermata conflict-free con MicrosoftTeams (23/08/2026) - vedi
    # Connect-M365OpsExchange.ps1 per il dettaglio completo della verifica dal vivo.
    # Assert-M365OpsExoSafeVersion (Private) disinstalla anche attivamente una eventuale
    # versione >= 3.10.0 gia' presente sul disco, non solo installa la 3.9.0 se manca.
    $script:M365OpsExoSafeVersion = '3.9.0'
    Assert-M365OpsExoSafeVersion
    Import-Module ExchangeOnlineManagement -RequiredVersion $script:M365OpsExoSafeVersion -ErrorAction Stop
    $script:M365OpsExchangeModuleImported = $true

    if ($script:M365OpsContext.AuthMode -eq 'Delegated') {
        if (-not $script:M365OpsContext.DelegatedUpn) {
            throw "Il profilo '$($script:M365OpsContext.Name)' e' in modalita' Delegated ma non ha un DelegatedUpn configurato. Usa Set-M365OpsTenant -DelegatedUpn per impostarlo."
        }
        Connect-IPPSSession -UserPrincipalName $script:M365OpsContext.DelegatedUpn -Device -ShowBanner:$false
        $script:M365OpsComplianceConnected = $true
        return
    }

    if (-not $script:M365OpsContext.ExchangeCertThumbprint) {
        throw "Il profilo '$($script:M365OpsContext.Name)' non ha un ExchangeCertThumbprint configurato. Usa Set-M365OpsTenant -ExchangeCertThumbprint per impostarlo."
    }

    Connect-IPPSSession `
        -AppId $script:M365OpsContext.ClientId `
        -CertificateThumbprint $script:M365OpsContext.ExchangeCertThumbprint `
        -Organization $script:M365OpsContext.TenantId `
        -ShowBanner:$false

    $script:M365OpsComplianceConnected = $true
}
