"""Mac-only Swift integration tests use this isolated fake backend, never a real user DB."""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,obj,status=200):
        data=json.dumps(obj).encode();self.send_response(status);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def do_GET(self):
        if self.path=='/api/native/session':return self.reply({'protocol':1,'token':'fixture'})
        if self.path=='/api/health':return self.reply({'ollama':True,'models':['qwen3:4b']})
        self.reply({},404)
    def do_POST(self):
        obj=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.headers.get('X-Atlas-Token')!='fixture':return self.reply({},403)
        if self.path=='/api/chat/cancel':return self.reply({'ok':True})
        if self.path=='/api/action/request':return self.reply({'token':'one-use','description':'Calculator öffnen'})
        if self.path=='/api/action/confirm':
            return self.reply({'ok':True} if obj.get('approved') is True else {'error':'Missing approval'},200 if obj.get('approved') is True else 400)
        if self.path=='/api/native/intent':
            if obj['message']=='calculate':return self.reply({'kind':'answer','answer':'391.'})
            if obj['message']=='open two':return self.reply({'kind':'tools','steps':[{'name':'local_open','input':{'kind':'app','target':x}} for x in ['calculator','notes']]})
            if obj['message']=='bad tool':return self.reply({'kind':'tools','steps':[{'name':'run_shell','input':{}}]})
            return self.reply({'kind':'chat'})
        text=obj['history'][-1]['content']
        if text=='redirect':
            self.send_response(302);self.send_header('Location','http://127.0.0.1:1/never');self.end_headers();return
        self.send_response(200);self.send_header('Content-Type','application/x-ndjson');self.end_headers()
        events=[{'type':'start'},{'type':'delta','text':'Hallo '},{'type':'delta','text':'Robin'}]
        if text=='error':events.append({'type':'error','error':'Testfehler'})
        elif text!='incomplete':events.append({'type':'done','truncated':text=='truncated'})
        try:
            for event in events:
                self.wfile.write((json.dumps(event)+'\n').encode());self.wfile.flush()
                time.sleep(.03)
        except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
with open(sys.argv[1],'w') as f:f.write(str(server.server_port))
server.serve_forever()
