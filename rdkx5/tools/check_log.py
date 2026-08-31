import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.127.10", username="sunrise", password="sunrise", timeout=12, look_for_keys=False, allow_agent=False)
cmd = "grep -iE 'ACK|STATUSTEXT|arm|servo|channel|prearm' /tmp/gw.log | tail -30"
i, o, e = c.exec_command(cmd, timeout=10)
print(o.read().decode(errors="replace"))
c.close()
