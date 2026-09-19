# SeaUI 网关 systemd 部署（RDK X5）

1. `scp rdkx5/deploy/seaui-gateway.service sunrise@<rdk_ip>:/tmp/ && ssh sunrise@<rdk_ip> "sudo cp /tmp/seaui-gateway.service /etc/systemd/system/ && sudo systemctl daemon-reload"`
2. `ssh sunrise@<rdk_ip> "sudo systemctl enable --now seaui-gateway"`
3. `ssh sunrise@<rdk_ip> "journalctl -u seaui-gateway -f"` 实时查看网关日志。
