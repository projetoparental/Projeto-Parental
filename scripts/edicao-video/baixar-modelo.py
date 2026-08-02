#!/usr/bin/env python3
"""
Baixa e configura o modelo Whisper para transcrição offline.
Execute este script UMA VEZ antes de usar o editar-video.ps1.
"""

import os
import sys
from pathlib import Path

# Define cache em local persistente
cache_dir = Path.home() / ".cache" / "whisper"
cache_dir.mkdir(parents=True, exist_ok=True)

print(f"Configurando cache de modelos em: {cache_dir}")
os.environ["HF_HOME"] = str(cache_dir)

try:
    from faster_whisper import WhisperModel

    print("\nBaixando modelo 'small' (essa é a primeira vez, pode levar alguns minutos)...")
    print("Tamanho: ~1.4 GB")

    model = WhisperModel("small", device="cpu", compute_type="int8")
    print("\n✅ Modelo baixado e pronto para usar!")
    print(f"   Localização: {cache_dir}")

except Exception as e:
    print(f"\n❌ Erro ao baixar modelo: {e}", file=sys.stderr)
    print("\nDica: verifique a conexão de internet e tente novamente.", file=sys.stderr)
    sys.exit(1)
