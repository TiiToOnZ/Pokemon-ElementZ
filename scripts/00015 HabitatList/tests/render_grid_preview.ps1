# Static layout review, not a LiteRGSS screenshot. No game data is written.
param([switch]$PrepareBounds)
Add-Type -AssemblyName System.Drawing
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$output = Join-Path $PSScriptRoot '..\ui_previews'
if ($PrepareBounds) {
    # Measure actual alpha, without editing any source image.
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System.Drawing;
public static class HabitatBounds {
    public static int[] Read(string path) {
        using (Bitmap bitmap = new Bitmap(path)) {
            int left=bitmap.Width, top=bitmap.Height, right=-1, bottom=-1;
            for (int y=0; y<bitmap.Height; y++) for (int x=0; x<bitmap.Width; x++) {
                if (bitmap.GetPixel(x,y).A == 0) continue;
                if (x<left) left=x;
                if (y<top) top=y;
                if (x>right) right=x;
                if (y>bottom) bottom=y;
            }
            return right<0 ? new int[] {0,0,1,1} : new int[] {left,top,right-left+1,bottom-top+1};
        }
    }
}
'@
    $bounds = @{}
    Get-ChildItem -LiteralPath (Join-Path $project 'graphics\pokedex\pokefront') -Filter '*.png' -File | ForEach-Object {
        $bounds[$_.BaseName] = [HabitatBounds]::Read($_.FullName)
    }
    $bounds | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $output 'front_bounds.json') -Encoding UTF8
    Write-Output 'PNG alpha bounds measured from project assets.'
    return
}
$frames = Get-Content -LiteralPath (Join-Path $output 'draw_commands.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fontCollection = New-Object System.Drawing.Text.PrivateFontCollection
$fontCollection.AddFontFile((Join-Path $project 'Fonts\PokemonDS.ttf'))
$fontCollection.AddFontFile((Join-Path $project 'Fonts\PowerGreenSmall.ttf'))
$fontFamily = $fontCollection.Families | Where-Object { $_.Name -like '*Pokemon*' } | Select-Object -First 1
$smallFamily = $fontCollection.Families | Where-Object { $_.Name -like '*Power*' } | Select-Object -First 1
$font = [Drawing.Font]::new($fontFamily, 13, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$smallFont = [Drawing.Font]::new($smallFamily, 11, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$background = [Drawing.Image]::FromFile((Join-Path $project 'graphics\interface\team\fond.png'))
$bar = [Drawing.Image]::FromFile((Join-Path $project 'graphics\interface\tcard\button_background.png'))
$button = [Drawing.Image]::FromFile((Join-Path $project 'graphics\pokedex\buttons.png'))
foreach ($frame in $frames.PSObject.Properties) {
    $canvas = [Drawing.Bitmap]::new(320, 240)
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    $graphics.DrawImageUnscaled($background, 0, 0)
    foreach ($command in $frame.Value) {
        $rect = [Drawing.RectangleF]::new($command.x, $command.y, $command.width, $command.height)
        if ($command.kind -eq 'gradient') {
            for ($column = 0; $column -lt $command.width; $column++) {
                $rgba = $command.columns[$column]
                $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb($rgba[3], $rgba[0], $rgba[1], $rgba[2]))
                $graphics.FillRectangle($brush, [single]($command.x + $column), [single]$command.y, [single]1, [single]$command.height)
                $brush.Dispose()
            }
        } elseif ($command.kind -eq 'sprite') {
            $source = [Drawing.Image]::FromFile((Join-Path $project $command.asset))
            $graphics.DrawImage($source, $rect)
            $source.Dispose()
        } else {
            $format = [Drawing.StringFormat]::GenericTypographic.Clone()
            $format.Alignment = [Drawing.StringAlignment][int]$command.align
            $format.LineAlignment = [Drawing.StringAlignment]::Center
            $format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
            $textFont = $font
            if ($command.font_id -eq 20) { $textFont = $smallFont }
            $graphics.DrawString($command.text, $textFont, [Drawing.Brushes]::Black, $rect, $format)
            $format.Dispose()
        }
    }
    $graphics.DrawImageUnscaled($bar, 0, 214)
    $labels = @('Suivant', ('Pr' + [char]233 + 'c' + [char]233 + 'dent'), 'Ensemble', 'Retour')
    $keys = @('A', 'X', 'Y', 'B')
    for ($i = 0; $i -lt 4; $i++) {
        $x = 3 + $i * 80
        $sx = 0
        if ($i -eq 3) { $sx = [int]($button.Width / 2) + 1 }
        $rect = [Drawing.Rectangle]::new($x, 219, 74, 19)
        $graphics.DrawImage($button, $rect, $sx, 0, 74, 19, [Drawing.GraphicsUnit]::Pixel)
        # Logical input symbols are shown here; the game renders mapped key art.
        $graphics.DrawString($keys[$i], $smallFont, [Drawing.Brushes]::Black, [single]$x, [single]220)
        $graphics.DrawString($labels[$i], $smallFont, [Drawing.Brushes]::Black, [single]($x + 17), [single]222)
    }
    $canvas.Save((Join-Path $output ($frame.Name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $canvas.Dispose()
}
$background.Dispose()
$bar.Dispose()
$button.Dispose()
$font.Dispose()
$smallFont.Dispose()
$fontCollection.Dispose()
Write-Output '320x240 static previews rendered with project assets and fonts.'
