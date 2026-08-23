function Get-M365OpsIsolatedModuleConnectAsyncStatus {
    <#
    .SYNOPSIS
        Controllo NON BLOCCANTE (una sola lettura, mai un ciclo di attesa) dello stato di un
        login avviato con Start-M365OpsIsolatedModuleConnectAsync - pensata per essere chiamata
        ripetutamente dalla GUI (polling), stesso principio gia' in uso per il device-code
        Graph/Exchange. Vedi Start-M365OpsIsolatedModuleConnectAsync per il contesto completo
        del perche' esiste questo percorso asincrono.
    .PARAMETER ModuleType
        'Exchange' o 'Teams'.
    .OUTPUTS
        pscustomobject con Status:
        - 'Connected': gia' connesso (nessun login in corso, o appena completato con successo -
          i proxy sono gia' installati, i cmdlet Exchange/Teams funzionano gia').
        - 'Pending': login ancora in corso, richiama piu' tardi.
        - 'Error': login fallito (worker chiuso inaspettatamente, o timeout) - Message spiega
          il motivo. Lo stato pending viene ripulito, un nuovo tentativo puo' ripartire da capo.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType
    )

    if (-not $script:M365OpsContext) { throw "Nessun tenant attivo. Usa Connect-M365Ops prima." }
    $tenantName = $script:M365OpsContext.Name

    $existing = if ($script:M365OpsIsolatedWorkers -and $script:M365OpsIsolatedWorkers[$tenantName]) { $script:M365OpsIsolatedWorkers[$tenantName][$ModuleType] } else { $null }
    if ($existing -and -not $existing.HasExited) {
        return [pscustomobject]@{ Status = 'Connected' }
    }

    $pendingKey = "$tenantName|$ModuleType"
    $pending = if ($script:M365OpsIsolatedPendingConnects) { $script:M365OpsIsolatedPendingConnects[$pendingKey] } else { $null }
    if (-not $pending) {
        # Nessun login in corso e nessuna connessione attiva - stato pulito, non un errore:
        # il chiamante (Gui/Server.ps1) interpreta questo come "non ancora avviato nulla".
        return [pscustomobject]@{ Status = 'Error'; Message = "Nessun login in corso per $ModuleType su questo tenant." }
    }

    $process = $pending.Process
    if ($process.HasExited) {
        $script:M365OpsIsolatedPendingConnects.Remove($pendingKey)
        $err = try { $process.StandardError.ReadToEnd() } catch { '' }
        return [pscustomobject]@{ Status = 'Error'; Message = "Il processo isolato per $ModuleType si e' chiuso prima di completare il login (exit $($process.ExitCode)). $err" }
    }

    if (((Get-Date) - $pending.StartedAt).TotalSeconds -gt $pending.TimeoutSeconds) {
        $script:M365OpsIsolatedPendingConnects.Remove($pendingKey)
        if (-not $process.HasExited) { $process.Kill() }
        return [pscustomobject]@{ Status = 'Error'; Message = "Timeout: il login per $ModuleType non si e' completato entro $($pending.TimeoutSeconds) secondi." }
    }

    # Lettura NON bloccante: stesso identico controllo (EndOfStream + ReadLine) gia' collaudato
    # dal vivo nel percorso sincrono (Invoke-M365OpsMcpRequest), qui chiamato UNA VOLTA SOLA per
    # invocazione invece che dentro un ciclo con Start-Sleep - se non c'e' nulla di pronto si
    # esce subito con 'Pending', e sara' la PROSSIMA chiamata di polling (dal browser, qualche
    # secondo dopo) a ricontrollare, invece di restare qui ad aspettare.
    if ($process.StandardOutput.EndOfStream) {
        return [pscustomobject]@{ Status = 'Pending' }
    }

    $line = $process.StandardOutput.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line)) {
        return [pscustomobject]@{ Status = 'Pending' }
    }

    try { $parsed = $line | ConvertFrom-Json -ErrorAction Stop } catch {
        # Riga non-JSON (log/rumore) - ignorata, si resta in attesa della prossima.
        return [pscustomobject]@{ Status = 'Pending' }
    }
    if (-not ($parsed.PSObject.Properties.Name -contains 'id') -or $parsed.id -ne $pending.RequestId) {
        # Risposta a un'altra richiesta (non dovrebbe capitare su questo protocollo, un worker
        # gestisce una richiesta alla volta, ma il controllo costa nulla ed evita ambiguita').
        return [pscustomobject]@{ Status = 'Pending' }
    }

    $script:M365OpsIsolatedPendingConnects.Remove($pendingKey)

    if ($parsed.error) {
        return [pscustomobject]@{ Status = 'Error'; Message = "Connessione $ModuleType nel processo isolato fallita: $($parsed.error.message)" }
    }

    Complete-M365OpsIsolatedModuleConnect -TenantName $tenantName -ModuleType $ModuleType -Process $process -ConnectResult $parsed.result
    [pscustomobject]@{ Status = 'Connected' }
}
