# Pipeline de edição de vídeo para o Projeto Parental.
# Fluxo: seleciona vídeo em Downloads -> remove silêncios -> transcreve ->
# você marca falas erradas para cortar -> corta -> redimensiona para vertical ->
# gera legenda final -> pergunta estilo -> grava legenda queimada no vídeo.
#
# Pré-requisito: rode instalar-requisitos.ps1 uma vez antes de usar este script.

$ErrorActionPreference = "Stop"

$PastaDownloads = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
$PastaProjeto = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$PastaExports = Join-Path $PastaProjeto "conteudo\reels\exports"
$PastaTemp = Join-Path $PastaProjeto "conteudo\reels\_temp"
$PastaTranscricoes = Join-Path $PastaProjeto "conteudo\reels\transcricoes"

New-Item -ItemType Directory -Force -Path $PastaExports, $PastaTemp, $PastaTranscricoes | Out-Null

function Selecionar-Video {
    $videos = Get-ChildItem -Path $PastaDownloads -Include *.mp4, *.mov, *.MP4, *.MOV -Recurse -File |
        Sort-Object LastWriteTime -Descending

    if ($videos.Count -eq 0) {
        Write-Host "Nenhum vídeo encontrado em $PastaDownloads" -ForegroundColor Red
        exit 1
    }

    Write-Host "`nVídeos encontrados em Downloads:`n"
    for ($i = 0; $i -lt $videos.Count; $i++) {
        $tamanhoMB = [math]::Round($videos[$i].Length / 1MB, 1)
        Write-Host "[$i] $($videos[$i].Name)  ($tamanhoMB MB)"
    }

    $escolha = Read-Host "`nDigite o número do vídeo que deseja editar"
    return $videos[[int]$escolha].FullName
}

function Converter-Tempo {
    param([string]$texto)
    $partes = $texto.Split(":")
    if ($partes.Count -eq 2) { return ([double]$partes[0] * 60 + [double]$partes[1]) }
    if ($partes.Count -eq 3) { return ([double]$partes[0] * 3600 + [double]$partes[1] * 60 + [double]$partes[2]) }
    return [double]$texto
}

function Obter-Duracao {
    param([string]$Arquivo)
    $texto = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$Arquivo"
    return [double]$texto
}

function Cortar-Trechos {
    # Recebe a lista de trechos que devem ser MANTIDOS e remonta o vídeo só com eles,
    # preservando sincronia de áudio e vídeo via trim + concat.
    param([string]$Input, [string]$Output, [array]$Trechos)

    if ($Trechos.Count -eq 0) {
        Write-Host "Nada para cortar, copiando vídeo sem alterações." -ForegroundColor Yellow
        Copy-Item $Input $Output
        return
    }

    $filtros = @()
    $mapas = @()
    for ($i = 0; $i -lt $Trechos.Count; $i++) {
        $ini = $Trechos[$i].Inicio
        $fim = $Trechos[$i].Fim
        $filtros += "[0:v]trim=start=$ini`:end=$fim,setpts=PTS-STARTPTS[v$i]"
        $filtros += "[0:a]atrim=start=$ini`:end=$fim,asetpts=PTS-STARTPTS[a$i]"
        $mapas += "[v$i][a$i]"
    }
    $concat = ($mapas -join "") + "concat=n=$($Trechos.Count):v=1:a=1[outv][outa]"
    $filterComplex = ($filtros -join ";") + ";" + $concat

    & ffmpeg -y -i "$Input" -filter_complex $filterComplex -map "[outv]" -map "[outa]" -c:v libx264 -crf 18 -preset fast -c:a aac "$Output"
}

function Remover-Silencio {
    param([string]$Input, [string]$Output)

    Write-Host "`nAnalisando silêncios..." -ForegroundColor Cyan
    $log = & ffmpeg -i "$Input" -af "silencedetect=noise=-30dB:d=0.6" -f null - 2>&1 | Out-String

    $starts = [regex]::Matches($log, "silence_start:\s*([\d\.]+)") | ForEach-Object { [double]$_.Groups[1].Value }
    $ends = [regex]::Matches($log, "silence_end:\s*([\d\.]+)") | ForEach-Object { [double]$_.Groups[1].Value }

    $silencios = @()
    for ($i = 0; $i -lt $starts.Count; $i++) {
        if ($i -lt $ends.Count) {
            $silencios += [PSCustomObject]@{ Inicio = $starts[$i]; Fim = $ends[$i] }
        }
    }

    if ($silencios.Count -eq 0) {
        Write-Host "Nenhum silêncio significativo encontrado." -ForegroundColor Yellow
        Copy-Item $Input $Output
        return
    }

    $duracaoTotal = Obter-Duracao -Arquivo $Input
    $folga = 0.15
    $manter = @()
    $cursor = 0.0
    foreach ($s in $silencios) {
        $fimFala = [math]::Max($cursor, $s.Inicio + $folga)
        if ($fimFala -gt $cursor) {
            $manter += [PSCustomObject]@{ Inicio = $cursor; Fim = $fimFala }
        }
        $cursor = [math]::Max($cursor, $s.Fim - $folga)
    }
    if ($cursor -lt $duracaoTotal) {
        $manter += [PSCustomObject]@{ Inicio = $cursor; Fim = $duracaoTotal }
    }

    Cortar-Trechos -Input $Input -Output $Output -Trechos $manter
    Write-Host "Silêncios removidos: $($silencios.Count) trechos cortados." -ForegroundColor Green
}

