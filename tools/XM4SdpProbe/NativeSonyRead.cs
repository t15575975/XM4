using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

/// <summary>
/// Explicit, read-only Sony ANC state query on the already validated
/// WF-1000XM4 RFCOMM channel 9. Sends only DATA_MDR GET 66 15
/// and required protocol ACKs; does not send ANC SET commands.
/// Based on Sony Device Center ProtocolV2, NoiseControlCodec, FrameCodec.
/// </summary>
internal static class NativeSonyRead
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
    [DllImport("Ws2_32.dll", EntryPoint = "send", ExactSpelling = true)]
    private static extern int NativeSend(IntPtr socket, byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "recv", ExactSpelling = true)]
    private static extern int NativeRecv(IntPtr socket, [Out] byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "setsockopt", ExactSpelling = true)]
    private static extern int NativeSetSocketOption(IntPtr socket, int level, int name, ref int value, int valueLength);
    [DllImport("Ws2_32.dll", EntryPoint = "closesocket", ExactSpelling = true)]
    private static extern int NativeClose(IntPtr socket);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAGetLastError();

    private static bool SendFrame(IntPtr socket, byte[] frame, string label)
    {
        var count = NativeSend(socket, frame, frame.Length, 0);
        if (count != frame.Length)
        {
            Console.WriteLine($"{label} send failed or short: sent={count}/{frame.Length}; WSAGetLastError={WSAGetLastError()}");
            return false;
        }
        Console.WriteLine($"{label} sent: {Convert.ToHexString(frame)}");
        return true;
    }

    private static bool DecodeNoiseControl(byte[] p)
    {
        // Sony Device Center: WF-1000XM4 V2 response:
        // 67 15 01 [enabled] [ambient] [wind] [voice] [ambient level].
        if (p.Length != 8 || p[0] != 0x67 || p[1] != 0x15 ||
            p[2] != 1 || p[3] > 1 || p[4] > 1 || p[6] > 1 || p[7] > 20)
        {
            return false;
        }

        var mode = p[3] == 0 ? "OFF" : p[4] == 1 ? "AMBIENT" : "ANC";
        Console.WriteLine($"ANC STATE CONFIRMED: {mode}; ambientLevel={p[7]}; voiceFocus={p[6]}; windRaw=0x{p[5]:X2}");
        return true;
    }

    internal static void QueryNoiseControl(ulong address)
    {
        var length = Marshal.SizeOf<SockAddrBth>();
        if (length != 30)
            throw new InvalidOperationException($"Wrong SOCKADDR_BTH size: {length}");
        var wsaData = Marshal.AllocHGlobal(512);
        var socket = new IntPtr(-1);
        var started = false;
        try
        {
            var start = WSAStartup(0x0202, wsaData);
            if (start != 0)
            {
                Console.WriteLine($"WSAStartup failed: {start}");
                return;
            }
            started = true;
            socket = NativeSocket(32, 1, 3);
            if (socket == new IntPtr(-1))
            {
                Console.WriteLine($"RFCOMM socket failed: {WSAGetLastError()}");
                return;
            }
            int timeoutMs = 1500;
            if (NativeSetSocketOption(socket, 0xFFFF, 0x1006, ref timeoutMs, sizeof(int)) != 0)
            {
                Console.WriteLine($"SO_RCVTIMEO failed: {WSAGetLastError()}");
                return;
            }
            int sendTimeoutMs = 1500;
            if (NativeSetSocketOption(socket, 0xFFFF, 0x1005, ref sendTimeoutMs, sizeof(int)) != 0)
            {
                Console.WriteLine($"SO_SNDTIMEO failed: {WSAGetLastError()}");
                return;
            }

            var remote = new SockAddrBth
            {
                AddressFamily = 32,
                BluetoothAddress = address,
                ServiceClassId = Guid.Empty,
                Port = 9
            };
            Console.WriteLine("Connecting to RFCOMM channel 9...");
            if (NativeConnect(socket, ref remote, length) != 0)
            {
                Console.WriteLine($"Connect failed: WSAGetLastError={WSAGetLastError()}");
                return;
            }
            Console.WriteLine("CONNECTED. Requesting current ANC state (no setting change)...");
            Thread.Sleep(500);

            if (!SendFrame(socket, SonyWireCodec.Encode(0x0C, 0, 0x66, 0x15), "ANC GET 66 15"))
                return;

            var pending = new List<byte>();
            var recvBuffer = new byte[1024];
            for (var attempt = 0; attempt < 6; attempt++)
            {
                var count = NativeRecv(socket, recvBuffer, recvBuffer.Length, 0);
                if (count == 0)
                {
                    Console.WriteLine("Device closed RFCOMM connection.");
                    return;
                }
                if (count < 0)
                {
                    var error = WSAGetLastError();
                    if (error == 10060 || error == 10035)
                    {
                        Console.WriteLine($"No response data yet ({attempt + 1}/6; timeout).");
                        continue;
                    }
                    Console.WriteLine($"Receive failed: WSAGetLastError={error}");
                    return;
                }

                pending.AddRange(recvBuffer.Take(count));
                Console.WriteLine($"Received {count} bytes.");
                while (SonyWireCodec.TryTake(pending, out var frame, out var errorText))
                {
                    if (errorText != null)
                    {
                        Console.WriteLine($"Invalid Sony frame: {errorText}");
                        continue;
                    }
                    if (frame == null)
                        continue;

                    Console.WriteLine($"Frame: type=0x{frame.Type:X2}, seq={frame.Sequence}, payload={Convert.ToHexString(frame.Payload)}");
                    if (frame.Type == 0x01)
                    {
                        Console.WriteLine("Sony ACK received.");
                        continue;
                    }

                    if (frame.Type == 0x0C)
                    {
                        // Respond to DATA_MDR frames with the opposite 1-bit
                        // sequence ACK, as in Sony Device Center's session.
                        byte ackSeq = (byte)(1 - (frame.Sequence & 1));
                        if (!SendFrame(socket, SonyWireCodec.Encode(0x01, ackSeq), "Protocol ACK"))
                            return;
                        if (DecodeNoiseControl(frame.Payload))
                            return;
                    }
                }
            }
            Console.WriteLine("NO CONFIRMED ANC STATE. Link succeeded, but no valid 67 15 response received.");
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
