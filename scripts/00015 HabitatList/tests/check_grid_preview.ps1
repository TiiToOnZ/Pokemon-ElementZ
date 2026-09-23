# Check rendered PNG alpha, scaling and painter order independently of the stubs.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$frames = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '..\ui_previews\draw_commands.json') | ConvertFrom-Json
foreach ($frame in $frames.PSObject.Properties) {
    $owners = New-Object int[] (320 * 240)
    $markers = New-Object int[] (320 * 240)
    $sprites = @($frame.Value | Where-Object kind -eq 'sprite')
    $bands = @($frame.Value | Where-Object kind -eq 'gradient')
    foreach ($band in $bands) {
        if ($band.x -ne 8 -or $band.width -ne 304 -or $band.height -ne 18 -or $band.y -lt 32 -or ($band.y + 18) -gt 192) {
            throw "Invalid band rectangle: $($frame.Name)"
        }
    }
    $id = 0
    foreach ($sprite in $sprites) {
        $id++
        $bitmap = [Drawing.Bitmap]::new((Join-Path $project $sprite.asset))
        $canvas = [Drawing.Bitmap]::new(320, 240)
        $graphics = [Drawing.Graphics]::FromImage($canvas)
        try {
            $scale = 1
            if ($sprite.asset -match '/pokefront/000\.png$') { $scale = 0.83 }
            if ($sprite.asset -match '/Catch\.png$') { $scale = 0.75 }
            if ([Math]::Abs($sprite.width - $bitmap.Width * $scale) -gt 0.001 -or [Math]::Abs($sprite.height - $bitmap.Height * $scale) -gt 0.001) {
                throw "Incorrect sprite scale: $($frame.Name) $($sprite.asset)"
            }
            $isTime = $sprite.asset -match '/(daytime|nighttime)\.png$'
            $minY = 32
            $maxY = 192
            if ($frame.Name -match '^(ensemble_|formes_et_inconnu)' -and !$isTime) { $minY = 52 }
            if ($isTime) {
                $matchingBands = @($bands | Where-Object { $_.y -eq $sprite.y })
                if ($matchingBands.Count -eq 0 -and $sprite.y -ne 32) { throw "Detached time icon: $($frame.Name)" }
                $minY = $sprite.y
                $maxY = $sprite.y + 18
            }
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
            $graphics.DrawImage($bitmap, [Drawing.RectangleF]::new($sprite.x, $sprite.y, $sprite.width, $sprite.height))
            $left = [Math]::Max(0, [Math]::Floor($sprite.x))
            $right = [Math]::Min(320, [Math]::Ceiling($sprite.x + $sprite.width))
            $top = [Math]::Max(0, [Math]::Floor($sprite.y))
            $bottom = [Math]::Min(240, [Math]::Ceiling($sprite.y + $sprite.height))
            for ($dy = $top; $dy -lt $bottom; $dy++) {
                for ($dx = $left; $dx -lt $right; $dx++) {
                    if ($canvas.GetPixel($dx, $dy).A -eq 0) { continue }
                    if ($dx -lt 8 -or $dx -ge 312 -or $dy -lt $minY -or $dy -ge $maxY) {
                        throw "Opaque pixel outside reserved area: $($frame.Name) $($sprite.asset)"
                    }
                    if (!$isTime) {
                        foreach ($band in $bands) {
                            if ($dy -ge $band.y -and $dy -lt ($band.y + $band.height)) {
                                throw "Pokemon/badge overlaps band: $($frame.Name) $($sprite.asset)"
                            }
                        }
                    }
                    if ($sprite.asset -match '/(Catch|daytime|nighttime)\.png$') {
                        if ($markers[$dy * 320 + $dx] -ne 0) {
                            throw "Overlapping indicator pixels: $($frame.Name)"
                        }
                        $markers[$dy * 320 + $dx] = $id
                    }
                    $owners[$dy * 320 + $dx] = $id
                }
            }
        } finally { $graphics.Dispose(); $canvas.Dispose(); $bitmap.Dispose() }
    }
    $visible = @($owners | Where-Object { $_ -gt 0 } | Group-Object | ForEach-Object { [int]$_.Name })
    for ($i = 1; $i -le $sprites.Count; $i++) {
        if ($i -notin $visible) { throw "Fully hidden sprite: $($frame.Name) $i" }
    }
    Write-Output "$($frame.Name): $($sprites.Count) sprites/badges visible; scales, bounds and bands OK."
}
