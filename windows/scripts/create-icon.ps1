param([Parameter(Mandatory=$true)][string]$Source, [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$directory = Split-Path -Parent $Destination
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$image = [System.Drawing.Image]::FromFile($Source)
try {
    $bitmap = [System.Drawing.Bitmap]::new(256, 256)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($image, 0, 0, 256, 256)
        } finally { $graphics.Dispose() }
        $png = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
            $bytes = $png.ToArray()
            $writer = [System.IO.BinaryWriter]::new([System.IO.File]::Create($Destination))
            try {
                $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
                $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
                $writer.Write([uint16]1); $writer.Write([uint16]32)
                $writer.Write([uint32]$bytes.Length); $writer.Write([uint32]22)
                $writer.Write($bytes)
            } finally { $writer.Dispose() }
        } finally { $png.Dispose() }
    } finally { $bitmap.Dispose() }
} finally { $image.Dispose() }
