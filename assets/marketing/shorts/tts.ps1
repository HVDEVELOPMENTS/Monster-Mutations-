# Speaks every line of scripts.json with a Windows voice into out/<short>/lineN.wav
# and writes out/<short>/durations.json (seconds per line), which build_short.py reads.
param([string]$Voice = "Microsoft David Desktop", [int]$Rate = 1)

Add-Type -AssemblyName System.Speech
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scripts = Get-Content (Join-Path $here "scripts.json") -Raw | ConvertFrom-Json

foreach ($prop in $scripts.PSObject.Properties) {
    $dir = Join-Path $here ("out\" + $prop.Name)
    New-Item -ItemType Directory -Force $dir | Out-Null
    $durations = @()
    $i = 0
    foreach ($line in $prop.Value.lines) {
        $wav = Join-Path $dir ("line$i.wav")
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.SelectVoice($Voice)
        $synth.Rate = $Rate
        $fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(44100, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
        $synth.SetOutputToWaveFile($wav, $fmt)
        $synth.Speak($line.say)
        $synth.Dispose()
        $bytes = (Get-Item $wav).Length - 44
        $durations += [math]::Round($bytes / (44100 * 2), 3)
        $i++
    }
    ConvertTo-Json -InputObject $durations | Set-Content -Encoding utf8 (Join-Path $dir "durations.json")
    "$($prop.Name): $($durations -join ', ')"
}
