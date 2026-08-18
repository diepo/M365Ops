function ConvertTo-M365OpsHashtable {
    <#
    .SYNOPSIS
        Converte ricorsivamente un PSCustomObject (cosi' come arriva da ConvertFrom-Json, es. i
        parametri di una proposta di scrittura dell'AI) in una Hashtable vera con le stesse chiavi
        annidate, invariati tutti i valori scalari/array.
    .NOTES
        Bug reale trovato e corretto il 15/08/2026: un parametro tipizzato [hashtable] (es. -Body
        su Invoke-M365OpsGraphRequest, -ExtraParams su ~20 cmdlet Exchange di scrittura) rifiuta il
        binding di un PSCustomObject e fallisce con un errore di legatura argomenti invece di
        eseguire la richiesta - non e' deducibile guardando solo il chiamante, perche' la stessa
        chiamata funziona benissimo se il valore e' stato costruito a mano con @{...} nel codice
        del modulo. Usata su ogni parametro proveniente da un tool AI (exo_query, propose_exo_write,
        custom_script_query, propose_custom_script_write) prima di splattarlo su una cmdlet reale,
        cosi' il problema e' risolto una volta sola invece che in ogni singola cmdlet consumer.
    #>
    param($InputObject)

    if ($null -eq $InputObject) { return $InputObject }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-M365OpsHashtable $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-M365OpsHashtable $p.Value }
        return $h
    }
    if ($InputObject -isnot [string] -and $InputObject -is [System.Collections.IEnumerable]) {
        return @($InputObject | ForEach-Object { ConvertTo-M365OpsHashtable $_ })
    }
    return $InputObject
}
