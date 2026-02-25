import os
import subprocess
import threading
import urllib.request
import json
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
A1111_DEFAULT = "http://127.0.0.1:7860"

def logln(log, s):
    log.insert(tk.END, s + "\n")
    log.see(tk.END)

def run_cmd(cmd, log: scrolledtext.ScrolledText, env=None):
    def worker():
        try:
            p = subprocess.Popen(
                cmd,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=env or os.environ.copy(),
                shell=False,
            )
            for line in p.stdout:
                log.insert(tk.END, line)
                log.see(tk.END)
            rc = p.wait()
            logln(log, f"[exit={rc}]")
        except Exception as e:
            logln(log, f"[error] {e}")
    threading.Thread(target=worker, daemon=True).start()

def http_get_json(url: str, timeout_s: int = 10):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8", errors="replace"))

def http_post_json(url: str, payload: dict, timeout_s: int = 30):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8", errors="replace")) if raw else {}

def main():
    root = tk.Tk()
    root.title("STUDIO_MVP v0.3 - GUI (Tk)")
    root.geometry("980x650")

    frm = ttk.Frame(root, padding=10)
    frm.pack(fill=tk.BOTH, expand=True)

    mode = tk.StringVar(value="SMOKE")
    script = tk.StringVar(value="hola live")
    base_url = tk.StringVar(value=A1111_DEFAULT)

    model_var = tk.StringVar(value="(sin cargar)")
    models = []

    top = ttk.Frame(frm)
    top.pack(fill=tk.X)

    ttk.Label(top, text="Modo:").pack(side=tk.LEFT)
    ttk.Combobox(top, textvariable=mode, values=["SMOKE", "LIVE", "LIVE_FAST"], width=12, state="readonly").pack(side=tk.LEFT, padx=6)

    ttk.Label(top, text="Script:").pack(side=tk.LEFT, padx=(12,0))
    ttk.Entry(top, textvariable=script, width=55).pack(side=tk.LEFT, padx=6)

    arow = ttk.Frame(frm)
    arow.pack(fill=tk.X, pady=(8,0))

    ttk.Label(arow, text="A1111 BaseUrl:").pack(side=tk.LEFT)
    ttk.Entry(arow, textvariable=base_url, width=30).pack(side=tk.LEFT, padx=6)

    ttk.Label(arow, text="Modelo:").pack(side=tk.LEFT, padx=(12,0))
    model_combo = ttk.Combobox(arow, textvariable=model_var, values=["(sin cargar)"], width=55, state="readonly")
    model_combo.pack(side=tk.LEFT, padx=6)

    btns = ttk.Frame(frm)
    btns.pack(fill=tk.X, pady=8)

    log = scrolledtext.ScrolledText(frm, height=26)
    log.pack(fill=tk.BOTH, expand=True)

    def do_run():
        m = mode.get()
        s = script.get().strip() or "hola live"
        if m == "SMOKE":
            run_cmd(["cmd", "/c", "tools\\smoke_v03.cmd"], log)
        elif m == "LIVE_FAST":
            run_cmd(["cmd", "/c", "tools\\run_live_v03.cmd", "hola live"], log)
        else:
            env = os.environ.copy()
            env["STUDIO_ALLOW_LIVE"] = "1"
            run_cmd(["python", "-m", "cli.main", "--v03-config", "config\\studio_v03_live_a1111.json", "--script", s], log, env=env)

    def do_check():
        run_cmd(["cmd", "/c", "tools\\a1111_ping.cmd"], log)
        run_cmd(["cmd", "/c", "tools\\a1111_models.cmd"], log)

    def do_start():
        bat = r"C:\stable-diffusion-webui\webui-user.bat"
        if not os.path.exists(bat):
            messagebox.showerror("A1111", f"No encuentro: {bat}")
            return
        subprocess.Popen(["cmd.exe","/c","start","",bat,"--api"], cwd=os.path.dirname(bat), shell=False)
        logln(log, "[info] A1111 launching... wait for http://127.0.0.1:7860")

    def do_clean():
        run_cmd(["cmd", "/c", "tools\\clean_outputs.cmd"], log)

    def refresh_models():
        nonlocal models
        u = base_url.get().strip().rstrip("/")
        try:
            models = http_get_json(u + "/sdapi/v1/sd-models", timeout_s=10)
            titles = [m.get("title","") for m in models if m.get("title")]
            if not titles:
                raise RuntimeError("No titles in models.")
            model_combo["values"] = titles
            model_var.set(titles[0])
            logln(log, f"[ok] modelos cargados: {len(titles)}")
        except Exception as e:
            messagebox.showerror("Models", f"No pude cargar modelos: {e}")
            logln(log, f"[error] models: {e}")

    def set_model():
        u = base_url.get().strip().rstrip("/")
        title = model_var.get().strip()
        if not title or title == "(sin cargar)":
            messagebox.showinfo("Set model", "No hay modelo seleccionado.")
            return
        try:
            http_post_json(u + "/sdapi/v1/options", {"sd_model_checkpoint": title}, timeout_s=30)
            opts = http_get_json(u + "/sdapi/v1/options", timeout_s=10)
            cur = opts.get("sd_model_checkpoint", "(unknown)")
            logln(log, f"[ok] modelo actual: {cur}")
        except Exception as e:
            messagebox.showerror("Set model", f"No pude setear modelo: {e}")
            logln(log, f"[error] set_model: {e}")

    ttk.Button(btns, text="Run", command=do_run).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Check A1111", command=do_check).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Start A1111", command=do_start).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Refresh models", command=refresh_models).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Set model", command=set_model).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clean outputs", command=do_clean).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clear log", command=lambda: log.delete("1.0", tk.END)).pack(side=tk.RIGHT, padx=4)

    root.mainloop()

if __name__ == "__main__":
    main()
