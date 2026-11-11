using InTheHand.Net.Sockets;
using System.Linq;

var connectMode = args.Length == 2 && args[0] == "--connect";
if (args.Length != 0 && !connectMode)
{
    Console.WriteLine("Usage: dotnet run -- [--connect <SDP-listed-service-UUID>]");
    return;
}
Console.WriteLine("XM4 Bluetooth Classic SDP / RFCOMM probe");
Console.WriteLine("No Sony commands or application data are sent.");
try
{
    using var client = new BluetoothClient();
    var matches = client.PairedDevices.Where(d => d.DeviceName.Contains("WF-1000XM4", StringComparison.OrdinalIgnoreCase)).ToArray();
    Console.WriteLine($"Matching paired devices: {matches.Length}");
    foreach (var device in matches)
    {
        Console.WriteLine($"Device: {device.DeviceName}; paired={device.Authenticated}; connected={device.Connected}");
        Console.WriteLine($"Platform: {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}; OS={System.Runtime.InteropServices.RuntimeInformation.OSDescription}; process64bit={Environment.Is64BitProcess}");
        Guid[] services;
        try
        {
            services = (await device.GetRfcommServicesAsync(cached: false)).Distinct().ToArray();
            Console.WriteLine($"RFCOMM service UUID count: {services.Length}");
            foreach (var service in services) Console.WriteLine($"  {service}");
        }
        catch (Exception e)
        {
            Console.WriteLine($"SDP query failed: {e.GetType().Name}: {e.Message}");
            continue;
        }
        if (!connectMode) continue;
        if (!Guid.TryParse(args[1], out var target) || !services.Contains(target))
        {
            Console.WriteLine("Refusing connection: target UUID is not in the fresh SDP results.");
            continue;
        }
        Console.WriteLine($"Attempting RFCOMM connect to {target} (no data writes)...");
        using var probe = new BluetoothClient();
        try
        {
            // Windows Bluetooth connect can block; do not start another probe if this times out.
            var attempt = probe.ConnectAsync(device.DeviceAddress, target);
            var completed = await Task.WhenAny(attempt, Task.Delay(TimeSpan.FromSeconds(12)));
            if (completed != attempt)
            {
                Console.WriteLine("TIMEOUT after 12 seconds. Connection may still be pending; exit and wait before retrying.");
            }
            else
            {
                await attempt;
                Console.WriteLine($"CONNECTED: {probe.Connected}. Closing immediately without sending data.");
            }
        }
        catch (Exception e)
        {
            Console.WriteLine($"CONNECT FAILED: {e.GetType().Name}: {e.Message}");
            if (e is System.Net.Sockets.SocketException se)
                Console.WriteLine($"SocketErrorCode={se.SocketErrorCode}; NativeErrorCode={se.NativeErrorCode}; ErrorCode={se.ErrorCode}");
            Console.WriteLine($"HResult=0x{e.HResult:X8}");
        }
    }
}
catch (Exception e)
{
    Console.WriteLine($"Probe failed: {e.GetType().Name}: {e.Message}");
}
