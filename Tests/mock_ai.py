#!/usr/bin/env python3
"""Loopback-only DeepSeek-compatible fixture. Accepts synthetic credentials only."""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    leak_count = 0
    def log_message(self, *args):
        pass
    def reply(self, status, value, **headers):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        for k, v in headers.items(): self.send_header(k, v)
        self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError): pass
    def do_GET(self):
        if self.path == "/metrics": self.reply(200, {"redirect_leaks": Handler.leak_count})
        else:
            Handler.leak_count += 1
            self.reply(400, {"error": "unexpected redirect target"})
    def do_POST(self):
        if self.path not in ("/v1/chat/completions", "/chat/completions"):
            Handler.leak_count += 1; self.reply(400, {"error": "unexpected path"}); return
        if self.headers.get("Authorization") != "Bearer test-ai-only":
            self.reply(401, {"error": "fixture only accepts synthetic credentials"}); return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            assert self.headers.get("Content-Type") == "application/json"
            assert body["stream"] is False and body["response_format"]["type"] == "json_object"
            assert len(body["messages"]) == 2
            assert body["messages"][0]["role"] == "system" and body["messages"][1]["role"] == "user"
            context = json.loads(body["messages"][1]["content"])
            code = context["source_code"]
            model = body["model"]
        except Exception:
            self.reply(400, {"error": "request contract failed"}); return
        if model == "unauthorized": self.reply(401, {"error": "sensitive-body test-ai-only must not appear in errors"}); return
        if model == "rate-limit": self.reply(429, {"error": "quota"}); return
        if model == "server-error": self.reply(500, {"error": "internal"}); return
        if model == "redirect":
            self.reply(307, {}, Location=f"http://127.0.0.1:{self.server.server_port}/leak"); return
        if model == "slow": time.sleep(2)
        if model == "oversize":
            self.reply(200, {"padding": "x" * 2_100_000}); return
        edit = "Mode: edit." in body["messages"][0]["content"]
        replacement = code.replace("print(1 / 0)", "print('AI_REVIEW_FIXED')")
        payload = {"summary": "發現一處除零風險，已提供最小修改建議。", "findings": [
            {"severity": "high", "line": 1, "title": "除零會導致執行失敗", "detail": "分母為零時 Python 會拋出 ZeroDivisionError；請先檢查分母或移除無效運算。"}],
            "replacement_code": replacement if edit or model == "unexpected-edit" else None}
        content = json.dumps(payload, ensure_ascii=False)
        if model == "empty": content = "   "
        if model == "invalid-json": content = "```json\nnot-json\n```"
        if model == "malformed-envelope": self.reply(200, {"choices": []}); return
        reason = "length" if model == "truncated" else "tool_calls" if model == "tool-call" else "stop"
        self.reply(200, {"choices": [{"finish_reason": reason, "message": {"content": content}}]})

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--port", type=int, default=0); parser.add_argument("--ready")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    endpoint = f"http://127.0.0.1:{server.server_port}/v1"
    if args.ready: Path(args.ready).write_text(json.dumps({"endpoint": endpoint}))
    print(endpoint, flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
