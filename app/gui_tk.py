import os
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

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
            log.insert(tk.END, f"\n[exit={rc}]\n")
            log.see(tk.END)
        except Exception as e:
            log.insert(tk.END, f"\n[error] {e}\n")
            log.see(tk.END)
    threading.Thread(target=worker, daemon=True).start()

def main():
    root = tk.Tk()
    root.title("STUDIO_MVP v0.3 - GUI (Tk)")
    root.geometry("900x600")

    frm = ttk.Frame(root, padding=10)
    frm.pack(fill=tk.BOTH, expand=True)

    mode = tk.StringVar(value="SMOKE")
    script = tk.StringVar(value="hola live")

    top = ttk.Frame(frm)
    top.pack(fill=tk.X)

    ttk.Label(top, text="Modo:").pack(side=tk.LEFT)
    ttk.Combobox(top, textvariable=mode, values=["SMOKE", "LIVE", "LIVE_FAST"], width=12, state="readonly").pack(side=tk.LEFT, padx=6)

    ttk.Label(top, text="Script:").pack(side=tk.LEFT, padx=(12,0))
    ttk.Entry(top, textvariable=script, width=50).pack(side=tk.LEFT, padx=6)

    btns = ttk.Frame(frm)
    btns.pack(fill=tk.X, pady=8)

    log = scrolledtext.ScrolledText(frm, height=25)
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
        # abre A1111 en nueva ventana
        bat = r"C:\stable-diffusion-webui\webui-user.bat"
        if not os.path.exists(bat):
            messagebox.showerror("A1111", f"No encuentro: {bat}")
            return
        subprocess.Popen(["cmd", "/c", f'"{bat}" --api'], cwd=os.path.dirname(bat), shell=False)
        log.insert(tk.END, "[info] A1111 launching... wait for http://127.0.0.1:7860\n")
        log.see(tk.END)

    def do_clean():
        run_cmd(["cmd", "/c", "tools\\clean_outputs.cmd"], log)

    ttk.Button(btns, text="Run", command=do_run).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Check A1111", command=do_check).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Start A1111", command=do_start).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clean outputs", command=do_clean).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Clear log", command=lambda: log.delete("1.0", tk.END)).pack(side=tk.RIGHT, padx=4)

    root.mainloop()

if __name__ == "__main__":
    main()
