function Get-M365OpsCliMicrosoft365Versions {
    <#
    .SYNOPSIS
        Restituisce { Installed; Latest } per il pacchetto npm @pnp/cli-microsoft365 - la
        versione REALMENTE installata globalmente su questo PC e l'ultima pubblicata sul
        registro npm. Usata da Assert-M365OpsCliMicrosoft365Installed.ps1 (16/09/2026,
        richiesto esplicitamente dall'utente: "la nostra app e' pronta a verificare le nuove
        versioni del cli e aggiornarsi se serve? [...] si mettici un controllo") per decidere
        se un aggiornamento automatico serve.
    .NOTES
        Entrambe le versioni vengono lette tramite NPM stesso (mai tramite un comando della CLI
        come 'm365 version'/'m365 --version'): npm e' l'interfaccia STABILE con cui questo
        pacchetto e' stato installato, non soggetta alle stesse rinomine di comandi/opzioni che
        possono capitare da una major all'altra della CLI (v11.0, verificato dal vivo sulle note
        di rilascio ufficiali PnP, ha rinominato diversi comandi/opzioni - ma non tocca in alcun
        modo npm). Richiede una chiamata di RETE (npm view, contro il registro npm) - mai
        chiamata ad ogni connessione: il chiamante la limita a una volta al giorno (throttle
        separato, vedi Test-M365OpsCliMicrosoft365UpdateCheckDue.ps1).
    .OUTPUTS
        pscustomobject { Installed = <string o $null>; Latest = <string o $null> } - un valore
        $null (invece di un errore bloccante) se quella specifica lettura fallisce (es. rete
        assente per Latest, un errore di parsing per Installed) - il chiamante decide cosa fare
        con dati parziali, non deve mai bloccare l'uso della CLI gia' installata e funzionante.
    #>
    $npmCmd = (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue).Source
    if (-not $npmCmd) { $npmCmd = (Get-Command 'npm' -ErrorAction SilentlyContinue).Source }
    if (-not $npmCmd) { return [pscustomobject]@{ Installed = $null; Latest = $null } }

    # Stesso principio EAP 'Continue' locale di Invoke-M365OpsCliMicrosoft365NpmInstall.ps1:
    # npm scrive avvisi non fatali su stderr, che non devono mai essere promossi a eccezione
    # terminante sotto $ErrorActionPreference = 'Stop' del modulo.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $installedVersion = $null
    try {
        $listJson = & $npmCmd list -g "@pnp/cli-microsoft365" --depth=0 --json 2>&1 | Out-String
        $parsed = ConvertFrom-Json -InputObject $listJson -ErrorAction Stop
        $installedVersion = $parsed.dependencies.'@pnp/cli-microsoft365'.version
    } catch { }

    $latestVersion = $null
    try {
        $viewOutput = (& $npmCmd view "@pnp/cli-microsoft365" version 2>&1 | Out-String).Trim()
        # Un output multi-riga (es. un avviso npm stampato PRIMA del numero di versione, mai
        # osservato dal vivo ma non escludibile su ogni configurazione npm) invaliderebbe un
        # confronto diretto - tiene solo l'ultima riga non vuota, dove npm scrive sempre il
        # valore richiesto da 'npm view <pkg> version'.
        $lines = @($viewOutput -split "`r?`n" | Where-Object { $_.Trim() })
        if ($lines.Count -gt 0) { $latestVersion = $lines[-1].Trim() }
    } catch { }

    $ErrorActionPreference = $previousEap

    [pscustomobject]@{ Installed = $installedVersion; Latest = $latestVersion }
}
