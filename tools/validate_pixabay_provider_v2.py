import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.providers.image_provider import ProviderImage

p = ProviderImage()
r = p.generate(
    purpose="pixabay_core_smoke_v2",
    prompt="unused prompt",
    seed=456,
)

img_path = Path(r["path"])
meta_path = img_path.with_suffix(".json")

print("=== GENERATE RESULT ===")
print(r)
print()

print("=== FILE CHECK ===")
raw = img_path.read_bytes()
print("IMAGE_PATH  :", img_path)
print("META_PATH   :", meta_path)
print("PNG_SIG     :", raw[:8] == b"\x89PNG\r\n\x1a\n")
print("FILE_SIZE   :", len(raw))
print()

meta = json.loads(meta_path.read_text(encoding="utf-8"))
m = meta.get("meta", {})

print("=== META CHECK ===")
print("provider          :", meta.get("provider"))
print("stock_query       :", meta.get("params", {}).get("stock_query"))
print("asset_id          :", m.get("asset_id"))
print("image_content_type:", m.get("image_content_type"))
print("api_search_url    :", m.get("api_search_url"))
print("redacted_ok       :", "***REDACTED***" in str(m.get("api_search_url", "")))
