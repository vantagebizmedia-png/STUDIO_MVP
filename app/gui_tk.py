import os
import subprocess
import threading
import urllib.request
import json
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
A1111_DEFAULT = "http://127.0.0.1:7860"
STATE_PATH = os.path.join(ROOT, "workspace", "gui_state.json")

def logln(log, s):
    log.insert(tk.END, s + "\n")
    log.see(tk.END)

def run_cmd(cmd, log, env=None):
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

def http_get_json(url, timeout_s=10):
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8", errors="replace"))

def http_post_json(url, payload, timeout_s=30):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8", errors="replace")) if raw else {}

def load_state():
    try:
        if os.path.exists(STATE_PATH):
            with open(STATE_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {}

def save_state(data):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def main():
    st = load_state()

    root = tk.Tk()
    root.title("STUDIO_MVP v0.3 - GUI (Tk)")
    root.geometry("1020x700")

    frm = ttk.Frame(root, padding=10)
    frm.pack(fill=tk.BOTH, expand=True)

    script = tk.StringVar(value=st.get("script", "hola live"))
    base_url = tk.StringVar(value=st.get("base_url", A1111_DEFAULT))
    model_var = tk.StringVar(value="(sin cargar)")
    set_on_run = tk.BooleanVar(value=bool(st.get("set_model_on_run", True)))

    top = ttk.Frame(frm)
    top.pack(fill=tk.X)

    ttk.Label(top, text="Script:").pack(side=tk.LEFT)
    ttk.Entry(top, textvariable=script, width=72).pack(side=tk.LEFT, padx=8)

    ttk.Checkbutton(top, text="Set model on Run LIVE", variable=set_on_run).pack(side=tk.LEFT, padx=10)

    arow = ttk.Frame(frm)
    arow.pack(fill=tk.X, pady=(8,0))

    ttk.Label(arow, text="A1111 BaseUrl:").pack(side=tk.LEFT)
    ttk.Entry(arow, textvariable=base_url, width=32).pack(side=tk.LEFT, padx=8)

    ttk.Label(arow, text="Modelo:").pack(side=tk.LEFT, padx=(12,0))
    model_combo = ttk.Combobox(arow, textvariable=model_var, values=["(sin cargar)"], width=62, state="readonly")
    model_combo.pack(side=tk.LEFT, padx=8)

    btns = ttk.Frame(frm)
    btns.pack(fill=tk.X, pady=10)

    log = scrolledtext.ScrolledText(frm, height=26)
    log.pack(fill=tk.BOTH, expand=True)

    def refresh_models(silent=False):
        u = base_url.get().strip().rstrip("/")
        try:
            models = http_get_json(u + "/sdapi/v1/sd-models", timeout_s=10)
            titles = [m.get("title","") for m in models if m.get("title")]
            if not titles:
                raise RuntimeError("No titles in models.")
            model_combo["values"] = titles
            preferred = st.get("model_title")
            model_var.set(preferred if preferred in titles else titles[0])
            if not silent:
                logln(log, f"[ok] modelos cargados: {len(titles)}")
        except Exception as e:
            if not silent:
                messagebox.showerror("Models", f"No pude cargar modelos: {e}")
                logln(log, f"[error] models: {e}")

    def set_model():
        u = base_url.get().strip().rstrip("/")
        title = model_var.get().strip()
        if not title or title == "(sin cargar)":
            messagebox.showinfo("Set model", "No hay modelo seleccionado.")
            return True
        try:
            http_post_json(u + "/sdapi/v1/options", {"sd_model_checkpoint": title}, timeout_s=30)
            opts = http_get_json(u + "/sdapi/v1/options", timeout_s=10)
            cur = opts.get("sd_model_checkpoint", "(unknown)")
            logln(log, f"[ok] modelo actual: {cur}")
            return True
        except Exception as e:
            messagebox.showerror("Set model", f"No pude setear modelo: {e}")
            logln(log, f"[error] set_model: {e}")
            return False

    def run_smoke():
        run_cmd(["cmd", "/c", "tools\\smoke_v03.cmd"], log)

    def run_live_fast():
        run_cmd(["cmd", "/c", "tools\\run_live_v03.cmd", "hola live"], log)

    def run_live():
        u = base_url.get().strip().rstrip("/")
        s = script.get().strip() or "hola live"

        # set model first (optional)
        if set_on_run.get():
            logln(log, "[info] setting model before LIVE...")
            ok = set_model()
            if not ok:
                logln(log, "[warn] LIVE aborted (set_model failed).")
                return

        env = os.environ.copy()
        env["STUDIO_ALLOW_LIVE"] = "1"
        run_cmd(["python", "-m", "cli.main", "--v03-config", "config\\studio_v03_live_a1111.json", "--script", s], log, env=env)

    def check_a1111():
        run_cmd(["cmd", "/c", "tools\\a1111_ping.cmd"], log)
        run_cmd(["cmd", "/c", "tools\\a1111_models.cmd"], log)

    def start_a1111():
        bat = r"C:\stable-diffusion-webui\webui-user.bat"
        if not os.path.exists(bat):
            messagebox.showerror("A1111", f"No encuentro: {bat}")
            return
        subprocess.Popen(["cmd.exe","/c","start","",bat,"--api"], cwd=os.path.dirname(bat), shell=False)
        logln(log, "[info] A1111 launching... wait for http://127.0.0.1:7860")

    def clean_outputs():
        run_cmd(["cmd", "/c", "tools\\clean_outputs.cmd"], log)

    def clear_log():
        log.delete("1.0", tk.END)

    def on_close():
        save_state({
            "base_url": base_url.get().strip(),
            "script": script.get().strip(),
            "model_title": model_var.get().strip(),
            "set_model_on_run": bool(set_on_run.get()),
        })
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)

    ttk.Button(btns, text="Run SMOKE", command=run_smoke).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Run LIVE", command=run_live).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Run LIVE_FAST", command=run_live_fast).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Check A1111", command=check_a1111).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Start A1111", command=start_a1111).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Refresh models", command=refresh_models).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Set model", command=set_model).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clean outputs", command=clean_outputs).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clear log", command=clear_log).pack(side=tk.RIGHT, padx=4)

    root.after(300, lambda: refresh_models(silent=True))

    root.mainloop()

if __name__ == "__main__":
    main()
