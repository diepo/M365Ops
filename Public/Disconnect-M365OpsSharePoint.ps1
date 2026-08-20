function Disconnect-M365OpsSharePoint {
    <#
    .SYNOPSIS
        Chiude la connessione SharePoint/PnP PowerShell, se attiva.
    #>
    if ($script:M365OpsSharePointConnectedUrl) {
        Disconnect-PnPOnline -ErrorAction SilentlyContinue
        $script:M365OpsSharePointConnectedUrl = $null
    }
}
