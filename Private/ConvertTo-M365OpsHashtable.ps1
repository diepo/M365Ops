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

        BUG SERIO trovato dal vivo il 19/08/2026 durante uno stress test mirato: un array con
        ESATTAMENTE UN elemento (es. "groupTypes":["DynamicMembership"], comunissimo per campi
        Graph che sono sempre array ma spesso valorizzati con un solo elemento) veniva
        silenziosamente COLLASSATO a scalare nudo (la stringa "DynamicMembership" invece
        dell'array) - Graph rifiuta poi il corpo con un errore di tipo ("Error converting value
        to type System.String[]"), o peggio potrebbe accettarlo silenziosamente in modo diverso
        da quanto inteso per altri campi meno rigorosi. Causa: "return @($x | ForEach-Object
        {...})" nel ramo array sotto NON basta a preservare la forma array quando la pipeline
        emette un solo oggetto - PowerShell enumera l'array in uscita dalla funzione (comportamento
        standard per il flusso di output), e con un solo elemento il chiamante
        ("$h[$k] = ConvertTo-M365OpsHashtable ...") lo ricollassa a scalare in fase di
        assegnazione, esattamente come "$a = FunzioneCheRestituisceArrayVuoto" collassa a $null
        a 0 elementi (stesso identico meccanismo, stesso giorno, trovato anche nel bug "role
        mancante" di Invoke-M365OpsAgentTools). Verificato empiricamente: senza la virgola
        unaria, un array di 1 elemento esce come [string]; con "return ,@(...)" (la virgola
        forza l'emissione di UN solo oggetto pipeline - l'array stesso, mai enumerato) resta
        [object[]] con Count=1 in ogni caso, 0/1/N elementi inclusi - verificato per tutti e tre.
        Questa funzione e' usata su OGNI parametro proveniente da un tool AI prima di quasi ogni
        scrittura del modulo (propose_graph_write/propose_exo_write/propose_intune_write/
        propose_sharepoint_write/propose_teams_write/propose_custom_script_write/exo_query/
        custom_script_query) - il bug poteva quindi colpire silenziosamente qualunque campo ad
        un solo elemento in qualunque area, non solo groupTypes.
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
        return ,@($InputObject | ForEach-Object { ConvertTo-M365OpsHashtable $_ })
    }
    return $InputObject
}
