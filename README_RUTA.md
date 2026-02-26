# STUDIO_MVP - Ruta oficial (MVP determinista)

## Principios
- Determinista / controlado por operador: no auto-modifica nada; cambios solo via commits/parches explícitos.
- Defaults seguros: config/providers.json viene en DRY (no gasta).
- Dos entregables distintos:
  1) ZIP del repo (codigo): git archive ...
  2) ZIP del pack (contenido generado): sale de tools/zip_pack*

---

## 0) Requisitos
- Python 3.10+ (recomendado)
- FFmpeg + ffprobe en PATH
- (Opcional) Hugging Face token para hf_image:
  - temporal en sesion: $env:HF_TOKEN = "hf_..."

---

## 1) Checks rapidos

### Compilar
```powershell
python -m compileall .\app .\studio .\cli .\tools -q
```

### Tests
```powershell
python -m pytest -q
```

---

## 2) Modos (config/providers.json)
tools/switch_mode.ps1 cambia DRY/LIVE/REPLAY con backup automatico.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\switch_mode.ps1 DRY
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\switch_mode.ps1 LIVE text
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\switch_mode.ps1 REPLAY text
```

---

## 3) Smokes oficiales (1 comando)

### A) Texto LIVE (gasta SOLO texto) - revierte providers.json al final
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\text_live_smoke.ps1 -ScriptText "mi prueba live"
```

### B) Voz gratis (Edge) + demo_image + texto REPLAY (0$)
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\edge_voice_smoke.ps1 -ScriptText "mi prueba live"
```

### C) Imagen real (HF) + voz Edge + texto REPLAY (0$)
Requiere HF_TOKEN en la sesion:
```powershell
$env:HF_TOKEN = "hf_..."
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\hf_edge_smoke.ps1 -ScriptText "mi prueba live"
```

---

## 4) Entregable: ZIP del PACK (contenido)
Tras correr un smoke o un release, ubica PACK_DIR: en el output y luego:

```powershell
# si existe wrapper cmd:
cmd /c .\tools\zip_pack.cmd "<PACK_DIR>" --overwrite

# o python directo:
python .\tools\zip_pack.py --pack-dir "<PACK_DIR>" --overwrite
```

---

## 5) Render directo (sin smoke)
```powershell
python .\tools\render_pack_v03.py --pack-dir "<PACK_DIR>" --w 540 --h 960 --fps 15 --fit crop
```

---

## 6) Auditoria en manifest (opcional)
tools/manifest_audit_inject.py agrega snapshot de providers al manifest_v03.json.
