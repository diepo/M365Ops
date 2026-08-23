function Complete-M365OpsIsolatedModuleConnect {
    <#
    .SYNOPSIS
        Logica condivisa da eseguire DOPO che il worker isolato ha risposto con successo al
        metodo "connect" (registra il processo come attivo per questo tenant, genera i proxy
        dinamici per ogni cmdlet esportato). Estratta il 23/08/2026 da Connect-M365OpsIsolatedModule
        (che la chiama per il percorso sincrono gia' esistente) per essere riusata TALE E QUALE
        dal nuovo percorso asincrono (Start-/Get-M365OpsIsolatedModuleConnectAsync*) - nessuna
        differenza di comportamento tra i due percorsi una volta che il worker ha risposto, la
        sola differenza e' COME si aspetta quella risposta (bloccante vs polling).
    .PARAMETER TenantName
        Nome del profilo tenant per cui registrare il worker connesso.
    .PARAMETER ModuleType
        'Exchange' o 'Teams'.
    .PARAMETER Process
        Il processo worker gia' avviato e gia' connesso con successo.
    .PARAMETER ConnectResult
        Il campo "result" della risposta JSON-RPC del worker al metodo "connect" (deserializzato).
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType,
        [Parameter(Mandatory)] $Process,
        [Parameter(Mandatory)] $ConnectResult
    )

    if (-not $script:M365OpsIsolatedWorkers) { $script:M365OpsIsolatedWorkers = @{} }
    if (-not $script:M365OpsIsolatedWorkers[$TenantName]) { $script:M365OpsIsolatedWorkers[$TenantName] = @{} }
    $script:M365OpsIsolatedWorkers[$TenantName][$ModuleType] = $Process

    # Bug reale trovato dal vivo il 23/08/2026, durante la verifica end-to-end del nuovo
    # percorso asincrono (Start-/Get-M365OpsIsolatedModuleConnectAsync*): senza questa riga,
    # una chiamata SUCCESSIVA a Connect-M365OpsTeams/Connect-M365OpsExchange (es. da
    # Get-M365OpsTeamsList, che la invoca sempre prima di leggere dati) trova ancora
    # $script:M365OpsTeamsConnected/$script:M365OpsExchangeConnected a $false (mai impostato da
    # questo percorso, solo dal corpo normale di quelle due funzioni) e prova a "connettersi"
    # di nuovo chiamando alla cieca Connect-MicrosoftTeams/Connect-ExchangeOnline per nome - ma
    # quel nome e' ormai una funzione PROXY globale (installata poche righe sotto, per QUALUNQUE
    # comando nuovo del modulo appena connesso, Connect-MicrosoftTeams compreso), quindi la
    # chiamata viene inoltrata al worker come un "invoke" qualsiasi invece di un vero connect.
    # Il worker esegue davvero un SECONDO Connect-MicrosoftTeams (ridondante, la sessione era
    # gia' attiva) e ne restituisce l'oggetto risultato (Account/Environment/Tenant/TenantId) via
    # ConvertTo-Json - che pero' fallisce con "Errore MCP: The type
    # '...Dictionary`2[[...AzureAccount+Property...],[...String...]]' is not supported for
    # serialization... Keys must be strings", perche' quell'oggetto contiene un Dictionary con
    # chiavi non-stringa che ConvertTo-Json non sa serializzare. Nel percorso sincrono/reattivo
    # esistente questo non capitava mai, perche' l'isolamento scatta SOLO dentro il catch di
    # Connect-M365OpsTeams/Connect-M365OpsExchange stesse, che impostano gia' il proprio flag
    # subito dopo (vedi quei file) - il nuovo percorso asincrono invece puo' rendere l'isolamento
    # attivo SENZA mai passare da quelle funzioni, lasciando il flag indietro. Fix: impostarlo
    # qui, punto unico raggiunto da ENTRAMBI i percorsi dopo un connect riuscito - innocuo se gia'
    # vero (il ramo sincrono lo re-imposta semplicemente allo stesso valore).
    if ($ModuleType -eq 'Teams') { $script:M365OpsTeamsConnected = $true } else { $script:M365OpsExchangeConnected = $true }

    # Bug reale trovato dal vivo il 26/08/2026: Connect-IPPSSession (Purview) nel worker
    # isolato falliva silenziosamente in ogni test - il worker lo logga su un proprio stderr
    # che nessuno leggeva mai in caso di "connect" andato a buon fine, quindi i cmdlet Purview
    # (es. Get-RetentionCompliancePolicy) risultavano assenti dall'elenco proxato senza nessuna
    # traccia visibile del perche'. Ora il worker restituisce l'esito esplicitamente nel
    # risultato di "connect" - va sempre loggato qui, non solo in caso di eccezione.
    if ($ModuleType -eq 'Exchange' -and $ConnectResult.PSObject.Properties.Name -contains 'purviewConnected' -and -not $ConnectResult.purviewConnected) {
        Write-M365OpsLog "Isolamento reattivo Exchange: connesso correttamente alle mailbox, ma Connect-IPPSSession (Purview/Compliance) e' fallito nel processo isolato - i cmdlet Purview (Get-RetentionCompliancePolicy e simili) non saranno disponibili per il tenant '$TenantName' finche' non risolto. Motivo: $($ConnectResult.purviewError)" -Level Warn
    }

    # Generazione dei proxy: evento UNA TANTUM per ModuleType per l'intera vita di QUESTO
    # processo server, non per tenant - vedi Connect-M365OpsIsolatedModule.ps1 per il
    # ragionamento completo, invariato qui.
    if (-not $script:M365OpsIsolatedProxiesInstalled) { $script:M365OpsIsolatedProxiesInstalled = @{} }
    if (-not $script:M365OpsIsolatedProxiesInstalled[$ModuleType]) {
        if (-not $script:M365OpsIsolatedCmdletModuleMap) { $script:M365OpsIsolatedCmdletModuleMap = @{} }
        if (-not $script:M365OpsIsolatedCmdletParams) { $script:M365OpsIsolatedCmdletParams = @{} }

        if (-not $script:M365OpsIsolatedProxyBody) {
            $script:M365OpsIsolatedProxyBody = {
                [CmdletBinding()]
                param()
                DynamicParam {
                    $cmdName = $MyInvocation.MyCommand.Name
                    $paramDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
                    foreach ($pName in $script:M365OpsIsolatedCmdletParams[$cmdName]) {
                        $attrs = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                        $attrs.Add((New-Object System.Management.Automation.ParameterAttribute))
                        $rp = New-Object System.Management.Automation.RuntimeDefinedParameter($pName, [object], $attrs)
                        $paramDictionary.Add($pName, $rp)
                    }
                    return $paramDictionary
                }
                process {
                    $cmdName = $MyInvocation.MyCommand.Name
                    $targetModule = $script:M365OpsIsolatedCmdletModuleMap[$cmdName]
                    Invoke-M365OpsIsolatedCmdlet -ModuleType $targetModule -Cmdlet $cmdName -Parameters $PSBoundParameters
                }
            }
        }

        # Bug reale trovato dal vivo il 23/08/2026 durante un test forzato di isolamento Teams
        # App-only su vnsys-test ("Index operation failed; the array index evaluated to null."):
        # quando il worker non trova NESSUN comando nuovo (commands = {} lato JSON), ConvertFrom-Json
        # su un oggetto JSON vuoto restituisce un PSCustomObject la cui collezione
        # PSObject.Properties.Name contiene UN elemento $null (non zero elementi come ci si
        # aspetterebbe) - quirk riprodotto in isolamento, non legato al tenant/timing. Senza
        # questo filtro, quel $null finiva come chiave di un hashtable ($h[$null] = ...), da cui
        # l'errore "array index evaluated to null". Where-Object { $_ } scarta sia questo caso
        # (nessun comando da proxare, esito legittimo anche se raro) sia qualunque altro nome
        # vuoto/nullo, senza toccare il caso normale (decine di nomi cmdlet reali, sempre truthy).
        $commandNames = @($ConnectResult.commands.PSObject.Properties.Name) | Where-Object { $_ }
        foreach ($cmdName in $commandNames) {
            $script:M365OpsIsolatedCmdletModuleMap[$cmdName] = $ModuleType
            $script:M365OpsIsolatedCmdletParams[$cmdName] = @($ConnectResult.commands.$cmdName)
            Set-Item -Path "function:global:$cmdName" -Value $script:M365OpsIsolatedProxyBody -Force
        }
        $script:M365OpsIsolatedProxiesInstalled[$ModuleType] = $true
        Write-M365OpsLog "Isolamento reattivo attivato per $ModuleType - $($commandNames.Count) cmdlet ora eseguiti in un processo separato per evitare il conflitto .NET di sezione 6.6."
        Write-Host "Isolamento reattivo attivato per $ModuleType ($($commandNames.Count) cmdlet proxati)." -ForegroundColor Yellow
    }
}
