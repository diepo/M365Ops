function Disconnect-M365OpsTeams {
    <#
    .SYNOPSIS
        Chiude la connessione Microsoft Teams PowerShell, se attiva.
    #>
    if ($script:M365OpsTeamsConnected) {
        Disconnect-MicrosoftTeams -Confirm:$false -ErrorAction SilentlyContinue
        $script:M365OpsTeamsConnected = $false
    }
}
