import os
from huggingface_hub import InferenceClient

token = os.environ.get("HF_TOKEN")
assert token and token.startswith("hf_"), "HF_TOKEN no está seteado"

client = InferenceClient(api_key=token)
prompt = "a simple logo icon, flat, minimal, white background"

candidates = [
  "black-forest-labs/FLUX.1-schnell",
  "stabilityai/stable-diffusion-xl-base-1.0",
  "runwayml/stable-diffusion-v1-5",
]

for m in candidates:
    try:
        print("TRY:", m)
        img = client.text_to_image(prompt, model=m)
        out = "hf_ok.png"
        img.save(out)
        print("OK MODEL:", m, "->", out)
        break
    except Exception as e:
        print("FAIL:", m, "->", repr(e))
else:
    raise SystemExit("No funcionó ningún modelo candidato.")
