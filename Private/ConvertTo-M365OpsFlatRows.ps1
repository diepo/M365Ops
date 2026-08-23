function ConvertTo-M365OpsFlatRows {
    <#
    .SYNOPSIS
        Appiattisce le proprieta' con valore ARRAY di ogni riga in una stringa leggibile (unita
        con ", ") prima di scriverla in Excel/PDF - senza questo, ImportExcel e ConvertTo-Html
        si limitano a chiamare .ToString() su un array .NET, che produce il nome del tipo
        (es. "System.Object[]") invece del contenuto reale. Bug reale segnalato dal vivo il
        18/08/2026 su un report gruppi di distribuzione, colonna ManagedBy (proprieta'
        multi-valore di Exchange). I valori scalari (stringhe, numeri, date, booleani, $null)
        passano invariati.
    #>
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Rows)

    $Rows | ForEach-Object {
        $row = $_
        $flat = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $value = $prop.Value
            if ($null -eq $value -or $value -is [string]) {
                $flat[$prop.Name] = $value
            }
            elseif ($value -is [System.Collections.IEnumerable]) {
                $items = @($value | ForEach-Object { [string]$_ } | Where-Object { $_ })
                $flat[$prop.Name] = if ($items.Count -gt 0) { $items -join ", " } else { $null }
            }
            elseif ($value.GetType().IsPrimitive -or $value -is [decimal] -or $value -is [datetime] -or $value -is [guid] -or $value -is [System.Enum]) {
                # Tipi scalari "veri" (int/bool/double/decimal/datetime/guid/enum) - Excel e il
                # PDF li rendono gia' correttamente da soli, nessun appiattimento necessario.
                $flat[$prop.Name] = $value
            }
            else {
                # Oggetto complesso SINGOLO, non un array (23/08/2026, bug reale trovato dal
                # vivo, bug-hunt di 16 ore - stesso principio del fix sugli array sopra, ma
                # mai applicato a un oggetto nidificato non-enumerabile, es. signInActivity/
                # assignedPlan/manager di Graph). Prima di questo fix, questo ramo lasciava il
                # valore invariato: Excel (ImportExcel/EPPlus) scriveva una cella VUOTA, mentre
                # il PDF (ConvertTo-Html) stampava il dump grezzo "@{X=1; Y=2}" - due formati
                # dello STESSO report con contenuti diversi per la stessa colonna. In piu',
                # lasciare passare l'oggetto grezzo faceva anche fallire Group-Object nella
                # costruzione dei grafici PDF (Export-M365OpsDataReport.ps1, "Cannot compare...
                # because the object does not implement IComparable", riprodotto dal vivo) -
                # appiattendo qui, alla fonte, quel crash non si presenta nemmeno piu' (oltre
                # al try/catch di sicurezza gia' aggiunto li').
                $pairs = @()
                if ($value -is [System.Collections.IDictionary]) {
                    foreach ($k in $value.Keys) { $pairs += "$k=$($value[$k])" }
                } else {
                    foreach ($p in $value.PSObject.Properties) { $pairs += "$($p.Name)=$($p.Value)" }
                }
                $flat[$prop.Name] = if ($pairs.Count -gt 0) { $pairs -join "; " } else { $null }
            }
        }
        [pscustomobject]$flat
    }
}
