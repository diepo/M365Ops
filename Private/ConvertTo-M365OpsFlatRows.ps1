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
            else {
                $flat[$prop.Name] = $value
            }
        }
        [pscustomobject]$flat
    }
}
