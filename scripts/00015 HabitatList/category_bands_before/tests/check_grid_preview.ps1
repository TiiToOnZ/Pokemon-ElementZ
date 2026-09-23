# Check actual PNG alpha and painter order, independently of the headless stubs.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$frames = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '..\ui_previews\draw_commands.json') | ConvertFrom-Json
foreach ($frame in $frames.PSObject.Properties) {
    $owners = New-Object int[] (320 * 240)
    $markers = New-Object int[] (320 * 240)
    $sprites = @($frame.Value | Where-Object kind -eq 'sprite')
    $id = 0
    foreach ($sprite in $sprites) {
        $id++
        $bitmap = [Drawing.Bitmap]::new((Join-Path $project $sprite.asset))
        try {
            $minY = 52
            $maxY = 192
            if ($sprite.y -eq 32 -and $sprite.asset -match '(daytime|nighttime)\.png$') {
                $minY = 32
                $maxY = 50
            }
            if ($sprite.width -ne $bitmap.Width -or $sprite.height -ne $bitmap.Height) {
                throw "Rescaled sprite: $($frame.Name) $($sprite.asset)"
            }
            for ($y = 0; $y -lt $bitmap.Height; $y++) {
                for ($x = 0; $x -lt $bitmap.Width; $x++) {
                    if ($bitmap.GetPixel($x, $y).A -eq 0) { continue }
                    $dx = [int]$sprite.x + $x
                    $dy = [int]$sprite.y + $y
                    if ($dx -lt 8 -or $dx -ge 312 -or $dy -lt $minY -or $dy -ge $maxY) {
                        throw "Opaque pixel outside grid: $($frame.Name) $($sprite.asset)"
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
        } finally { $bitmap.Dispose() }
    }
    $visible = @($owners | Where-Object { $_ -gt 0 } | Group-Object | ForEach-Object { [int]$_.Name })
    for ($i = 1; $i -le $sprites.Count; $i++) {
        if ($i -notin $visible) { throw "Fully hidden sprite: $($frame.Name) $i" }
    }
    Write-Output "$($frame.Name): $($sprites.Count) sprites/badges visible, native size, within their reserved area."
}
