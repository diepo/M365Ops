function Get-M365OpsKnowledgeDocumentText {
    <#
    .SYNOPSIS
        Testo COMPLETO estratto di UN documento della Knowledge Base del tenant indicato -
        usalo solo quando il riassunto di Get-M365OpsKnowledgeCatalog non basta a rispondere.
    .PARAMETER TenantName
        Determina ESCLUSIVAMENTE in quale Knowledge Base cercare - stesso schema di isolamento
        di Get-M365OpsChatHistory/Get-M365OpsKnowledgeCatalog.
    .NOTES
        Sicurezza/isolamento: FileName viene verificato PRIMA contro il catalogo del tenant
        indicato (Get-M365OpsKnowledgeCatalog) - se non compare li', l'errore e' esplicito e il
        file NON viene letto. Questo impedisce sia un path traversal (es. "..\altro-tenant\x")
        sia, piu' in generale, che un documento di un altro tenant sia mai raggiungibile
        passando un FileName indovinato: il catalogo del tenant CORRENTE e' l'unica fonte
        attendibile di quali nomi file esistono per lui.
    #>
    param(
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [string]$FileName
    )

    $requestedName = Split-Path -Leaf $FileName
    $catalog = @(Get-M365OpsKnowledgeCatalog -TenantName $TenantName)
    $match = $catalog | Where-Object { $_.FileName -eq $requestedName } | Select-Object -First 1
    if (-not $match) {
        throw "Nessun documento '$requestedName' nella Knowledge Base di '$TenantName' - verifica il nome esatto con Get-M365OpsKnowledgeCatalog, mai indovinato."
    }

    $kbDir = (Get-M365OpsKnowledgeBasePaths -TenantName $TenantName).KbDir
    $textPath = Join-Path $kbDir "$requestedName.extracted.txt"
    if (-not (Test-Path $textPath)) {
        throw "Il documento '$requestedName' e' catalogato ma il testo estratto non e' piu' presente su disco - potrebbe non aver avuto testo estraibile al momento del caricamento."
    }
    Get-Content -Path $textPath -Raw
}
