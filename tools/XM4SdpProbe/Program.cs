using InTheHand.Net.Sockets;
using InTheHand.Net;
using System.Net.Sockets;
using System.Linq;

if (args.Length == 1 && args[0] == "--self-test")
{
    SonyWireCodec.SelfTest();
    return;
}

var connectMode = args.Length == 2 && args[0] == "--connect";
var nativeReadAnc = args.Length == 1 && args[0] == "--native-read-anc";
var nativeChannel9 = args.Length == 1 && args[0] == "--native-channel9";
var nativeV2 = args.Length == 1 && args[0] == "--native-v2";
if (args.Length != 0 && !connectMode && !nativeChannel9 && !nativeV2 && !nativeReadAnc)
{
    Console.WriteLine("Usage: dotnet run -- [--self-test | --native-read-anc | --connect <SDP-listed-service-UUID> | --native-v2 | --native-channel9]");
    return;
}
Console.WriteLine("XM4 Bluetooth Classic SDP / RFCOMM probe");
Console.WriteLine(nativeReadAnc ? "Mode: GET CURRENT ANC STATE ONLY (Sony DataMdr 66 15 + ACK); does not change ANC settings." : "No Sony commands or application data are sent.");
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
        if (nativeReadAnc)
        {
            NativeSonyRead.QueryNoiseControl(device.DeviceAddress.ToUInt64());
            continue;
        }
        if (nativeChannel9)
        {
            // WF-1000XM4 specific Linux implementation uses RFCOMM channel 9.
            // Windows cross-platform client also tries channel 9 first as fallback.
            NativeRfcommProbe.Connect(device.DeviceAddress.ToUInt64(), Guid.Empty, 9);
            continue;
        }
        if (nativeV2)
        {
            // Known Sony V2 UUID from Sony Device Center; require advertisement in fresh SDP.
            var sonyV2 = Guid.Parse("956c7b26-d49a-4ba8-b03f-b17d393cb6e2");
            if (!services.Contains(sonyV2))
            {
                Console.WriteLine("Not testing Sony V2: UUID missing from fresh SDP results.");
                continue;
            }
            NativeRfcommProbe.Connect(device.DeviceAddress.ToUInt64(), sonyV2, 0);
            continue;
        }
        if (!connectMode) continue;
        if (!Guid.TryParse(args[1], out var target) || !services.Contains(target))
        {
            Console.WriteLine("Refusing connection: target UUID is not in the fresh SDP results.");
            continue;
        }
        Console.WriteLine($"Attempting RFCOMM connect to {target} (no data writes)...");
        var endpoint = new BluetoothEndPoint(device.DeviceAddress, target);
        var serialized = endpoint.Serialize();
        Console.WriteLine($"Endpoint: family={endpoint.AddressFamily}; sockaddr size={serialized.Size}; service={endpoint.Service}; port={endpoint.Port}");
        using var probe = new BluetoothClient();
        Console.WriteLine($"Socket: family={probe.Client.AddressFamily}; type={probe.Client.SocketType}; protocol={probe.Client.ProtocolType}");
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
