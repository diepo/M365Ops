function Test-M365OpsFixApplicable {
    <#
    .SYNOPSIS
        Vero solo se la correzione proposta da Invoke-M365OpsErrorTriage e' applicabile in
        sicurezza: file dentro la cartella del modulo, testo da sostituire presente ESATTAMENTE
        una volta.
    #>
    param($Triage, [string]$ModuleRoot)

    if (-not $Triage.fix -or -not $Triage.fix.file -or -not $Triage.fix.search -or -not $Triage.fix.replace) { return $false }

    $fullPath = Join-Path $ModuleRoot $Triage.fix.file
    if (-not (Test-Path $fullPath)) { return $false }

    $resolvedRoot = (Resolve-Path $ModuleRoot).Path.TrimEnd('\', '/')
    $resolvedFile = (Resolve-Path $fullPath).Path
    # Confronto per prefisso di CARTELLA (con separatore), non di stringa nuda: altrimenti
    # "C:\...\M365OpsEvil\x.ps1" supererebbe il controllo solo perche' inizia con lo stesso
    # testo di "C:\...\M365Ops" - un file fuori dal modulo con nome che condivide il prefisso.
    if (-not $resolvedFile.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $false }

    $content = Get-Content $fullPath -Raw
    $count = ([regex]::Matches($content, [regex]::Escape($Triage.fix.search))).Count
    return ($count -eq 1)
}
