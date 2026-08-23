<#
    Worker isolato per un singolo modulo (ExchangeOnlineManagement o MicrosoftTeams), eseguito
    come sottoprocesso pwsh.exe SEPARATO dal processo server principale (26/08/2026, isolamento
    reattivo del conflitto .NET di sezione 6.6 - vedi Connect-M365OpsIsolatedModule.ps1 per
    l'architettura completa). NON e' una funzione del modulo M365Ops: gira in un processo che
    non lo importa affatto, solo il modulo Exchange O Teams (mai entrambi nello stesso processo,
    che e' l'intero scopo di questo file).

    Protocollo: JSON-RPC 2.0 su stdin/stdout, newline-delimited - stesso identico protocollo
    gia' usato per i server MCP (Private\Invoke-M365OpsMcpRequest.ps1) e per Lokka, riusato qui
    1:1 sul lato server invece che client. Due metodi:
    - "connect": autentica il modulo (AppOnly con certificato, o Delegato con AccessToken/
      device-code) e restituisce l'elenco dei comandi esportati dal modulo con i loro parametri
      (esclusi i parametri comuni di PowerShell) - il PROCESSO CHIAMANTE (parent) usa questo
      elenco per generare le funzioni proxy dinamicamente, senza bisogno di mantenere a mano un
      elenco di comandi (vedi Connect-M365OpsIsolatedModule.ps1).
    - "invoke": esegue UN cmdlet reale con i parametri forniti, restituisce il risultato
      serializzato in JSON (ConvertTo-Json -Depth 6) - la fedelta' di tipo va persa
      (oggetti reali come MailboxObject diventano PSCustomObject generici), accettabile per
      questo progetto perche' nessun call site usa i tipi reali per altro che leggere proprieta'
      o passare a ConvertTo-Json/report (verificato: nessun uso di metodi .NET sui risultati).
#>
param(
    [Parameter(Mandatory)] [ValidateSet('Exchange', 'Teams')] [string]$ModuleType
)

$ErrorActionPreference = 'Stop'
$script:M365OpsWorkerRequestModule = $ModuleType

function Send-M365OpsWorkerResponse {
    param($Id, $Result, $ErrorMessage)
    if ($ErrorMessage) {
        $payload = [ordered]@{ jsonrpc = "2.0"; id = $Id; error = @{ message = $ErrorMessage } }
    } else {
        $payload = [ordered]@{ jsonrpc = "2.0"; id = $Id; result = $Result }
    }
    $json = $payload | ConvertTo-Json -Depth 12 -Compress
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

# Parametri comuni di PowerShell (CmdletBinding li aggiunge sempre da soli) - esclusi
# dall'elenco dei parametri riportato al chiamante, altrimenti il generatore di proxy dinamici
# lato parent proverebbe a ridichiararli, andando in collisione con quelli gia' automatici
# (verificato dal vivo: "A parameter with the name 'ErrorAction' was defined multiple times").
$script:CommonParamNames = @(
    'ErrorAction','WarningAction','Verbose','Debug','ErrorVariable','WarningVariable',
    'OutVariable','OutBuffer','PipelineVariable','InformationAction','InformationVariable',
    'Confirm','WhatIf','ProgressAction'
)

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    try { $req = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }

    try {
        switch ($req.method) {
            "connect" {
                # Elenco comandi PRIMA di importare/connettersi - baseline per il diff sotto.
                # BUG REALE trovato dal vivo il 26/08/2026 (riproduzione end-to-end, non teoria):
                # filtrare per -Module ExchangeOnlineManagement DOPO il connect trovava solo 32
                # comandi invece degli oltre 130 attesi (Get-Mailbox, Get-DistributionGroup,
                # Get-RetentionCompliancePolicy compresi, TUTTI mancanti) - Connect-ExchangeOnline
                # inietta la stragrande maggioranza dei comandi tramite implicit remoting in un
                # modulo temporaneo con un nome GENERATO A CASO (stesso meccanismo di
                # Import-PSSession), mai letteralmente "ExchangeOnlineManagement" - un filtro per
                # nome di modulo quindi li manca quasi tutti per costruzione, non per un problema
                # di tempistica (il tentativo con un'attesa di stabilizzazione, primo fix provato,
                # non aveva infatti cambiato nulla: il conteggio restava fisso a 32). Il fix vero
                # e' un diff prima/dopo sui NOMI dei comandi disponibili nella sessione, che
                # cattura tutto cio' che il connect ha reso disponibile a prescindere da quale
                # modulo (reale o temporaneo generato) lo ospiti.
                $commandsBefore = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-Command -CommandType Function, Cmdlet).Name), [System.StringComparer]::OrdinalIgnoreCase)

                if ($ModuleType -eq 'Exchange') {
                    Import-Module ExchangeOnlineManagement -ErrorAction Stop
                    if ($req.params.AccessToken) {
                        # Delegato via token gia' ottenuto altrove - non usato dai chiamanti
                        # attuali (che per il ramo Delegato passano UserPrincipalName da solo,
                        # vedi sotto), tenuto per compatibilita' futura.
                        Connect-ExchangeOnline -AccessToken $req.params.AccessToken -UserPrincipalName $req.params.UserPrincipalName -ShowBanner:$false -ErrorAction Stop | Out-Null
                    } elseif ($req.params.UserPrincipalName) {
                        # Delegato via popup interattivo (27/08/2026, richiesto con massima
                        # priorita' dal vivo: conflitto reale Teams+Exchange poi Purview su un
                        # tenant Delegato) - vedi Get-M365OpsIsolatedConnectParams.ps1 .NOTES per
                        # il perche' NON e' -Device: qui stdout e' il canale del protocollo
                        # JSON-RPC stesso, un codice dispositivo stampato come testo li' non
                        # sarebbe mai visto da nessuno e la richiesta resterebbe bloccata fino al
                        # timeout. Il popup browser/WAM invece e' una finestra GUI separata, non
                        # tocca stdout - stesso principio gia' verificato dal vivo funzionante
                        # per Teams delegato (Connect-M365OpsTeams.ps1) e per Purview delegato
                        # standalone (Connect-M365OpsCompliance.ps1).
                        Connect-ExchangeOnline -UserPrincipalName $req.params.UserPrincipalName -ShowBanner:$false -ErrorAction Stop | Out-Null
                        $script:PurviewConnected = $false
                        $script:PurviewError = $null
                        try {
                            $ippsParams = @{ UserPrincipalName = $req.params.UserPrincipalName; ErrorAction = 'Stop' }
                            if ((Get-Command Connect-IPPSSession).Parameters.Keys -contains 'ShowBanner') { $ippsParams.ShowBanner = $false }
                            # Niente -Device qui neanche per Purview, stesso motivo di sopra -
                            # il popup e' l'unico percorso sicuro in questo processo.
                            Connect-IPPSSession @ippsParams | Out-Null
                            $script:PurviewConnected = $true
                        } catch {
                            $script:PurviewError = $_.Exception.Message
                            [Console]::Error.WriteLine("Connect-IPPSSession (Purview) fallito nel worker isolato (delegato), non bloccante: $($_.Exception.Message)")
                        }
                    } else {
                        # App-only: stesso certificato usato sia per Connect-ExchangeOnline
                        # (mailbox) sia per Connect-IPPSSession (Purview) - un SOLO worker
                        # serve entrambe le famiglie di cmdlet (l'inventario del 26/08/2026 le
                        # conta insieme, entrambe esposte dallo stesso modulo
                        # ExchangeOnlineManagement), non serve un secondo processo dedicato
                        # solo a Purview. Purview e' best-effort: se il tenant non ha il
                        # permesso/ruolo Compliance, questo secondo Connect fallisce ma non
                        # deve bloccare l'uso dei cmdlet mailbox, gia' connessi con successo.
                        Connect-ExchangeOnline -AppId $req.params.AppId -CertificateThumbprint $req.params.CertificateThumbprint -Organization $req.params.Organization -ShowBanner:$false -ErrorAction Stop | Out-Null
                        $script:PurviewConnected = $false
                        $script:PurviewError = $null
                        try {
                            Connect-IPPSSession -AppId $req.params.AppId -CertificateThumbprint $req.params.CertificateThumbprint -Organization $req.params.Organization -ShowBanner:$false -ErrorAction Stop | Out-Null
                            $script:PurviewConnected = $true
                            # LIMITE REALE, non un bug dell'isolamento (verificato dal vivo il
                            # 26/08/2026 con uno script minimale, FUORI da questa architettura,
                            # solo Import-Module+Connect-ExchangeOnline+Connect-IPPSSession puri
                            # sul tenant vnsys-test): Connect-IPPSSession qui non lancia MAI
                            # un'eccezione e ritorna "riuscito", ma Get-PSSession subito dopo
                            # mostra ZERO sessioni remote attive - la sessione di implicit
                            # remoting classica (quella da cui derivano cmdlet come
                            # Get-RetentionCompliancePolicy) non viene proprio stabilita, per
                            # motivi indipendenti da questo worker (verosimilmente permessi
                            # Compliance/eDiscovery mancanti sull'App Registration per QUESTO
                            # tenant, o un comportamento di ExchangeOnlineManagement 3.4.0 con
                            # auth a solo certificato). Risultato pratico: $commands sotto non
                            # includera' MAI i classici cmdlet Purview per questo tenant, anche
                            # se purviewConnected e' true - non risolvibile allungando l'attesa
                            # di stabilizzazione (gia' provato dal vivo, nessun effetto).
                        } catch {
                            # Non bloccante di proposito (vedi sopra) - ma il fallimento va
                            # comunque restituito al chiamante (26/08/2026, bug reale trovato dal
                            # vivo: prima veniva loggato SOLO su stderr del worker, che nessun
                            # chiamante legge mai in caso di successo del "connect" - il fallimento
                            # spariva nel nulla, lasciando Get-RetentionCompliancePolicy e gli altri
                            # cmdlet Purview silenziosamente assenti dall'elenco proxato, senza
                            # nessuna traccia visibile del perche').
                            $script:PurviewError = $_.Exception.Message
                            [Console]::Error.WriteLine("Connect-IPPSSession (Purview) fallito nel worker isolato, non bloccante: $($_.Exception.Message)")
                        }
                    }
                    $moduleName = 'ExchangeOnlineManagement'
                } else {
                    Import-Module MicrosoftTeams -ErrorAction Stop
                    $connectParams = @{ ErrorAction = 'Stop' }
                    if ($req.params.CertificateThumbprint) {
                        $connectParams.ApplicationId = $req.params.AppId
                        $connectParams.Certificate = $req.params.CertificateThumbprint
                        $connectParams.TenantId = $req.params.TenantId
                    } else {
                        $connectParams.TenantId = $req.params.TenantId
                    }
                    if ($req.params.DisableWAM -and (Get-Command Connect-MicrosoftTeams).Parameters.Keys -contains 'DisableWAM') {
                        $connectParams.DisableWAM = $true
                    }
                    Connect-MicrosoftTeams @connectParams | Out-Null
                    $moduleName = 'MicrosoftTeams'
                }

                # Elenco comandi + parametri (esclusi quelli comuni) NUOVI da quando il worker
                # e' partito - mai una lista mantenuta a mano, e mai un filtro per nome di
                # modulo (vedi commento sopra $commandsBefore per il perche'): qualunque
                # comando il connect abbia reso disponibile, ovunque viva, risulta
                # automaticamente proxabile, senza dover aggiornare questo worker.
                #
                # Attesa di stabilizzazione a POLLING (26/08/2026, non piu' un singolo
                # Start-Sleep fisso di 2s) - bug reale trovato dal vivo: con soli 2s fissi,
                # Get-RetentionCompliancePolicy e gli altri cmdlet iniettati dalla sessione di
                # Connect-IPPSSession (Purview, stabilita DOPO quella di Connect-ExchangeOnline,
                # quindi ha meno tempo per completare l'iniezione implicita entro lo stesso
                # termine fisso) restavano sistematicamente assenti dall'elenco finale anche
                # quando Connect-IPPSSession non aveva lanciato nessuna eccezione - non un
                # problema di permessi/ruolo (la connessione riusciva), solo di tempistica.
                # Qui si attende finche' il CONTEGGIO TOTALE dei comandi smette di crescere per
                # due controlli consecutivi (stabile per almeno 1s), con un tetto massimo di
                # attesa per non restare bloccati all'infinito se qualcosa non si stabilizza mai.
                $stableCount = 0
                $lastCount = -1
                $maxWait = [System.Diagnostics.Stopwatch]::StartNew()
                while ($stableCount -lt 2 -and $maxWait.Elapsed.TotalSeconds -lt 15) {
                    Start-Sleep -Milliseconds 500
                    $currentCount = (Get-Command -CommandType Function, Cmdlet).Count
                    if ($currentCount -eq $lastCount) { $stableCount++ } else { $stableCount = 0 }
                    $lastCount = $currentCount
                }

                $commands = @{}
                foreach ($cmd in (Get-Command -CommandType Function, Cmdlet)) {
                    if ($commandsBefore.Contains($cmd.Name)) { continue }
                    $paramNames = @($cmd.Parameters.Keys | Where-Object { $_ -notin $script:CommonParamNames })
                    $commands[$cmd.Name] = $paramNames
                }
                $resultPayload = @{ connected = $true; commands = $commands }
                if ($ModuleType -eq 'Exchange') {
                    $resultPayload.purviewConnected = $script:PurviewConnected
                    $resultPayload.purviewError = $script:PurviewError
                }
                Send-M365OpsWorkerResponse -Id $req.id -Result $resultPayload
            }
            "invoke" {
                $cmdName = $req.params.cmdlet
                $cmdParams = @{}
                if ($req.params.parameters) {
                    $req.params.parameters.PSObject.Properties | ForEach-Object {
                        # I valori arrivano come stringhe/numeri/bool/array/oggetto dal JSON -
                        # PowerShell li converte gia' correttamente per la maggior parte dei
                        # parametri (stringhe/numeri/bool) tramite il normale binding; oggetti
                        # annidati (raro in questo progetto - i chiamanti passano quasi sempre
                        # scalari o array di stringhe) restano PSCustomObject, sufficiente per
                        # i pochi cmdlet che li accettano come bag di proprieta'.
                        $cmdParams[$_.Name] = $_.Value
                    }
                }
                $result = & $cmdName @cmdParams
                # -Compress omesso apposta (a differenza di altrove in questo progetto): i
                # risultati di questi cmdlet possono avere proprieta' con caratteri che
                # Compress su alcune build gestisce comunque bene, ma la leggibilita' nei log
                # di debug (se mai serve un dump manuale) vale il trascurabile overhead qui,
                # non e' un payload HTTP con un limite pratico come altrove.
                $resultJson = ConvertTo-Json -InputObject $result -Depth 6 -Compress -ErrorAction SilentlyContinue
                if ($null -eq $resultJson) { $resultJson = '[]' }
                Send-M365OpsWorkerResponse -Id $req.id -Result $resultJson
            }
            default {
                Send-M365OpsWorkerResponse -Id $req.id -ErrorMessage "Metodo sconosciuto: $($req.method)"
            }
        }
    }
    catch {
        Send-M365OpsWorkerResponse -Id $req.id -ErrorMessage $_.Exception.Message
    }
}
