# -*- coding: utf-8 -*-
"""STUDIO v0.2  Mini GUI: Prompt -> Generate -> Export -> Replay."""

import os
import tkinter as tk
from tkinter import ttk, messagebox
from typing import Optional

from app.v02_core import extract_script_preview, generate_v02, replay_v02

ROOT_DIR = os.path.dirname(os.path.dirname(__file__))
WORKSPACE_DIR = os.getenv("STUDIO_WORKSPACE", "workspace")
if not os.path.isabs(WORKSPACE_DIR):
    WORKSPACE_DIR = os.path.join(ROOT_DIR, WORKSPACE_DIR)
class StudioV02GUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("STUDIO v0.2")
        self.geometry("980x680")
        self.resizable(True, True)

        self.seed_var = tk.StringVar(value="123")
        self.pack_dir_var = tk.StringVar(value="(aÃºn no generado)")
        self.zip_sha_var = tk.StringVar(value="(aÃºn no generado)")
        self.zip_path_var = tk.StringVar(value="(aÃºn no generado)")
        self.status_var = tk.StringVar(value="Listo")

        self._last_replay_path = None  # type: Optional[str]

        self._build()

    def _build(self):
        pad = 12

        top = ttk.Frame(self)
        top.pack(fill="x", padx=pad, pady=(pad, 6))

        ttk.Label(top, text="Prompt", font=("Segoe UI", 12, "bold")).pack(anchor="w")

        self.prompt_box = tk.Text(self, height=6, wrap="word")
        self.prompt_box.pack(fill="x", padx=pad)
        self.prompt_box.insert("1.0", "finanzas personales, hÃ¡bitos, ansiedad")
        row = ttk.Frame(self)
        row.pack(fill="x", padx=pad, pady=(8, 6))

        ttk.Label(row, text="Seed:").pack(side="left")
        ttk.Entry(row, textvariable=self.seed_var, width=12).pack(side="left", padx=(6, 18))

        ttk.Button(row, text="Generate", command=self.on_generate).pack(side="left")
        ttk.Button(row, text="Replay", command=self.on_replay).pack(side="left", padx=(10, 0))
        ttk.Button(row, text="Open folder", command=self.on_open_folder).pack(side="left", padx=(14, 0))
        ttk.Button(row, text="Open ZIP", command=self.on_open_zip).pack(side="left", padx=(10, 0))

        out = ttk.LabelFrame(self, text="Salida")
        out.pack(fill="both", expand=True, padx=pad, pady=(6, pad))

        meta = ttk.Frame(out)
        meta.pack(fill="x", padx=10, pady=(10, 6))

        ttk.Label(meta, text="Pack:", font=("Segoe UI", 9, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(meta, textvariable=self.pack_dir_var, wraplength=880).grid(row=0, column=1, sticky="w")

        ttk.Label(meta, text="ZIP sha256:", font=("Segoe UI", 9, "bold")).grid(row=1, column=0, sticky="w", pady=(6, 0))
        ttk.Label(meta, textvariable=self.zip_sha_var, wraplength=880).grid(row=1, column=1, sticky="w", pady=(6, 0))

        ttk.Label(meta, text="ZIP path:", font=("Segoe UI", 9, "bold")).grid(row=2, column=0, sticky="w", pady=(6, 0))
        ttk.Label(meta, textvariable=self.zip_path_var, wraplength=880).grid(row=2, column=1, sticky="w", pady=(6, 0))


        ttk.Label(out, text="Preview (guion por clips)", font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=10, pady=(6, 0))

        self.preview_box = tk.Text(out, height=18, wrap="word")
        self.preview_box.pack(fill="both", expand=True, padx=10, pady=(6, 10))
        self.preview_box.insert("1.0", "(aÃºn no generado)")
        status = ttk.Frame(self)
        status.pack(fill="x", padx=pad, pady=(0, pad))
        ttk.Label(status, textvariable=self.status_var).pack(anchor="w")

    def _read_prompt(self) -> str:
        return (self.prompt_box.get("1.0", "end") or "").strip()

    def on_generate(self):
        prompt = self._read_prompt()
        if not prompt:
            messagebox.showwarning("Falta prompt", "Escribe un prompt.")
            return

        try:
            seed = int((self.seed_var.get() or "123").strip())
        except ValueError:
            messagebox.showwarning("Seed invÃ¡lido", "Seed debe ser un entero (ej. 123).")
            return

        try:
            self.status_var.set("Generando...")
            self.update_idletasks()

            res = generate_v02(prompt=prompt, seed=seed)

            self._last_replay_path = res["replay_path"]
            self.pack_dir_var.set(res["pack_dir"])
            self.zip_sha_var.set(res.get("zip_sha256") or "(sin sha)")
            self.zip_path_var.set(res.get("zip_path") or "(sin zip)")

            prev = extract_script_preview(res["pack_dir"])
            self.preview_box.delete("1.0", "end")
            self.preview_box.insert("1.0", prev)

            self.status_var.set("OK: generado + exportado. replay.json listo.")
        except Exception as e:
            self.status_var.set("Error")
            messagebox.showerror("Error", f"No pude generar:\n{e}")

    def on_open_folder(self):
        pack_dir = (self.pack_dir_var.get() or "").strip()
        if not pack_dir or pack_dir.startswith("(") or (not os.path.isdir(pack_dir)):
            messagebox.showinfo("Open folder", "No hay pack_dir vÃ¡lido todavÃ­a. Primero corre Generate.")
            return
        try:
            os.startfile(pack_dir)  # Windows Explorer
        except Exception as e:
            messagebox.showerror("Open folder", f"No pude abrir la carpeta:\n{e}")

    def on_open_zip(self):
        zip_path = (self.zip_path_var.get() or "").strip()
        if not zip_path or zip_path.startswith("(") or (not os.path.isfile(zip_path)):
            messagebox.showinfo("Open ZIP", "No hay ZIP vÃ¡lido todavÃ­a. Primero corre Generate.")
            return
        try:
            os.startfile(zip_path)
        except Exception as e:
            messagebox.showerror("Open ZIP", f"No pude abrir el ZIP:\n{e}")

    def on_replay(self):
        if not self._last_replay_path or not os.path.isfile(self._last_replay_path):
            messagebox.showinfo("Replay", "Primero corre Generate (crea replay.json).")
            return

        try:
            self.status_var.set("Reproduciendo...")
            self.update_idletasks()

            res = replay_v02(self._last_replay_path)

            self.pack_dir_var.set(res["pack_dir"])
            self.zip_sha_var.set(res.get("zip_sha256") or "(sin sha)")
            self.zip_path_var.set(res.get("zip_path") or "(sin zip)")

            prev = extract_script_preview(res["pack_dir"])
            self.preview_box.delete("1.0", "end")
            self.preview_box.insert("1.0", prev)

            if res.get("ok"):
                self.status_var.set("OK: replay determinista verificado.")
            else:
                diffs = res.get("diffs") or []
                msg = "Replay terminÃ³ con diferencias.\n\n"
                if not res.get("zip_ok", True):
                    msg += f"ZIP esperado: {res.get('zip_expected')}\nZIP actual: {res.get('zip_sha256')}\n\n"
                if diffs:
                    msg += "Primeras diferencias:\n" + "\n".join([f"- {d.get('file')}" for d in diffs[:8]])
                self.status_var.set("Replay con diferencias")
                messagebox.showwarning("Replay", msg)
        except Exception as e:
            self.status_var.set("Error")
            messagebox.showerror("Error", f"No pude hacer replay:\n{e}")


def main():
    os.makedirs(WORKSPACE_DIR, exist_ok=True)
    app = StudioV02GUI()
    app.mainloop()


if __name__ == "__main__":
    main()




