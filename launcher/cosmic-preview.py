"""Throwaway preview server for launcher/cosmic-prototype.html."""
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent


if __name__ == "__main__":
    os.chdir(ROOT)
    print("Prototype: http://127.0.0.1:8767/cosmic-prototype.html?variant=A", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8767), SimpleHTTPRequestHandler).serve_forever()
