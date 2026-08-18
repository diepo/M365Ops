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

    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Host "Modulo ExchangeOnlineManagement non trovato, lo installo..." -ForegroundColor Yellow
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

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
