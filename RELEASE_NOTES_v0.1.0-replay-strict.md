# Release v0.1.0-replay-strict

## Evidencia
- Tag: v0.1.0-replay-strict
- Repo archive (git archive) SHA256: 5486991281204454DC2F5E74DDB5F93F74E687C983E6C5BBF83EBA160BE882F3

## Export determinista (packs)
- Pack con cache (pack): 77aca667a3688334bc22b835adf574162bfe8b1be61e194b62c1ae0f7c4951da
- Pack sin cache (pack_new): 3b9810635ea29ce971f75fb20971f05c34c1fcf3ddc6502303bcc6f1239ce231

## Estado
- python -m py_compile app/main.py => OK
- python -m py_compile app/providers/text_provider.py => OK
- studio validate --pack_dir pack => OK
- studio validate --pack_dir pack_new => OK
