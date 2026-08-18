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

$publicNames = Get-ChildItem -Path (Join-Path $here 'Public') -Filter '*.ps1' | ForEach-Object { $_.BaseName }
$customNames = Get-ChildItem -Path $script:M365OpsCustomScriptsPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '_*' -and (Get-Command -Name $_.BaseName -CommandType Function -ErrorAction SilentlyContinue) } |
    ForEach-Object { $_.BaseName }
# Invoke-M365OpsGraphRequest resta in Private/ (wrapper interno, non una cmdlet documentata)
# ma va esportata esplicitamente: Gui\Server.ps1 la chiama direttamente per eseguire una
# scrittura Graph confermata su tenant Delegati (ramo 'LokkaWrite'), ed e' un consumer del
# modulo come qualsiasi altro - vede solo i membri esportati, mai le funzioni Private per
# nome, anche se il file e' dot-sourced dentro il modulo (bug reale: 'the term is not
# recognized', scoping, non un problema di rete/import mancante - trovato il 15/08/2026).
Export-ModuleMember -Function (@($publicNames) + @($customNames) + 'Invoke-M365OpsGraphRequest')
