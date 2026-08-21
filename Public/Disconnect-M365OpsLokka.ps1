function Disconnect-M365OpsLokka {
    <#
    .SYNOPSIS
        Ferma il sottoprocesso Lokka, se attivo.

        Alias sottile su Disconnect-M365OpsMcpServer -Name 'lokka' (26/08/2026) - vedi
        Connect-M365OpsMcpServer.ps1 per il perche'.
    #>
    Disconnect-M365OpsMcpServer -Name 'lokka'
}
