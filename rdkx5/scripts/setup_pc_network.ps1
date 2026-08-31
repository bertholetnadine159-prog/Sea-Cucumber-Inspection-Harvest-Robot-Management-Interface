# ============================================================================
# [PC side] Configure the wired NIC for direct Ethernet link to RDK X5.
#
# Target: static 192.168.127.100/24, gateway 192.168.127.1, DNS 223.5.5.5.
# Also removes any stale 192.168.127.100 left on the Loopback interface.
#
# Usage (PowerShell, Administrator for -Apply):
#   .\setup_pc_network.ps1 -Check     # read-only diagnostics
#   .\setup_pc_network.ps1 -Apply     # apply static IP configuration
# ============================================================================
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$TargetIp = '192.168.127.100'
$TargetPrefix = 24
$TargetGateway = '192.168.127.1'
$TargetDns = '223.5.5.5'
$TargetBoard = '192.168.127.10'

function Get-PhysicalEthernetAdapter {
    # Prefer a connected wired adapter, otherwise the first physical one.
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InterfaceDescription -match 'Ethernet|GbE|PCIe' -and
            $_.InterfaceDescription -match 'Realtek|Intel' -and
            $_.InterfaceDescription -notmatch 'Virtual|VMware|Tunnel|TAP|Bluetooth|Wi-Fi|Wireless'
        } |
        Sort-Object { if ($_.Status -eq 'Up') { 0 } else { 1 } }, Name
    return $adapters | Select-Object -First 1
}

$adapter = Get-PhysicalEthernetAdapter
if (-not $adapter) {
    Write-Output '[FAIL] No physical Ethernet adapter found'
    exit 1
}

Write-Output "Ethernet adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
Write-Output "Link status: $($adapter.Status)  LinkSpeed: $($adapter.LinkSpeed)"

if ($adapter.Status -ne 'Up') {
    Write-Output '[WARN] Adapter has no link: plug the cable into RDK X5 and power the board on.'
    if (-not $Apply) {
        exit 2
    }
}

$current = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.PrefixOrigin -notin 'WellKnown' } |
    Select-Object -First 1

if ($current -and $current.IPAddress -eq $TargetIp -and $current.PrefixLength -eq $TargetPrefix) {
    Write-Output "[OK] Adapter already set to $TargetIp/$TargetPrefix"
} elseif ($Apply) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Output '[FAIL] -Apply requires an elevated PowerShell'
        exit 1
    }
    try {
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $TargetIp -PrefixLength $TargetPrefix -DefaultGateway $TargetGateway | Out-Null
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $TargetDns
        Write-Output "[OK] Configured $TargetIp/$TargetPrefix, gateway $TargetGateway"
    } catch {
        Write-Output "[WARN] Direct IP apply failed ($($_.Exception.Message)). Cleaning stale entries and retrying without gateway..."
        Remove-NetRoute -InterfaceIndex $adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $TargetIp -PrefixLength $TargetPrefix | Out-Null
        Write-Output "[OK] Configured $TargetIp/$TargetPrefix (no default gateway)"
    }
} else {
    $currentText = if ($current) { "$($current.IPAddress)/$($current.PrefixLength)" } else { 'unconfigured' }
    Write-Output "[INFO] Current: $currentText, target: $TargetIp/$TargetPrefix (run with -Apply to change)"
}

$stale = Get-NetIPAddress -InterfaceAlias 'Loopback*' -IPAddress $TargetIp -ErrorAction SilentlyContinue
if ($stale) {
    if ($Apply) {
        Remove-NetIPAddress -InterfaceIndex $stale.InterfaceIndex -IPAddress $TargetIp -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output '[OK] Removed stale Loopback address'
    } else {
        Write-Output '[WARN] Stale Loopback address found (cleared by -Apply)'
    }
}

# 清理 Loopback 上残留的伪路由 / 邻居，避免流量被吸走
$bogusRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    $_.InterfaceAlias -like 'Loopback*' -and (
        $_.DestinationPrefix -eq '0.0.0.0/0' -or $_.NextHop -eq $TargetBoard
    )
}
if ($bogusRoutes) {
    if ($Apply) {
        foreach ($route in $bogusRoutes) {
            Remove-NetRoute -InterfaceIndex $route.InterfaceIndex -DestinationPrefix $route.DestinationPrefix -NextHop $route.NextHop -Confirm:$false -ErrorAction SilentlyContinue
        }
        Write-Output '[OK] Removed bogus Loopback routes'
    } else {
        Write-Output "[WARN] Bogus Loopback route(s) found (cleared by -Apply):"
        $bogusRoutes | Select-Object DestinationPrefix, NextHop, InterfaceAlias | Format-Table -AutoSize
    }
}

$bogusNeighbor = Get-NetNeighbor -InterfaceAlias 'Loopback*' -IPAddress $TargetBoard -ErrorAction SilentlyContinue
if ($bogusNeighbor) {
    if ($Apply) {
        Remove-NetNeighbor -InterfaceIndex $bogusNeighbor.InterfaceIndex -IPAddress $TargetBoard -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output '[OK] Removed bogus Loopback neighbor entry'
    } else {
        Write-Output "[WARN] Bogus Loopback neighbor entry found (cleared by -Apply)"
    }
}

# 最终验证：物理网卡必须真实持有 192.168.127.100
$verified = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $TargetIp }
if ($Apply) {
    if ($verified) {
        Write-Output "[OK] Verified: adapter holds $TargetIp/$($verified.PrefixLength)"
    } else {
        Write-Output '[FAIL] Static IP was NOT applied to the adapter. Run this script again.'
        exit 1
    }
}

if ($Apply) {
    Write-Output '[CHECK] Pinging RDK X5 ...'
    if (Test-Connection -ComputerName $TargetBoard -Count 1 -Quiet) {
        Write-Output "[OK] $TargetBoard is reachable, board is online"
    } else {
        Write-Output "[WARN] $TargetBoard not reachable yet; check cable and board power"
    }
}
