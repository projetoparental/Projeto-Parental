# Instala tudo que o editar-video.ps1 precisa: FFmpeg, Python e faster-whisper.
# Rode este script UMA VEZ antes de usar o editar-video.ps1 pela primeira vez.

Write-Host "=== Instalando requisitos para edição de vídeo ===" -ForegroundColor Magenta

function Comando-Existe {
    param([string]$nome)
    return [bool](Get-Command $nome -ErrorAction SilentlyContinue)
}

if (-not (Comando-Existe "ffmpeg")) {
    Write-Host "Instalando FFmpeg via winget..." -ForegroundColor Cyan
    winget install --id Gyan.FFmpeg -e --source winget
} else {
    Write-Host "FFmpeg já está instalado." -ForegroundColor Green
}

if (-not (Comando-Existe "python")) {
    Write-Host "Instalando Python via winget..." -ForegroundColor Cyan
    winget install --id Python.Python.3.12 -e --source winget
} else {
    Write-Host "Python já está instalado." -ForegroundColor Green
}

Write-Host "`nInstalando faster-whisper (motor de transcrição de áudio)..." -ForegroundColor Cyan
python -m pip install --upgrade pip
python -m pip install faster-whisper

Write-Host "`n✅ Requisitos instalados." -ForegroundColor Green
Write-Host "Feche e reabra o PowerShell antes de rodar o editar-video.ps1, para o Windows reconhecer os novos comandos." -ForegroundColor Yellow
