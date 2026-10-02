# Rebuild the icon from the exact vector contours supplied by the designer.
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'assets'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
[xml]$svg=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'assets/brand-mark.svg'))
$paths=@($svg.DocumentElement.ChildNodes | Where-Object LocalName -eq 'path')
if ($paths.Count -ne 2) { throw 'The brand mark must contain both original contours.' }
$main=[Windows.Media.Geometry]::Parse($paths[0].GetAttribute('d'))
$dot=[Windows.Media.Geometry]::Parse($paths[1].GetAttribute('d'))
$bounds=$main.Bounds; $bounds.Union($dot.Bounds)
$scale=300/[Math]::Max($bounds.Width,$bounds.Height)
$matrix=[Windows.Media.Matrix]::new($scale,0,0,$scale,256-($bounds.X+$bounds.Width/2)*$scale,256-($bounds.Y+$bounds.Height/2)*$scale)
function Brush([string]$a,[string]$b) {
    return [Windows.Media.LinearGradientBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($a),[Windows.Media.ColorConverter]::ConvertFromString($b),45)
}
function Render-Brand([int]$size,[bool]$Icon) {
    $visual=New-Object Windows.Media.DrawingVisual
    $dc=$visual.RenderOpen()
    $dc.PushTransform([Windows.Media.ScaleTransform]::new($size/512,$size/512))
    if ($Icon) {
        $tile=[Windows.Rect]::new(16,16,480,480)
        $dc.DrawRoundedRectangle((Brush '#8574BE' '#332A55'),$null,$tile,110,110)
        $light=New-Object Windows.Media.RadialGradientBrush
        $light.Center='0.23,0.05'; $light.GradientOrigin=$light.Center; $light.RadiusX=1; $light.RadiusY=0.9
        $light.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString('#55D5C3FF'),0))
        $light.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Colors]::Transparent,1))
        $dc.DrawRoundedRectangle($light,[Windows.Media.Pen]::new((Brush '#C8DBCCF8' '#40594A78'),2),$tile,110,110)
        $dc.PushTransform([Windows.Media.MatrixTransform]::new($matrix))
        # A short shadow beneath the symbol adds depth without blurring its white face.
        $dc.PushTransform([Windows.Media.TranslateTransform]::new(0,7/$scale))
        $shade=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString('#33221A3A'))
        $dc.DrawGeometry($shade,$null,$main); $dc.DrawGeometry($shade,$null,$dot); $dc.Pop()
        $dc.DrawGeometry((Brush '#FFFFFF' '#E7E0F6'),$null,$main)
        $dc.DrawGeometry((Brush '#C4D7B5' '#8DA87E'),$null,$dot)
        $dc.Pop()
    } else {
        $dc.DrawRectangle([Windows.Media.Brushes]::Black,$null,[Windows.Rect]::new(0,0,512,512))
        $dc.PushTransform([Windows.Media.ScaleTransform]::new(0.25,0.25))
        $dc.DrawGeometry([Windows.Media.Brushes]::White,$null,$main); $dc.DrawGeometry([Windows.Media.Brushes]::White,$null,$dot)
        $dc.Pop()
    }
    $dc.Pop(); $dc.Close()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size,$size,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=New-Object IO.MemoryStream
    $encoder.Save($stream); $bytes=$stream.ToArray(); $stream.Dispose()
    return ,$bytes
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'logo-original-preview.png'),(Render-Brand 512 $false))
[IO.File]::WriteAllBytes((Join-Path $OutputDirectory '1nstall-icon.png'),(Render-Brand 1024 $true))
$sizes=@(16,20,24,32,40,48,64,128,256)
$images=@($sizes | ForEach-Object { ,(Render-Brand $_ $true) })
$stream=New-Object IO.MemoryStream; $writer=[IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset=6+16*$sizes.Count
for ($i=0;$i -lt $sizes.Count;$i++) {
    $dimension=if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension); $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
    $offset+=$images[$i].Length
}
foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
$writer.Flush(); [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'src/1nstall.ico'),$stream.ToArray()); $writer.Dispose()
$tx=$matrix.OffsetX.ToString([Globalization.CultureInfo]::InvariantCulture); $ty=$matrix.OffsetY.ToString([Globalization.CultureInfo]::InvariantCulture)
$s=$scale.ToString([Globalization.CultureInfo]::InvariantCulture)
$iconSvg=@"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<defs><linearGradient id="tile" x2="1" y2="1"><stop stop-color="#8574BE"/><stop offset="1" stop-color="#332A55"/></linearGradient><radialGradient id="light" cx=".23" cy=".05" r="1"><stop stop-color="#D5C3FF" stop-opacity=".33"/><stop offset="1" stop-color="#D5C3FF" stop-opacity="0"/></radialGradient><linearGradient id="face" x2="1" y2="1"><stop stop-color="#FFF"/><stop offset="1" stop-color="#E7E0F6"/></linearGradient><linearGradient id="sage" x2="1" y2="1"><stop stop-color="#C4D7B5"/><stop offset="1" stop-color="#8DA87E"/></linearGradient></defs>
<rect x="16" y="16" width="480" height="480" rx="110" fill="url(#tile)"/><rect x="16" y="16" width="480" height="480" rx="110" fill="url(#light)" stroke="#C8BBE6" stroke-opacity=".4" stroke-width="2"/>
<g transform="matrix($s 0 0 $s $tx $ty)"><g fill="#221A3A" opacity=".2" transform="translate(0 $((7/$scale).ToString([Globalization.CultureInfo]::InvariantCulture)))"><path d="$($paths[0].GetAttribute('d'))"/><path d="$($paths[1].GetAttribute('d'))"/></g><path fill="url(#face)" d="$($paths[0].GetAttribute('d'))"/><path fill="url(#sage)" d="$($paths[1].GetAttribute('d'))"/></g></svg>
"@
[IO.File]::WriteAllText((Join-Path $OutputDirectory '1nstall-icon.svg'),$iconSvg)
Write-Output 'Brand icon generated: 9 native ICO sizes, PNG and SVG.'
