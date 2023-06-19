import sys
import socketserver
import threading
import os
import time
import base64
# from prompt_toolkit import prompt
from colorama import Fore
from colorama import Style

class FileWatcher:

  def __init__(self, path):
    self._cb = []
    self._path = path
    self._stat = -1
    pass
    
  def add_notification_receiver(self, cb):
    self._cb.append(cb)
    pass
  
  def notify_all(self):
    for cb in self._cb:
      cb(self._path)
      
  def stat(self):
    try:
      return os.stat(self._path).st_mtime
    except:
      return -1
      
  def run(self):
    while True:
      cur_stat = self.stat()
      if self._stat != cur_stat:
        print(f"{Fore.YELLOW}[-] stat changed, notify all...")
        self._stat = cur_stat
        self.notify_all()
      time.sleep(0.1)

  def start(self):
    self.joinable = threading.Thread(target=self.run, daemon=True)
    self.joinable.start()
    return self.joinable

class TCPHandler(socketserver.StreamRequestHandler):
  
  _handlers = set()
  _path = None
  
  @staticmethod
  def add_handler(obj):
    TCPHandler._handlers.add(obj)
  
  @staticmethod
  def del_handler(obj):
    TCPHandler._handlers.remove(obj)

  def setup(self):
    super().setup()
    TCPHandler.add_handler(self)
    print(f"{Fore.YELLOW}[-] connection established")
    
  def finish(self):
    TCPHandler.del_handler(self)
    print(f"{Fore.YELLOW}[-] connection closed")
    super().finish()
    
  def send_feat(self, path):
    with open(path, 'rb') as fp:
      feat = base64.b64encode(fp.read())
      print(f"{Fore.YELLOW}[-] CMD:feature sent")
      self.request.send(b'feat' + feat + b'\n')
  
  def send_exit(self):
    print(f"{Fore.YELLOW}[-] CMD:exit sent")
    self.request.send(b'exit\n')
      
  def handle(self):
    self.send_feat(TCPHandler._path)
    # self.request.send(b"feat\n")
    # self.request.send(b"exit\n")
    while True:
      line = self.rfile.readline()
      #print(line.strip())
      if not line: break
      if line.startswith(b'[!]'):
        sys.stdout.buffer.write(Fore.RED.encode())
      elif line.startswith(b'[~]'):
        sys.stdout.buffer.write(Fore.BLUE.encode())
      else:
        sys.stdout.buffer.write(Fore.GREEN.encode())
      sys.stdout.buffer.write(line)
      sys.stdout.buffer.flush()
      sys.stdout.buffer.write(Style.RESET_ALL.encode())
      
class FeatureServer:

  def __init__(self, addr):
    ip, port = addr.split(":")
    self.host = ip
    self.port = int(port)
    pass
    
  def update_feature(self, path):
    TCPHandler._path = path
    for h in TCPHandler._handlers:
      h.send_feat(path)
  
  def quit(self):
    for h in TCPHandler._handlers:
      h.send_exit()
      
  def serve(self):
    with socketserver.ThreadingTCPServer((self.host, self.port), TCPHandler) as server:
      server.serve_forever()
      
  def start(self):    
    self.joinable = threading.Thread(target=self.serve, daemon=True)
    self.joinable.start()
    return self.joinable

def main(listen, feature):
  fw = FileWatcher(feature)
  srv = FeatureServer(listen)
  fw.add_notification_receiver(srv.update_feature)
  t1 = srv.start()
  t2 = fw.start()
  # join_all(t1, t2)
  #t1.join()
  #t2.join()
  try:
    while True: time.sleep(1)
  except KeyboardInterrupt:
    try:
      srv.quit()
    except:
      pass
  print(Style.RESET_ALL)
  
def pop_flag(a, f):
  if f not in a: return False
  a.remove(f)
  return True

def pop_arg(a, n):
  if n not in a: return None
  idx = a.index(n)
  if idx == len(a) - 1: return None
  del a[idx]
  ret = a[idx]
  del a[idx]
  return ret

if __name__ == '__main__':
  args = sys.argv[1:]
  listen = pop_arg(args, '-l')
  feature = pop_arg(args, '-f')
  main(listen, feature)
  