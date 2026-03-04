import os
from huggingface_hub import InferenceClient

token = os.environ.get("HF_TOKEN")
assert token and token.startswith("hf_"), "HF_TOKEN no está seteado"

client = InferenceClient(api_key=token)

model = "stabilityai/stable-diffusion-2-1"
prompt = "a simple logo icon, flat, minimal, white background"

print("Trying model:", model)
img = client.text_to_image(prompt, model=model)  # PIL.Image
out = "hf_test.png"
img.save(out)
print("OK wrote", out)
