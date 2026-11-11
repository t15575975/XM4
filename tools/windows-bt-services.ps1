# Read-only Windows Bluetooth Classic service inventory
# No connections to COM ports or Sony command transmission.
$ErrorActionPreference = "Continue"
Write-Output "=== WF-1000XM4 PnP service records ==="
Get-PnpDevice | Where-Object { $_.FriendlyName -like '*WF-1000XM4*' } | ForEach-Object {
  Write-Output ("Name: " + $_.FriendlyName)
  Write-Output ("Class: " + $_.Class + " / Status: " + $_.Status)
  Write-Output ("Instance: " + $_.InstanceId)
  Get-PnpDeviceProperty -InstanceId $_.InstanceId -ErrorAction SilentlyContinue |
    Where-Object { $_.KeyName -match 'Service|HardwareIds|CompatibleIds|ContainerId' } |
    ForEach-Object { Write-Output ("  " + $_.KeyName + ": " + ($_.Data -join ', ')) }
}
Write-Output "=== COM4 / COM5 mapping ==="
Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -match 'COM4|COM5' } |
  ForEach-Object {
    Write-Output ("Port: " + $_.FriendlyName + " / " + $_.InstanceId)
    Get-PnpDeviceProperty -InstanceId $_.InstanceId -ErrorAction SilentlyContinue |
      Where-Object { $_.KeyName -match 'PortName|Parent|ContainerId|HardwareIds|Service' } |
      ForEach-Object { Write-Output ("  " + $_.KeyName + ": " + ($_.Data -join ', ')) }
  }
Write-Output "=== Finished; no Bluetooth connections were opened ==="
