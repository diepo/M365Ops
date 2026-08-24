function Get-M365OpsAiProviderLabel {
    <#
    .SYNOPSIS
        Etichetta leggibile del motore IA per un -Provider ('Claude' o 'AzureOpenAI') - usata
        per la nota "Elaborata da IA: ..." mostrata in fondo alle risposte in chat (24/08/2026,
        richiesto esplicitamente dall'utente). Estratta come funzione condivisa invece di
        ripetere la stessa mappa in Invoke-M365OpsAgentTools.ps1 (dove e' nata) e in
        Gui/Server.ps1 (dove serve per gli stessi motivi sui percorsi FUORI da quella funzione -
        catalogo comandi locali con RequiresAI=$true, triage/recovery errori via AI) - un solo
        posto da aggiornare se in futuro cambia il nome del modello o si aggiunge un provider.
    .PARAMETER Provider
        'Claude' o 'AzureOpenAI'.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Claude', 'AzureOpenAI')] [string]$Provider
    )
    if ($Provider -eq 'Claude') { 'Claude Sonnet 4.5 (Anthropic)' } else { 'Azure OpenAI' }
}
