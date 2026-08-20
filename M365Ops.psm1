# BUG STRUTTURALE trovato dal vivo il 20/08/2026 durante un test end-to-end su Accepted
# Domain: -ErrorAction Stop, aggiunto singolarmente a ~36 cmdlet di scrittura nel bug-hunt del
# 19/08/2026, NON protegge dal caso in cui il cmdlet nativo sottostante non e' disponibile del
# tutto nella sessione (es. ruolo RBAC mancante, come qui: New-AcceptedDomain "term not
# recognized" per lo stesso limite gia' diagnosticato su Receive/SendConnector) - un errore di
# risoluzione del NOME del comando ("term not recognized") e' una classe di errore diversa da
# un errore non terminante restituito DA un cmdlet realmente invocato: -ErrorAction e' un
# parametro comune che PowerShell applica solo DOPO aver risolto e legato il cmdlet, quindi su
# un comando irrisolvibile viene semplicemente ignorato, e l'esecuzione prosegue secondo
# l'$ErrorActionPreference del CHIAMANTE (default 'Continue') - verificato dal vivo:
# New-M365OpsAcceptedDomain ha stampato "Dominio accettato aggiunto" nonostante
# New-AcceptedDomain non fosse mai stato eseguito per davvero (nessun dominio creato,
# verificato con una lettura indipendente subito dopo).
# Impostare $ErrorActionPreference qui, a livello di SCOPE DEL MODULO (prima di qualunque
# dot-source), risolve entrambe le classi di errore in un colpo solo per OGNI funzione di
# Public\/Private\ (verificato empiricamente: le funzioni esportate da un modulo ereditano
# l'$ErrorActionPreference dello scope del modulo se non ne impostano uno proprio, incluso per
# un comando non risolvibile) - molto piu' robusto delle ~36 correzioni puntuali per-cmdlet gia'
# fatte, che restano comunque utili per il commento/contesto ma non erano piu' l'unica difesa
# necessaria. Un -ErrorAction SilentlyContinue/Continue esplicito su una chiamata specifica
# continua a vincere su questo default, come sempre in PowerShell - nessuna delle scelte
# deliberate di leggere-e-ignorare gia' presenti nel modulo (es.
# Get-MailboxFolderPermission -ErrorAction SilentlyContinue in Set-M365OpsCalendarPermission)
# viene toccata da questo cambio.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-ChildItem -Path (Join-Path $here 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
Get-ChildItem -Path (Join-Path $here 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }

# Script "home made" per casi d'uso concreti (es. report OneDrive/SharePoint) - dot-sourced qui,
# a livello di modulo, cosi' le funzioni sono richiamabili da Invoke-M365OpsAgentTools esattamente
# come le cmdlet di Public\. I file che iniziano con "_" sono esempi/template, mai caricati.
# Vedi Scripts\Custom\README.md per la convenzione richiesta (help PowerShell + tag Mode).
$script:M365OpsCustomScriptsPath = Join-Path $here 'Scripts\Custom'
Get-ChildItem -Path $script:M365OpsCustomScriptsPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '_*' } |
    ForEach-Object {
        try { . $_.FullName }
        catch { Write-Warning "Script personalizzato '$($_.Name)' non caricato (errore di sintassi): $($_.Exception.Message)" }
    }

$script:M365OpsModuleRoot = $here
$script:M365OpsContext = $null
$script:M365OpsTokenCache = @{}
$script:M365OpsAiCallCount = @{ Claude = 0; AzureOpenAI = 0 }
# "TenantName" riservato per la Knowledge Base GLOBALE (20/08/2026, richiesto esplicitamente
# dall'utente): Add-/Get-/Remove-M365OpsKnowledgeDocument* accettano gia' un -TenantName
# generico, usato SOLO per costruire un percorso sicuro (Config\KnowledgeBase-<nome>.json,
# Uploads\kb\<nome>\) - non serve alcuna nuova funzione di storage, basta un "tenant" fittizio e
# riservato per contenere documenti NON specifici di un cliente (es. la guida di configurazione
# dell'app stessa) e renderli visibili SEMPRE, a prescindere da quale tenant vero e' attivo.
# Prefisso "_" scelto apposta: i nomi profilo reali vengono da Config\tenants.json (scelti
# dall'operatore in GUI, es. "vnsys-test") e non iniziano mai per convenzione con underscore,
# quindi nessuna collisione possibile con un tenant vero. L'isolamento tra i KB dei singoli
# tenant (la garanzia di sicurezza gia' documentata in quelle funzioni) resta INTATTO: questo e'
# un bucket AGGIUNTIVO e separato, mai un modo di raggiungere il KB di un altro tenant vero.
$script:M365OpsGlobalKbName = '_global'

$publicNames = Get-ChildItem -Path (Join-Path $here 'Public') -Filter '*.ps1' | ForEach-Object { $_.BaseName }
$customNames = Get-ChildItem -Path $script:M365OpsCustomScriptsPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '_*' -and (Get-Command -Name $_.BaseName -CommandType Function -ErrorAction SilentlyContinue) } |
    ForEach-Object { $_.BaseName }
# Invoke-M365OpsGraphRequest e Get-M365OpsNormalizedChatText restano in Private/ (wrapper
# interni, non cmdlet documentate) ma vanno esportate esplicitamente: Gui\Server.ps1 le chiama
# direttamente (la prima per una scrittura Graph confermata su tenant Delegati, ramo
# 'LokkaWrite'; la seconda per normalizzare il testo prima del matching sul catalogo comandi,
# bug-hunt 19/08/2026) ed e' un consumer del modulo come qualsiasi altro - vede solo i membri
# esportati, mai le funzioni Private per nome, anche se il file e' dot-sourced dentro il modulo
# (bug reale: 'the term is not recognized', scoping, non un problema di rete/import mancante -
# trovato il 15/08/2026).
Export-ModuleMember -Function (@($publicNames) + @($customNames) + 'Invoke-M365OpsGraphRequest' + 'Get-M365OpsNormalizedChatText')
