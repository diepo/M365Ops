<#
    Genera Assets\M365Ops.ico da zero (nessun asset esterno, nessun logo Microsoft
    riprodotto - un badge originale: quadrato arrotondato con gradiente blu/turchese e un
    ingranaggio bianco stilizzato, leggibile anche a 16x16). Script una tantum per
    rigenerare l'icona se mai serve cambiarla - non fa parte del flusso di avvio dell'app.

    Richiesto esplicitamente dall'utente il 22/08/2026: "disegna una icona bellina per il
    bat". Un .bat non puo' avere un'icona propria (limite di Windows) - questa .ico va
    assegnata a un collegamento (.lnk) che punta a M365Ops.bat, vedi New-M365OpsShortcut.ps1.
#>
Add-Type -AssemblyName System.Drawing

function New-M365OpsIconFrame {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Sfondo: quadrato arrotondato con gradiente blu profondo -> turchese
    $radius = [Math]::Max(2, [int]($Size * 0.22))
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($Size - 1), ($Size - 1))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc(($rect.Right - $d), $rect.Y, $d, $d, 270, 90)
    $path.AddArc(($rect.Right - $d), ($rect.Bottom - $d), $d, $d, 0, 90)
    $path.AddArc($rect.X, ($rect.Bottom - $d), $d, $d, 90, 90)
    $path.CloseFigure()

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 11, 61, 145),
        [System.Drawing.Color]::FromArgb(255, 18, 184, 176),
        45
    )
    $g.FillPath($brush, $path)

    # Ingranaggio bianco centrale: cerchio esterno coi denti + foro centrale (even-odd fill)
    $cx = $Size / 2.0
    $cy = $Size / 2.0
    $outerR = $Size * 0.32
    $innerR = $Size * 0.15
    $toothLen = $Size * 0.09
    $toothHalfWidth = $Size * 0.055
    $teeth = 8

    $gearPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gearPath.FillMode = [System.Drawing.Drawing2D.FillMode]::Winding
    $gearPath.AddEllipse([float]($cx - $outerR), [float]($cy - $outerR), [float]($outerR * 2), [float]($outerR * 2))

    for ($i = 0; $i -lt $teeth; $i++) {
        $angle = ($i * 360.0 / $teeth) * [Math]::PI / 180.0
        $tipR = $outerR + $toothLen
        $baseCx = $cx + [Math]::Cos($angle) * $outerR
        $baseCy = $cy + [Math]::Sin($angle) * $outerR
        $tipCx = $cx + [Math]::Cos($angle) * $tipR
        $tipCy = $cy + [Math]::Sin($angle) * $tipR
        $perpX = -[Math]::Sin($angle) * $toothHalfWidth
        $perpY = [Math]::Cos($angle) * $toothHalfWidth

        $pts = @(
            New-Object System.Drawing.PointF(($baseCx + $perpX), ($baseCy + $perpY))
            New-Object System.Drawing.PointF(($tipCx + $perpX), ($tipCy + $perpY))
            New-Object System.Drawing.PointF(($tipCx - $perpX), ($tipCy - $perpY))
            New-Object System.Drawing.PointF(($baseCx - $perpX), ($baseCy - $perpY))
        )
        $gearPath.AddPolygon($pts)
    }

    $holePath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $holePath.AddEllipse([float]($cx - $innerR), [float]($cy - $innerR), [float]($innerR * 2), [float]($innerR * 2))

    $region = New-Object System.Drawing.Region($gearPath)
    $region.Exclude($holePath)
    $g.FillRegion([System.Drawing.Brushes]::White, $region)

    $g.Dispose()
    return $bmp
}

$sizes = @(16, 32, 48, 64, 128, 256)
$frames = @{}
foreach ($s in $sizes) { $frames[$s] = New-M365OpsIconFrame -Size $s }

$pngBytesBySize = @{}
foreach ($s in $sizes) {
    $ms = New-Object System.IO.MemoryStream
    $frames[$s].Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytesBySize[$s] = $ms.ToArray()
    $ms.Dispose()
}

$outPath = Join-Path $PSScriptRoot '..\Assets\M365Ops.ico'
$outPath = [System.IO.Path]::GetFullPath($outPath)

$fs = New-Object System.IO.FileStream($outPath, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)

# ICONDIR
$bw.Write([UInt16]0)      # reserved
$bw.Write([UInt16]1)      # type = icon
$bw.Write([UInt16]$sizes.Count)

$headerSize = 6 + (16 * $sizes.Count)
$offset = $headerSize
foreach ($s in $sizes) {
    $bytes = $pngBytesBySize[$s]
    $wByte = if ($s -ge 256) { 0 } else { $s }
    $hByte = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$wByte)
    $bw.Write([byte]$hByte)
    $bw.Write([byte]0)        # color count (0 = no palette, true color)
    $bw.Write([byte]0)        # reserved
    $bw.Write([UInt16]1)      # color planes
    $bw.Write([UInt16]32)     # bits per pixel
    $bw.Write([UInt32]$bytes.Length)
    $bw.Write([UInt32]$offset)
    $offset += $bytes.Length
}
foreach ($s in $sizes) { $bw.Write($pngBytesBySize[$s]) }

$bw.Flush()
$bw.Close()
$fs.Close()

foreach ($s in $sizes) { $frames[$s].Dispose() }

Write-Host "Icona generata: $outPath"
