$ErrorActionPreference = "SilentlyContinue"
$id = "USB\VID_0000&PID_0002\5&26B53364&0&9"
"Removing error device node..."
Remove-PnpDevice -InstanceId $id -Confirm:$false
Start-Sleep -Seconds 2
"Rescanning..."
pnputil /scan-devices
Start-Sleep -Seconds 3
"Done. Current USB error devices:"
$bad = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "USB" -and $_.Status -eq "Error" }
if ($bad) { $bad | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 200 }
else { "(none)" }
