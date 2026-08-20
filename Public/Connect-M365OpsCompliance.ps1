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

    # Conflitto noto MicrosoftTeams/ExchangeOnlineManagement (22/08/2026) - vedi
    # Connect-M365OpsExchange.ps1 per il dettaglio completo. Questa funzione importa lo
    # stesso modulo ExchangeOnlineManagement, quindi eredita lo stesso rischio.
    if ($script:M365OpsTeamsModuleImported) {
        throw "Impossibile connettersi a Purview: il modulo MicrosoftTeams e' gia' stato caricato in questo stesso processo server, e i due moduli portano versioni incompatibili delle stesse librerie di autenticazione - conflitto noto e documentato di Microsoft (non un bug di M365Ops), presente da anni, senza soluzione lato modulo. Riavvia il server (pulsante Manutenzione, o 'M365Ops - Termina e riavvia' sul Desktop se non risponde) per liberare il processo."
    }

    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        # TLS1.2/provider NuGet/-SkipPublisherCheck (22/08/2026): stesso irrobustimento
        # applicato a Connect-M365OpsTeams.ps1 dopo un blocco reale trovato dal vivo - senza,
        # Install-Module puo' restare in attesa per sempre di un prompt di conferma mai
        # mostrato in un processo server senza finestra visibile (vedi quel file per il
        # dettaglio completo).
        Write-Host "Modulo ExchangeOnlineManagement non trovato, lo installo..." -ForegroundColor Yellow
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null } catch {}
        }
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
    }
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
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
