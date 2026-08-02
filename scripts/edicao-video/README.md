# Editor de Vídeo — Projeto Parental

Scripts para Windows que automatizam a parte pesada da edição (cortar silêncio,
cortar falas erradas, redimensionar para formato vertical e gravar legenda),
deixando o CapCut só para o refinamento final (textos extras, transições, música).

## O que o pipeline faz, em ordem

1. Lista os vídeos da sua pasta Downloads e você escolhe qual editar.
2. Remove automaticamente silêncios/pausas longas (detecção por áudio, via FFmpeg).
3. Transcreve o áudio e mostra o texto com marcação de tempo, para você localizar
   falas erradas ou recomeços (isso não dá para automatizar 100%: o script não
   sabe distinguir "errei e vou recomeçar" de uma fala normal — por isso pede
   para você revisar a transcrição e listar os intervalos a cortar).
4. Corta os intervalos que você marcou.
5. Redimensiona o vídeo para vertical 9:16 (você escolhe: cortar bordas ou fundo desfocado).
6. Gera a legenda final e pergunta o estilo (fonte, tamanho, posição, cor) antes
   de gravar o texto "queimado" no vídeo.
7. Salva o resultado em `conteudo/reels/exports/`.

## Pré-requisitos (rodar uma vez)

Abra o PowerShell na pasta do projeto e rode:

```powershell
.\scripts\edicao-video\instalar-requisitos.ps1
```

Isso instala FFmpeg, Python e a biblioteca `faster-whisper` (motor de transcrição).
Feche e reabra o PowerShell depois de rodar esse script pela primeira vez.

**Opcional (recomendado):** Se você quer baixar o modelo de transcrição antecipadamente
(evita esperar na primeira execução), rode:

```powershell
python .\scripts\edicao-video\baixar-modelo.py
```

Isso é especialmente útil se você está em um ambiente cloud ou offline depois.

## Como usar

1. Coloque o vídeo bruto na sua pasta **Downloads**.
2. Na pasta do projeto, rode:

```powershell
.\scripts\edicao-video\editar-video.ps1
```

3. Siga as perguntas na tela. Em algum momento o Bloco de Notas vai abrir para
   você anotar os trechos com fala errada — escreva um intervalo por linha
   (formato `mm:ss-mm:ss`, ex: `1:23-1:47`), salve e feche.
4. No fim, o script pergunta o estilo da legenda (fonte, tamanho, posição, cor).
5. O vídeo final fica em `conteudo/reels/exports/nome-do-video-pronto.mp4`.

## Limitações conhecidas

- Transcrição roda na CPU por padrão — vídeos longos (aula, workshop de 90 min)
  podem levar vários minutos para transcrever. Para acelerar, edite
  `transcrever.py` e troque `"small"` por um modelo maior só se tiver GPU.
- O modelo Whisper (~1.4 GB) é baixado uma única vez na primeira execução
  (ou via script `baixar-modelo.py`) e fica em cache local em `~/.cache/whisper`.
  Nas próximas execuções, a transcrição é instantânea (sem precisar de internet).
- A detecção de silêncio usa um limiar fixo (-30dB / 0.6s). Se o vídeo tiver
  ruído de fundo alto ou silêncios muito curtos entre frases, pode cortar mais
  ou menos do que o esperado — ajuste os valores em `Remover-Silencio` dentro
  de `editar-video.ps1` se precisar.
- Fontes "estilizadas" (Montserrat, Poppins etc.) só funcionam se estiverem
  instaladas como fonte do sistema no Windows. Arial, Impact e Verdana já vêm
  no Windows por padrão.
