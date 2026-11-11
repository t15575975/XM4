using InTheHand.Net.Sockets;
using System.Linq;

Console.WriteLine("XM4 RFCOMM SDP discovery (read-only; no RFCOMM sockets or commands)");
try
{
    using var client = new BluetoothClient();
    var paired = client.PairedDevices.ToArray();
    Console.WriteLine($"Paired devices: {paired.Length}");
    var matches = paired.Where(d => d.DeviceName.Contains("WF-1000XM4", StringComparison.OrdinalIgnoreCase)).ToArray();
    if (matches.Length == 0)
    {
        Console.WriteLine("WF-1000XM4 not found in paired devices. Confirm Windows pairing.");
        return;
    }
    foreach (var device in matches)
    {
        Console.WriteLine($"Device: {device.DeviceName}; paired={device.Authenticated}; connected={device.Connected}");
        try
        {
            // false requests fresh service discovery where supported.
            var services = (await device.GetRfcommServicesAsync(cached: false)).Distinct().ToArray();
            Console.WriteLine($"RFCOMM service UUID count: {services.Length}");
            foreach (var service in services) Console.WriteLine($"  {service}");
            if (services.Length == 0) Console.WriteLine("No RFCOMM service UUIDs returned; not proof of absence.");
        }
        catch (Exception e)
        {
            Console.WriteLine($"SDP query failed: {e.GetType().Name}: {e.Message}");
        }
    }
}
catch (Exception e)
{
    Console.WriteLine($"Bluetooth discovery failed: {e.GetType().Name}: {e.Message}");
}
