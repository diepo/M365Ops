function Get-M365OpsTeamDetail {
    <#
    .SYNOPSIS
        Restituisce l'oggetto Team COMPLETO (Get-Team, tutte le proprieta' native - criteri
        di collaborazione, visibilita', archiviazione, mail nickname, descrizione, ecc.) per
        UN team, non il sottoinsieme curato a mano di Get-M365OpsTeamsList (pensato per un
        elenco su piu' team, questa per il dettaglio completo di UNO).
    .PARAMETER GroupId
        Il GroupId del team (stesso identificativo di Get-M365OpsTeamsList/Get-M365OpsGroupOverview,
        non un nome - se non lo conosci gia', cercalo prima con quelle funzioni).
    #>
    param([Parameter(Mandatory)] [string]$GroupId)
    Connect-M365OpsTeams
    # Stesso pattern di isolamento reattivo di Get-M365OpsTeamsList/Get-M365OpsTeamsPolicies/
    # Get-M365OpsTeamsExternalAccessConfig (vedi quei file per il dettaglio completo del
    # conflitto .NET Teams/Exchange) - Connect-M365OpsTeams copre solo il proprio tentativo di
    # connessione, non un conflitto che scatta sulla chiamata diretta a Get-Team stessa.
    # Aggiunta l'11/09/2026, generalizzazione richiesta esplicitamente dall'utente (vedi
    # Get-M365OpsExchangeRecipientDetail per il contesto completo) estesa anche a Teams.
    $body = { Get-Team -GroupId $GroupId }
    try {
        & $body
    }
    catch {
        $hint = Get-M365OpsModuleConflictHint -RawMessage $_.Exception.Message -ThisService 'Microsoft Teams' -OtherService 'Exchange Online'
        if (-not $hint) { throw }
        Connect-M365OpsIsolatedModule -ModuleType 'Teams' -ConnectParams (Get-M365OpsIsolatedConnectParams -ModuleType 'Teams')
        & $body
    }
}
