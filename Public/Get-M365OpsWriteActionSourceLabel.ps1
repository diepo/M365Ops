function Get-M365OpsWriteActionSourceLabel {
    <#
    .SYNOPSIS
        Dato il 'Type' di una $script:PendingAction (vedi Execute-PendingAction in
        Gui\Server.ps1: ExoWrite, TeamsWrite, LokkaWrite, CliM365Write, ecc.), restituisce
        un'etichetta leggibile della sorgente reale - stesse etichette gia' usate da
        Get-M365OpsToolSourceLabel (Private) per coerenza, ma qui la chiave e' il TIPO di
        azione confermata dall'utente, non il nome del tool AI che l'ha proposta (dominio
        diverso: un'azione TeamsWrite puo' essere stata proposta da propose_teams_write, ma
        la sorgente dell'ESECUZIONE resta comunque "moduli PowerShell interni", identica in
        entrambi i casi).

        Aggiunta il 27/08/2026, richiesta esplicita dell'utente: mostrare la sorgente anche
        nella risposta POST-esecuzione (dopo aver confermato con "si"), non solo nella
        proposta iniziale - prima "Fonte dati: ..." appariva solo nel turno di proposta
        (aggiunto dall'AI in Invoke-M365OpsAgentTools.ps1), mai nel turno di esecuzione
        deterministica (Execute-PendingAction, che non passa mai dall'AI).
    .PARAMETER Type
        Il campo Type di $script:PendingAction.
    .PARAMETER IsDelegatedTenant
        Necessario SOLO per LokkaWrite: su un tenant Delegato quella scrittura non passa
        mai da Lokka (richiede client credentials) ma da una chiamata Graph diretta con lo
        stesso token delegato del resto del modulo - vedi il case 'LokkaWrite' in
        Execute-PendingAction, che gia' fa questa stessa distinzione per l'esecuzione vera.
    #>
    param(
        [Parameter(Mandatory)] [string]$Type,
        [bool]$IsDelegatedTenant = $false
    )

    switch ($Type) {
        'LokkaWrite' {
            if ($IsDelegatedTenant) { return 'Microsoft Graph diretto (token delegato, nessun MCP)' }
            return 'Lokka (MCP)'
        }
        'CliM365Write' { return 'CLI Microsoft 365 (MCP)' }
        'NewCustomScript' { return 'nuovo script personalizzato (salvato ora in Scripts\Custom)' }
        'CustomWrite' { return 'script personalizzato di questo tenant' }
        default { return 'moduli PowerShell interni di M365Ops' }
    }
}
