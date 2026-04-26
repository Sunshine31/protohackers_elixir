import socket

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('localhost', 5004))
print(s.recv(1024).decode()) # Welcome...
s.send(b"Alice\n")
print(s.recv(1024).decode()) # Room contents...
s.close()
