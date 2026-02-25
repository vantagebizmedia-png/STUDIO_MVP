from __future__ import annotations
import argparse
import json
import random
from datetime import datetime

def gen_ideas(niche: str, audience: str, seed: int, n: int):
    r = random.Random(seed)

    formats = [
        ("Diagnóstico rápido", "Checklist de 30 segundos para detectar {issue}."),
        ("Mito vs realidad", "Lo que casi todos creen sobre {issue} y por qué te cuesta $$$."),
        ("Error común", "El error #1 que daña {part} (y cómo evitarlo en 1 minuto)."),
        ("Señales", "3 señales de que {issue} antes de quedarte botado."),
        ("Ahorro", "Cómo ahorrar en {service} sin caer en estafas (pregunta clave)."),
        ("Mantenimiento", "Rutina de {time} para alargar la vida de {part}."),
        ("Herramienta", "La herramienta más barata que te salva en {scenario}."),
        ("Comparativa", "{optionA} vs {optionB}: cuál conviene según tu caso."),
        ("Explicación simple", "Qué hace {system} y por qué importa (en lenguaje humano)."),
        ("Miniprueba", "Prueba casera: si pasa esto, necesitas {service}."),
    ]

    issues = [
        "frenos chillando", "vibración al frenar", "luz de check engine", "batería descargándose",
        "sobrecalentamiento", "consumo excesivo de gasolina", "olor a gasolina", "ruido al girar",
        "aire acondicionado que no enfría", "dirección dura", "llantas gastándose irregular",
        "carro que tiembla al ralentí",
    ]
    parts = ["tus frenos", "tu batería", "tu motor", "tu suspensión", "tus llantas", "tu transmisión", "tu alternador", "tu sistema de enfriamiento"]
    services = ["un cambio de aceite", "una alineación", "un diagnóstico OBD2", "un cambio de frenos", "un mantenimiento del A/C", "un cambio de bujías"]
    scenarios = ["un viaje largo", "una lluvia fuerte", "una revisión pre-compra", "una subida pronunciada", "una mañana fría"]
    systems = ["el alternador", "el sistema de frenos ABS", "la transmisión automática", "el sistema de enfriamiento", "el sensor MAF", "las bujías"]
    options = [("aceite sintético", "aceite convencional"), ("llantas nuevas", "llantas usadas"), ("pastillas cerámicas", "pastillas semi-metálicas"), ("taller de barrio", "concesionario")]
    times = ["10 minutos", "5 minutos", "15 minutos"]

    hooks = [
        "Si tu carro hace esto, NO lo ignores.",
        "Esto te puede ahorrar una visita al taller.",
        "Antes de gastar dinero, revisa esto.",
        "La mayoría se equivoca aquí (y sale caro).",
        "Haz esta prueba antes de conducir hoy.",
    ]
    ctas = [
        "¿Quieres la lista completa? Comenta CHECK y te la paso.",
        "Si te sirvió, guarda este video para cuando lo necesites.",
        "¿Te ha pasado? Escribe el síntoma y te digo por dónde empezar.",
        "Si quieres, hago parte 2 con ejemplos reales.",
        "Comparte con alguien que siempre pospone el mantenimiento.",
    ]

    ideas = []
    used = set()

    for _ in range(n * 5):
        fmt_name, fmt_tpl = r.choice(formats)
        issue = r.choice(issues)
        part = r.choice(parts)
        service = r.choice(services)
        scenario = r.choice(scenarios)
        system = r.choice(systems)
        optionA, optionB = r.choice(options)
        time = r.choice(times)

        title = fmt_tpl.format(issue=issue, part=part, service=service, scenario=scenario, system=system, optionA=optionA, optionB=optionB, time=time)
        key = (fmt_name, title)
        if key in used:
            continue
        used.add(key)

        ideas.append({
            "id": len(ideas) + 1,
            "nicho": niche,
            "angulo": fmt_name,
            "idea": title,
            "hook": r.choice(hooks),
            "audiencia": audience,
            "cta": r.choice(ctas),
            "duracion_objetivo": r.choice(["20-30s", "30-45s", "45-60s"]),
            "escenas_sugeridas": r.choice([4, 5, 6, 7]),
        })
        if len(ideas) >= n:
            break

    return ideas

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("niche", help="Nicho/tema (ej: reparación de automóviles)")
    ap.add_argument("--seed", type=int, default=7, help="Semilla para regenerar otras 5 ideas")
    ap.add_argument("--n", type=int, default=5, help="Cantidad de ideas")
    ap.add_argument("--audience", default="dueños de carro (principiantes)", help="Audiencia objetivo")
    ap.add_argument("--json", action="store_true", help="Salida en JSON")
    ap.add_argument("--out", default="", help="Guardar salida en archivo (opcional)")
    args = ap.parse_args()

    ideas = gen_ideas(args.niche, args.audience, args.seed, args.n)

    if args.json:
        s = json.dumps({"seed": args.seed, "created_at": datetime.now().isoformat(timespec="seconds"), "ideas": ideas}, ensure_ascii=False, indent=2)
        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                f.write(s)
            print(f"OK: guardado {args.out}")
        else:
            print(s)
        return

    print(f"Nicho: {args.niche}")
    print(f"Audiencia: {args.audience}")
    print(f"Seed: {args.seed}")
    print("-" * 60)
    for it in ideas:
        print(f"[{it['id']}] {it['angulo']}  {it['idea']}")
        print(f"    Hook: {it['hook']}")
        print(f"    Duración: {it['duracion_objetivo']} | Escenas: {it['escenas_sugeridas']}")
        print(f"    CTA: {it['cta']}")
        print()
    print("Elige una idea respondiendo con el número (1-5).")
    print("Si ninguna te gusta: vuelve a correr con otro --seed (ej: --seed 8).")

if __name__ == "__main__":
    main()
