function Get-M365OpsPartnerConnectorsStatus {
    <#
    .SYNOPSIS
        Legge lo stato dei connettori partner Intune (Mobile Threat Defense, connettori
        Exchange on-prem, partner di conformita' di terze parti, partner di assistenza remota,
        impostazioni Apple DEP/ABM, token VPP). SOLO LETTURA per design: l'attivazione iniziale
        di questi connettori richiede un flusso di consenso OAuth interattivo con il servizio
        partner (es. Apple Business Manager, un MTD provider) che non e' realizzabile tramite
        semplici chiamate REST - va fatto una volta dal Centro Amministrazione Intune. Ogni
        lettura e' avvolta in try/catch: un tenant senza quel tipo di connettore configurato
        restituisce una lista vuota o un 404, non un errore bloccante.
    #>
    param()

    function Get-Safe([string]$path) {
        try { (Invoke-M365OpsGraphRequest -Method GET -Path $path -Beta).value } catch { @() }
    }

    [pscustomobject]@{
        MobileThreatDefenseConnectors = Get-Safe "/deviceManagement/mobileThreatDefenseConnectors"
        ExchangeConnectors            = Get-Safe "/deviceManagement/exchangeConnectors"
        ComplianceManagementPartners  = Get-Safe "/deviceManagement/complianceManagementPartners"
        RemoteAssistancePartners      = Get-Safe "/deviceManagement/remoteAssistancePartners"
        DepOnboardingSettings         = Get-Safe "/deviceManagement/depOnboardingSettings"
        VppTokens                     = Get-Safe "/deviceAppManagement/vppTokens"
    }
}
