function Disconnect-M365OpsCompliance {
    <#
    .SYNOPSIS
        Chiude la connessione Security & Compliance (Purview) PowerShell, se attiva.
    .NOTES
        Disconnect-ExchangeOnline chiude TUTTE le sessioni remote del modulo
        ExchangeOnlineManagement per questo processo, incluse quelle Compliance/IPPS aperte con
        Connect-IPPSSession (comportamento del modulo stesso, non specifico di questo progetto) -
        se Exchange e' gia' stato disconnesso separatamente questa chiamata e' quindi un no-op
        sicuro (-ErrorAction SilentlyContinue), ma il FLAG va comunque azzerato qui: senza
        questa funzione (bug latente trovato il 27/08/2026, mai una funzione dedicata) restava
        "connesso" anche a sessione reale gia' chiusa, es. dopo un Disconnect-M365OpsExchange
        separato o dopo un cambio tenant (Connect-M365Ops disconnette gia' Exchange/Teams/
        SharePoint ad ogni cambio profilo, ma non aveva mai chiamato questa).
    #>
    if ($script:M365OpsComplianceConnected) {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        $script:M365OpsComplianceConnected = $false
    }
}
