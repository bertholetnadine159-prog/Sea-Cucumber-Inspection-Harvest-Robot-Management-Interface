$ErrorActionPreference = "SilentlyContinue"
"--- All present USB devices ---"
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "USB*" } |
    Select-Object Status, Class, FriendlyName | Format-Table -AutoSize | Out-String -Width 160
"--- Devices with errors (yellow bang) ---"
$bad = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -eq "Error" -or $_.Status -eq "Degraded" }
if ($bad) { $bad | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 200 }
else { "(none)" }
"--- Unknown devices ---"
$unk = Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq "Unknown" }
if ($unk) { $unk | Select-Object Status, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 200 }
else { "(none)" }
