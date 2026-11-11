using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

/// <summary>
/// Opt-in Sony V2 init + read-only ANC query for WF-1000XM4 on RFCOMM channel 9.
/// Implements the verified published V2 framing from marconvcm/sony-device-center;
/// sends only the init request, the GET, and the required Sony protocol ACK.
/// It NEVER sends NCASM_SET_PARAM (0x68).
/// </summary>
internal static class SonyAncReadProbe
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct SockAddrBth
    {
        public ushort Family;
        public ulong Address;
        public Guid Service;
        public uint Channel;
    }

    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAStartup(ushort version, IntPtr data);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSACleanup();
    [DllImport("Ws2_32.dll", EntryPoint = "socket", ExactSpelling = true)]
    private static extern IntPtr NativeSocket(int family, int type, int protocol);
    [DllImport("Ws2_32.dll", EntryPoint = "connect", ExactSpelling = true)]
    private static extern int NativeConnect(IntPtr socket, ref SockAddrBth addr, int addrlen);
    [DllImport("Ws2_32.dll", EntryPoint = "send", ExactSpelling = true)]
    private static extern int NativeSend(IntPtr socket, byte[] bytes, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "recv", ExactSpelling = true)]
    private static extern int NativeRecv(IntPtr socket, byte[] bytes, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "setsockopt", ExactSpelling = true)]
    private static extern int NativeSetSockOpt(IntPtr socket, int level, int option, ref int value, int size);
    [DllImport("Ws2_32.dll", EntryPoint = "closesocket", ExactSpelling = true)]
    private static extern int NativeClose(IntPtr socket);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAGetLastError();

    private static void SendAll(IntPtr socket, byte[] bytes)
    {
        int sent = 0;
        while (sent < bytes.Length)
        {
            // Winsock send() has no offset in this P/Invoke declaration.
            var tail = bytes.Skip(sent).ToArray();
            int n = NativeSend(socket, tail, tail.Length, 0);
            if (n <= 0) throw new InvalidOperationException($"WinSock send failed: {WSAGetLastError()}");
            sent += n;
        }
    }

    private static void SendSony(IntPtr socket, byte type, byte seq, params byte[] payload)
    {
        byte[] bytes = SonyWireCodec.Encode(type, seq, payload);
        Console.WriteLine($"TX: type={type:X2}, seq={seq}, payload={Convert.ToHexString(payload)}, bytes={Convert.ToHexString(bytes)}");
        SendAll(socket, bytes);
    }

    private static bool ReadUntil(
        IntPtr socket, List<byte> stream, ref byte nextSeq,
        byte opcode, byte? subtype, TimeSpan wait)
    {
        var deadline = DateTime.UtcNow + wait;
        byte[] recvBuffer = new byte[1024];

        while (DateTime.UtcNow < deadline)
        {
            // Drain already buffered frames before another blocking recv.
            while (SonyWireCodec.TryTake(stream, out var frame, out var error))
            {
                if (error != null)
                {
                    Console.WriteLine($"RX malformed frame: {error}");
                    continue;
                }
                if (frame == null) continue;
                Console.WriteLine($"RX: type={frame.Type:X2}, seq={frame.Sequence}, payload={Convert.ToHexString(frame.Payload)}");
                if (frame.Type == 0x01) // ACK of our previous command
                {
                    if (frame.Sequence <= 1) nextSeq = frame.Sequence;
                    continue;
                }
                if (frame.Type != 0x0C) continue;

                // SonyProtocolSession acknowledges incoming DATA_MDR with opposite sequence.
                SendSony(socket, 0x01, (byte)(1 - (frame.Sequence & 1)));
                if (frame.Payload.Length >= 1 && frame.Payload[0] == opcode &&
                    (subtype == null || (frame.Payload.Length >= 2 && frame.Payload[1] == subtype)))
                {
                    if (opcode == 0x67 && subtype == 0x15) PrintAncMode(frame.Payload);
                    return true;
                }
            }
            int n = NativeRecv(socket, recvBuffer, recvBuffer.Length, 0);
            if (n == 0) { Console.WriteLine("RX: headset closed connection."); return false; }
            if (n < 0)
            {
                int error = WSAGetLastError();
                if (error == 10060) continue; // SO_RCVTIMEO elapsed
                Console.WriteLine($"RX FAILED: WSAGetLastError={error}");
                return false;
            }
            for (int i = 0; i < n; i++) stream.Add(recvBuffer[i]);
            if (stream.Count > 4096) { Console.WriteLine("RX overflow; refusing further processing."); return false; }
        }
        Console.WriteLine($"RX TIMEOUT waiting for payload {opcode:X2}" + (subtype.HasValue ? $" {subtype:X2}" : ""));
        return false;
    }

    private static void PrintAncMode(byte[] p)
    {
        // sony-device-center/NoiseControlCodec.h: WF-1000XM4 V2 layout 0x15.
        if (p.Length != 8 || p[2] != 1 || p[3] > 1 || p[4] > 1 ||
            p[6] > 1 || p[7] > 20)
        {
            Console.WriteLine("ANC response received, but its layout is unexpected. Raw payload above retained.");
            return;
        }
        var mode = p[3] == 0 ? "OFF" : p[4] == 1 ? "AMBIENT" : "ANC";
        Console.WriteLine($"ANC MODE READ: {mode}; windRaw=0x{p[5]:X2}; focusOnVoice={p[6] == 1}; ambientLevel={p[7]}");
    }

    internal static void Run(ulong address)
    {
        int addrLen = Marshal.SizeOf<SockAddrBth>();
        if (addrLen != 30) throw new InvalidOperationException($"Wrong Windows BTH address structure size: {addrLen}");
        IntPtr wsaData = Marshal.AllocHGlobal(512);
        IntPtr socket = new IntPtr(-1);
        bool started = false;
        try
        {
            int init = WSAStartup(0x0202, wsaData);
            if (init != 0) { Console.WriteLine($"WSAStartup failed: {init}"); return; }
            started = true;
            socket = NativeSocket(32, 1, 3);
            if (socket == new IntPtr(-1))
            {
                Console.WriteLine($"Native socket failed: {WSAGetLastError()}");
                return;
            }

            int timeoutMs = 750;
            if (NativeSetSockOpt(socket, 0xFFFF, 0x1006, ref timeoutMs, sizeof(int)) != 0)
            {
                Console.WriteLine($"Unable to set bounded receive timeout: {WSAGetLastError()}. Aborting.");
                return;
            }

            var destination = new SockAddrBth { Family = 32, Address = address, Service = Guid.Empty, Channel = 9 };
            Console.WriteLine("Opening RFCOMM channel 9 (Sony WF-1000XM4 specific)...");
            if (NativeConnect(socket, ref destination, addrLen) != 0)
            {
                Console.WriteLine($"NATIVE CONNECT FAILED: WSAGetLastError={WSAGetLastError()}");
                return;
            }
            Console.WriteLine("CONNECTED. Protocol test sends V2 initialization and one read-only ANC GET.");
            Thread.Sleep(350);
            byte seq = 0;
            var stream = new List<byte>();

            // ProtocolV2::initDevice(): DataMdr [00 00] -> DataMdr [01 ...]
            SendSony(socket, 0x0C, seq, 0x00, 0x00);
            if (!ReadUntil(socket, stream, ref seq, 0x01, null, TimeSpan.FromSeconds(3)))
            {
                Console.WriteLine("V2 initialization not confirmed; ANC GET not sent.");
                return;
            }

            // ProtocolV2::_queryNoiseControl(), WF-1000XM4 special layout:
            // DataMdr [66 15] -> DataMdr [67 15 ...].
            SendSony(socket, 0x0C, seq, 0x66, 0x15);
            if (!ReadUntil(socket, stream, ref seq, 0x67, 0x15, TimeSpan.FromSeconds(4)))
                Console.WriteLine("ANC read not confirmed; no SET commands were sent.");
        }
        catch (Exception e)
        {
            Console.WriteLine($"PROTOCOL ERROR: {e.GetType().Name}: {e.Message}");
        }
        finally
        {
            if (socket != new IntPtr(-1)) NativeClose(socket);
            if (started) WSACleanup();
            Marshal.FreeHGlobal(wsaData);
            Console.WriteLine("Socket closed; ANC settings were not changed intentionally.");
        }
    }
}
