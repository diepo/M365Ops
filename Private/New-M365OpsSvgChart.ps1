<#
    Generazione di grafici SVG auto-contenuti (nessuna libreria esterna, nessuna dipendenza
    da internet) per i report PDF - stessa filosofia gia' usata per l'export PDF (Edge
    headless locale, niente CDN/JS di terze parti da scaricare al momento della stampa).
#>

function New-M365OpsSvgChart {
    <#
    .SYNOPSIS
        Dispatcher: genera un grafico SVG a barre orizzontali o a torta da coppie
        etichetta/valore gia' aggregate (vedi Export-M365OpsDataReport per l'aggregazione).
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Labels,
        [Parameter(Mandatory)] [int[]]$Values,
        [ValidateSet('Bar', 'Pie')] [string]$Type = 'Bar'
    )
    if ($Type -eq 'Pie') {
        return New-M365OpsSvgPieChart -Labels $Labels -Values $Values
    }
    return New-M365OpsSvgBarChart -Labels $Labels -Values $Values
}

function New-M365OpsSvgBarChart {
    <#
    .SYNOPSIS
        Grafico a barre orizzontali - leggibile anche con molte categorie (a differenza di
        una torta, che diventa illeggibile oltre 6-7 fette).
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Labels,
        [Parameter(Mandatory)] [int[]]$Values
    )
    $max = if ($Values.Count -gt 0) { ($Values | Measure-Object -Maximum).Maximum } else { 1 }
    if ($max -le 0) { $max = 1 }

    $rowHeight = 26
    $labelWidth = 200
    $chartWidth = 380
    $width = $labelWidth + $chartWidth + 60
    $height = ($Values.Count * $rowHeight) + 10

    $bars = for ($i = 0; $i -lt $Values.Count; $i++) {
        $y = $i * $rowHeight + 4
        $barW = [math]::Max(1, [math]::Round(($Values[$i] / $max) * $chartWidth))
        $label = [System.Security.SecurityElement]::Escape([string]$Labels[$i])
        "<text x='0' y='$($y + 14)' font-size='12' fill='#16222E'>$label</text>" +
        "<rect x='$labelWidth' y='$y' width='$barW' height='18' fill='#14618F' rx='2'></rect>" +
        "<text x='$($labelWidth + $barW + 6)' y='$($y + 14)' font-size='12' fill='#16222E'>$($Values[$i])</text>"
    }

    "<svg viewBox='0 0 $width $height' xmlns='http://www.w3.org/2000/svg' style='width:100%; max-width:${width}px; font-family: Segoe UI, Arial, sans-serif;'>$($bars -join '')</svg>"
}

function New-M365OpsSvgPieChart {
    <#
    .SYNOPSIS
        Grafico a torta con legenda (etichetta, valore, percentuale) - adatto a poche
        categorie (es. distribuzione licenze per SKU, stato compliance).
    #>
    param(
        [Parameter(Mandatory)] [string[]]$Labels,
        [Parameter(Mandatory)] [int[]]$Values
    )
    $total = ($Values | Measure-Object -Sum).Sum
    if ($total -le 0) { $total = 1 }
    $colors = @('#14618F', '#257A47', '#9C6B0E', '#B23A32', '#6B4FA0', '#1F8A8C', '#8494A3', '#C0708A', '#4E7A2E', '#A05A2C')
    $cx = 120; $cy = 120; $r = 100
    $angleStart = 0.0
    $legendY = 10
    $parts = for ($i = 0; $i -lt $Values.Count; $i++) {
        $fraction = $Values[$i] / $total
        $angleEnd = $angleStart + ($fraction * 360)
        $largeArc = if (($angleEnd - $angleStart) -gt 180) { 1 } else { 0 }
        $x1 = $cx + $r * [math]::Cos([math]::PI * $angleStart / 180)
        $y1 = $cy + $r * [math]::Sin([math]::PI * $angleStart / 180)
        $x2 = $cx + $r * [math]::Cos([math]::PI * $angleEnd / 180)
        $y2 = $cy + $r * [math]::Sin([math]::PI * $angleEnd / 180)
        $color = $colors[$i % $colors.Count]

        $slice = if ($Values.Count -eq 1) {
            "<circle cx='$cx' cy='$cy' r='$r' fill='$color'></circle>"
        } else {
            "<path d='M $cx,$cy L $x1,$y1 A $r,$r 0 $largeArc,1 $x2,$y2 Z' fill='$color'></path>"
        }
        $label = [System.Security.SecurityElement]::Escape([string]$Labels[$i])
        $pct = [math]::Round($fraction * 100, 1)
        $legend = "<rect x='250' y='$legendY' width='12' height='12' fill='$color'></rect>" +
                  "<text x='266' y='$($legendY + 10)' font-size='11' fill='#16222E'>$label ($($Values[$i]), $pct%)</text>"
        $legendY += 18
        $angleStart = $angleEnd
        $slice + $legend
    }
    $height = [math]::Max(240, $legendY + 10)
    "<svg viewBox='0 0 480 $height' xmlns='http://www.w3.org/2000/svg' style='width:100%; max-width:480px; font-family: Segoe UI, Arial, sans-serif;'>$($parts -join '')</svg>"
}