function Remover-Cortes-Manuais {
    param([string]$Input, [string]$Output, [string]$ArquivoCortes)

    $linhasValidas = Get-Content $ArquivoCortes | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") }

    if (-not $linhasValidas -or $linhasValidas.Count -eq 0) {
        Write-Host "Nenhum corte manual informado. Prosseguindo sem alterações." -ForegroundColor Yellow
        Copy-Item $Input $Output
        return
    }

    $duracaoTotal = Obter-Duracao -Arquivo $Input

    $cortes = $linhasValidas | ForEach-Object {
        $p = $_.Split("-")
        [PSCustomObject]@{
            Inicio = Converter-Tempo $p[0].Trim()
            Fim    = Converter-Tempo $p[1].Trim()
        }
    } | Sort-Object Inicio

    $manter = @()
    $cursor = 0.0
    foreach ($c in $cortes) {
        if ($c.Inicio -gt $cursor) {
            $manter += [PSCustomObject]@{ Inicio = $cursor; Fim = $c.Inicio }
        }
        $cursor = [math]::Max($cursor, $c.Fim)
    }
    if ($cursor -lt $duracaoTotal) {
        $manter += [PSCustomObject]@{ Inicio = $cursor; Fim = $duracaoTotal }
    }

    Cortar-Trechos -Input $Input -Output $Output -Trechos $manter
    Write-Host "Cortes manuais aplicados: $($cortes.Count) trechos removidos." -ForegroundColor Green
}

function Redimensionar-Vertical {
    param([string]$Input, [string]$Output)

    Write-Host "`nComo prefere o formato vertical (9:16)?" -ForegroundColor Cyan
    Write-Host "[1] Cortar as bordas (crop) - preenche a tela toda, pode cortar partes da imagem"
    Write-Host "[2] Fundo desfocado (blur) - mantém o vídeo inteiro visível, com faixas desfocadas nas laterais"
    $opcao = Read-Host "Escolha 1 ou 2"

    if ($opcao -eq "1") {
        $filtro = "crop=ih*9/16:ih,scale=1080:1920"
    } else {
        $filtro = "split[original][fundo];[fundo]scale=1080:1920,boxblur=20:5[fundoblur];[original]scale=1080:-1[frente];[fundoblur][frente]overlay=(W-w)/2:(H-h)/2"
    }

    & ffmpeg -y -i "$Input" -vf $filtro -c:a copy "$Output"
}

function Gerar-Transcricao {
    param([string]$Input, [string]$SaidaSrt, [string]$SaidaTxt)

    Write-Host "`nTranscrevendo áudio (pode demorar alguns minutos, dependendo da duração do vídeo)..." -ForegroundColor Cyan
    & python "$PSScriptRoot\transcrever.py" "$Input" "$SaidaSrt" "$SaidaTxt"
}

function Perguntar-EstiloLegenda {
    Write-Host "`n=== Estilo da Legenda ===" -ForegroundColor Cyan

    Write-Host "`nFonte:"
    Write-Host "[1] Arial (limpo, neutro)"
    Write-Host "[2] Impact (grande impacto, estilo virais)"
    Write-Host "[3] Verdana (arredondado, legível)"
    Write-Host "[4] Outra (digite o nome exato de uma fonte instalada no Windows)"
    $f = Read-Host "Escolha a fonte"
    $fonte = switch ($f) {
        "1" { "Arial" }
        "2" { "Impact" }
        "3" { "Verdana" }
        default { Read-Host "Digite o nome da fonte" }
    }

    $tamanho = Read-Host "`nTamanho da fonte (recomendado 60 a 90 para vídeo vertical) [Enter para usar 72]"
    if ([string]::IsNullOrWhiteSpace($tamanho)) { $tamanho = 72 }

    Write-Host "`nPosição da legenda na tela:"
    Write-Host "[1] Parte inferior (padrão dos Reels)"
    Write-Host "[2] Meio da tela"
    Write-Host "[3] Parte superior"
    $p = Read-Host "Escolha a posição"
    $alinhamento = switch ($p) {
        "2" { 5 }
        "3" { 8 }
        default { 2 }
    }
    $margemV = if ($alinhamento -eq 5) { 0 } else { 120 }

    Write-Host "`nCor do texto e do contorno:"
    Write-Host "[1] Branco com contorno preto (clássico)"
    Write-Host "[2] Branco com contorno terracota (cores Método Farol)"
    Write-Host "[3] Amarelo com contorno preto (alto contraste)"
    Write-Host "[4] Cor personalizada (você informa o código hex)"
    $c = Read-Host "Escolha a cor"
    switch ($c) {
        "1" { $corTexto = "&H00FFFFFF"; $corContorno = "&H00000000" }
        "2" { $corTexto = "&H00FFFFFF"; $corContorno = "&H001A3B5C" }
        "3" { $corTexto = "&H0000FFFF"; $corContorno = "&H00000000" }
        default {
            $hexTexto = Read-Host "Hex da cor do texto, formato RRGGBB (ex: FFFFFF para branco)"
            $r = $hexTexto.Substring(0, 2)
            $g = $hexTexto.Substring(2, 2)
            $b = $hexTexto.Substring(4, 2)
            $corTexto = "&H00$b$g$r"
            $corContorno = "&H00000000"
        }
    }

    $espessura = Read-Host "`nEspessura do contorno, de 1 a 5 [Enter para usar 3]"
    if ([string]::IsNullOrWhiteSpace($espessura)) { $espessura = 3 }

    return @{
        Fonte       = $fonte
        Tamanho     = $tamanho
        Alinhamento = $alinhamento
        MargemV     = $margemV
        CorTexto    = $corTexto
        CorContorno = $corContorno
        Contorno    = $espessura
    }
}

