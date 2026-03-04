from pathlib import Path

path = Path(r".\app\main.py")
text = path.read_text(encoding="utf-8")

old = '''    if any(k in text for k in productivity_keywords):
        query = "productive person working at desk laptop home office vertical portrait"
        reason = "productivity_office_detected"
    elif any(k in text for k in wellness_keywords):
        query = "person healthy routine meditation exercise calm lifestyle vertical portrait"
        reason = "wellness_lifestyle_detected"
    elif any(k in text for k in kitchen_keywords):
        query = "person cooking in kitchen at home vertical portrait"
        reason = "kitchen_lifestyle_detected"
    elif any(k in text for k in phone_keywords):
        query = "person using smartphone at home vertical portrait"
        reason = "phone_social_detected"
    elif any(k in text for k in organization_keywords):
        query = "organized desk workspace cleanup home office vertical portrait"
        reason = "organization_workspace_detected"
    elif any(k in text for k in finance_keywords):
        query = "business person planning money finances laptop desk vertical portrait"
        reason = "finance_business_detected"
    else:
        query = "person explaining topic in modern studio vertical portrait"
        reason = "default_real_world_stock"
'''

new = '''    if any(k in text for k in wellness_keywords):
        query = "person healthy routine meditation exercise calm lifestyle vertical portrait"
        reason = "wellness_lifestyle_detected"
    elif any(k in text for k in kitchen_keywords):
        query = "person cooking in kitchen at home vertical portrait"
        reason = "kitchen_lifestyle_detected"
    elif any(k in text for k in phone_keywords):
        query = "person using smartphone at home vertical portrait"
        reason = "phone_social_detected"
    elif any(k in text for k in organization_keywords):
        query = "organized desk workspace cleanup home office vertical portrait"
        reason = "organization_workspace_detected"
    elif any(k in text for k in finance_keywords):
        query = "business person planning money finances laptop desk vertical portrait"
        reason = "finance_business_detected"
    elif any(k in text for k in productivity_keywords):
        query = "productive person working at desk laptop home office vertical portrait"
        reason = "productivity_office_detected"
    else:
        query = "person explaining topic in modern studio vertical portrait"
        reason = "default_real_world_stock"
'''

if old not in text:
    raise SystemExit("No encontré el bloque if/elif esperado en app/main.py")

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("OK: prioridad de heurística corregida")
