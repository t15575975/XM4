using System;
using System.Runtime.InteropServices;

// Independent Windows Winsock2 RFCOMM test, modeled on Sony Device Center and
// Sony Headphones Client. No payloads are sent or received.
internal static class NativeRfcommProbe
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct SockAddrBth
    {
        public ushort AddressFamily;
        public ulong BluetoothAddress;
        public Guid ServiceClassId;
        public uint Port;
    }

    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAStartup(ushort version, IntPtr data);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSACleanup();
    [DllImport("Ws2_32.dll", EntryPoint = "socket", ExactSpelling = true)]
    private static extern IntPtr NativeSocket(int family, int type, int protocol);
    [DllImport("Ws2_32.dll", EntryPoint = "connect", ExactSpelling = true)]
    private static extern int NativeConnect(IntPtr socket, ref SockAddrBth name, int length);
    [DllImport("Ws2_32.dll", EntryPoint = "closesocket", ExactSpelling = true)]
    private static extern int NativeClose(IntPtr socket);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAGetLastError();

    internal static void Connect(ulong address, Guid service, uint port)
    {
        var length = Marshal.SizeOf<SockAddrBth>();
        if (length != 30)
            throw new InvalidOperationException($"Incorrect SOCKADDR_BTH layout: {length} bytes (expected 30).");
        Console.WriteLine($"Native Winsock2: AF_BTH=32; SOCK_STREAM=1; BTHPROTO_RFCOMM=3; sockaddr={length}");
        Console.WriteLine($"Connect target: service={service}, channel={(port == 0 ? "SDP lookup" : port.ToString())}");
        IntPtr wsaData = Marshal.AllocHGlobal(512);
        IntPtr socket = new IntPtr(-1);
        bool started = false;
        try
        {
            int start = WSAStartup(0x0202, wsaData);
            if (start != 0)
            {
                Console.WriteLine($"WSAStartup FAILED: {start}");
                return;
            }
            started = true;
            socket = NativeSocket(32, 1, 3);
            if (socket == new IntPtr(-1))
            {
                Console.WriteLine($"Native socket FAILED: WSAGetLastError={WSAGetLastError()}");
                return;
            }

            var remote = new SockAddrBth
            {
                AddressFamily = 32,
                BluetoothAddress = address,
                ServiceClassId = service,
                Port = port
            };
            Console.WriteLine("Connecting (without sending any application data)...");
            int status = NativeConnect(socket, ref remote, length);
            int error = status == 0 ? 0 : WSAGetLastError();
            if (status == 0)
                Console.WriteLine("NATIVE CONNECTED: Success. Closing without sending data.");
            else
                Console.WriteLine($"NATIVE CONNECT FAILED: WSAGetLastError={error}");
        }
        finally
        {
            if (socket != new IntPtr(-1))
                NativeClose(socket);
            if (started)
                WSACleanup();
            Marshal.FreeHGlobal(wsaData);
        }
    }
}