function Gravar-Legenda {
    param([string]$Input, [string]$Srt, [string]$Output, [hashtable]$Estilo)

    $srtEscapado = ($Srt -replace '\\', '/') -replace ':', '\:'
    $forceStyle = "FontName=$($Estilo.Fonte),FontSize=$($Estilo.Tamanho),PrimaryColour=$($Estilo.CorTexto),OutlineColour=$($Estilo.CorContorno),BorderStyle=1,Outline=$($Estilo.Contorno),Alignment=$($Estilo.Alinhamento),MarginV=$($Estilo.MargemV)"

    & ffmpeg -y -i "$Input" -vf "subtitles='$srtEscapado':force_style='$forceStyle'" -c:a copy "$Output"
}

# ---------------------------------------------------------------------------

Write-Host "=== Editor de Vídeo - Projeto Parental ===" -ForegroundColor Magenta

$videoOriginal = Selecionar-Video
$nomeBase = [System.IO.Path]::GetFileNameWithoutExtension($videoOriginal)

$semSilencio = Join-Path $PastaTemp "$nomeBase-01-sem-silencio.mp4"
$transcricaoTxtPreliminar = Join-Path $PastaTranscricoes "$nomeBase-preliminar.txt"
$transcricaoSrtPreliminar = Join-Path $PastaTranscricoes "$nomeBase-preliminar.srt"
$cortesManuais = Join-Path $PastaTemp "$nomeBase-cortes-manuais.txt"
$semErros = Join-Path $PastaTemp "$nomeBase-02-sem-erros.mp4"
$vertical = Join-Path $PastaTemp "$nomeBase-03-vertical.mp4"
$transcricaoSrtFinal = Join-Path $PastaTranscricoes "$nomeBase-final.srt"
$transcricaoTxtFinal = Join-Path $PastaTranscricoes "$nomeBase-final.txt"
$final = Join-Path $PastaExports "$nomeBase-pronto.mp4"

Remover-Silencio -Input $videoOriginal -Output $semSilencio

Gerar-Transcricao -Input $semSilencio -SaidaSrt $transcricaoSrtPreliminar -SaidaTxt $transcricaoTxtPreliminar

Write-Host "`nTranscrição gerada em:" -ForegroundColor Green
Write-Host $transcricaoTxtPreliminar
Write-Host "`nAbra esse arquivo, identifique as falas erradas ou recomeços (ex: 'deixa eu começar de novo')."
Write-Host "Escreva os intervalos a cortar no arquivo que vai abrir agora, um por linha, formato mm:ss-mm:ss."
Write-Host "Se não houver nada para cortar, apenas feche o Bloco de Notas sem escrever nada."

New-Item -ItemType File -Force -Path $cortesManuais | Out-Null
Add-Content $cortesManuais "# Escreva um intervalo por linha, exemplo: 1:23-1:47"
Add-Content $cortesManuais "# Salve o arquivo e feche o Bloco de Notas para continuar"

notepad $cortesManuais
Read-Host "`nPressione ENTER aqui depois de salvar e fechar o Bloco de Notas"

Remover-Cortes-Manuais -Input $semSilencio -Output $semErros -ArquivoCortes $cortesManuais

Redimensionar-Vertical -Input $semErros -Output $vertical

Gerar-Transcricao -Input $vertical -SaidaSrt $transcricaoSrtFinal -SaidaTxt $transcricaoTxtFinal

$estilo = Perguntar-EstiloLegenda

Gravar-Legenda -Input $vertical -Srt $transcricaoSrtFinal -Output $final -Estilo $estilo

Write-Host "`n✅ Pronto! Vídeo final salvo em:" -ForegroundColor Green
Write-Host $final -ForegroundColor Green
Write-Host "`nAbra no CapCut se quiser fazer ajustes finais (textos extras, transições, música)." -ForegroundColor Cyan
