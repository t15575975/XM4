# Read-only Windows Bluetooth inventory for WF-1000XM4.
# No device configuration changes, sockets, or Sony control commands.
$ErrorActionPreference = 'Continue'
Write-Output "=== Windows / PowerShell ==="
[Environment]::OSVersion.VersionString
$PSVersionTable.PSVersion.ToString()
Write-Output "=== Sony / Bluetooth PnP devices ==="
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'WF-1000XM4|Sony|Bluetooth' -or $_.InstanceId -match 'WF-1000XM4' } |
  Select-Object Class, FriendlyName, Status, InstanceId | Format-Table -AutoSize -Wrap | Out-String -Width 220
Write-Output "=== Serial COM ports (if exposed) ==="
Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue |
  Select-Object Name, DeviceID, Description | Format-Table -AutoSize | Out-String -Width 220
Write-Output "=== Bluetooth radio adapters ==="
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
  Select-Object FriendlyName, Status | Format-Table -AutoSize | Out-String -Width 220
Write-Output "=== End of read-only report ==="
