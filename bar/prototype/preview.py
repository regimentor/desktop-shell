"""Throwaway bar design preview: python3 bar/prototype/preview.py."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SOURCE = Path(__file__).with_name("bar-design.fragment.html")


class Preview(BaseHTTPRequestHandler):
    def do_GET(self):
        content = (
            '<!doctype html><html lang="ru"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>Daevox bar — prototype</title>'
            '<style>body{margin:24px;background:#11111b}main{max-width:1920px;margin:auto}</style>'
            '<main>' + SOURCE.read_text() + '</main></html>'
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(content)


if __name__ == "__main__":
    print("Prototype: http://127.0.0.1:8766/?variant=A", flush=True)
    HTTPServer(("127.0.0.1", 8766), Preview).serve_forever()
