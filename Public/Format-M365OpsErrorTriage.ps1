function Format-M365OpsErrorTriage {
    <#
    .SYNOPSIS
        Formatta il risultato di Invoke-M365OpsErrorTriage in testo leggibile per la chat.
    #>
    param($Triage)
    $tag = switch ($Triage.classification) {
        'transient' { '[TRANSITORIO]' }
        'input' { '[SERVE UNA DECISIONE TUA]' }
        'bug' { '[POSSIBILE BUG]' }
        default { '[NON CLASSIFICATO]' }
    }
    $lines = @("$tag $($Triage.explanation)")

    if ($Triage.fix -and $Triage.fix.file -and $Triage.fix.search -and $Triage.fix.replace) {
        $lines += ""
        $lines += "Correzione proposta in $($Triage.fix.file):"
        $lines += "--- PRIMA ---"
        $lines += $Triage.fix.search
        $lines += "--- DOPO ---"
        $lines += $Triage.fix.replace
        $lines += ""
        $lines += "Rispondi 'si' per applicarla (con backup automatico), 'no' per lasciar perdere."
    }
    return ($lines -join "`n")
}
