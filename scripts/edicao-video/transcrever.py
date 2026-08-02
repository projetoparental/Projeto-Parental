import sys
import os
from pathlib import Path
from faster_whisper import WhisperModel

cache_dir = Path.home() / ".cache" / "whisper"
os.environ["HF_HOME"] = str(cache_dir)


def formatar_srt_tempo(segundos):
    horas = int(segundos // 3600)
    minutos = int((segundos % 3600) // 60)
    segs = segundos % 60
    milissegundos = int((segs - int(segs)) * 1000)
    return f"{horas:02d}:{minutos:02d}:{int(segs):02d},{milissegundos:03d}"


def formatar_legivel(segundos):
    minutos = int(segundos // 60)
    segs = int(segundos % 60)
    return f"{minutos}:{segs:02d}"


def main():
    entrada, saida_srt, saida_txt = sys.argv[1], sys.argv[2], sys.argv[3]

    # "small" é rápido em CPU comum. Troque para "medium" ou "large-v3" se tiver
    # GPU ou não se importar de esperar mais, em troca de mais precisão.
    model = WhisperModel("small", device="cpu", compute_type="int8")
    segments, _ = model.transcribe(entrada, language="pt", vad_filter=True)

    with open(saida_srt, "w", encoding="utf-8") as srt, open(saida_txt, "w", encoding="utf-8") as txt:
        for i, seg in enumerate(segments, start=1):
            srt.write(f"{i}\n")
            srt.write(f"{formatar_srt_tempo(seg.start)} --> {formatar_srt_tempo(seg.end)}\n")
            srt.write(f"{seg.text.strip()}\n\n")

            txt.write(f"[{formatar_legivel(seg.start)} - {formatar_legivel(seg.end)}] {seg.text.strip()}\n")

    print(f"Transcrição concluída: {saida_srt}")


if __name__ == "__main__":
    main()
