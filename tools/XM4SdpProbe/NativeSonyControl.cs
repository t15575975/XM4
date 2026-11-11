using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

/// <summary>
/// Native Sony V2 ANC controller for WF-1000XM4, explicitly enabled by CLI flag.
/// Uses RFCOMM channel 9 (validated on user's Windows PC), reads current state,
/// preserves raw wind/voice/ambient-level parameters, sets one requested mode,
/// then reads back the actual state before reporting success.
/// </summary>
internal static class NativeSonyControl
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct SockAddrBth
    {
        public ushort Family;
        public ulong BluetoothAddress;
        public Guid Service;
        public uint Port;
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
    private static extern int NativeSend(IntPtr socket, byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "recv", ExactSpelling = true)]
    private static extern int NativeRecv(IntPtr socket, [Out] byte[] data, int length, int flags);
    [DllImport("Ws2_32.dll", EntryPoint = "setsockopt", ExactSpelling = true)]
    private static extern int NativeSetSocketOption(IntPtr socket, int level, int name, ref int value, int valueLength);
    [DllImport("Ws2_32.dll", EntryPoint = "closesocket", ExactSpelling = true)]
    private static extern int NativeClose(IntPtr socket);
    [DllImport("Ws2_32.dll", ExactSpelling = true)]
    private static extern int WSAGetLastError();

    private static bool SendSony(IntPtr socket, byte type, byte sequence, byte[] payload)
    {
        var packet = SonyWireCodec.Encode(type, sequence, payload);
        int sent = 0;
        while (sent < packet.Length)
        {
            var remaining = packet.Skip(sent).ToArray();
            int n = NativeSend(socket, remaining, remaining.Length, 0);
            if (n <= 0)
            {
                Console.WriteLine($"TX failed: WSAGetLastError={WSAGetLastError()}");
                return false;
            }
            sent += n;
        }
        Console.WriteLine($"TX: type={type:X2}, seq={sequence}, payload={Convert.ToHexString(payload)}, wire={Convert.ToHexString(packet)}");
        return true;
    }

    private static bool ReceiveUntil(
        IntPtr socket,
        List<byte> buffer,
        ref byte sequence,
        Func<SonyWireFrame, bool> isWanted,
        TimeSpan timeout,
        out SonyWireFrame? matched)
    {
        matched = null;
        var recvBuf = new byte[1024];
        var expires = DateTime.UtcNow.Add(timeout);
        while (DateTime.UtcNow < expires)
        {
            while (SonyWireCodec.TryTake(buffer, out var frame, out var error))
            {
                if (error != null)
                {
                    Console.WriteLine($"Invalid Sony response: {error}");
                    continue;
                }
                if (frame == null) continue;
                Console.WriteLine($"RX: type={frame.Type:X2}, seq={frame.Sequence}, payload={Convert.ToHexString(frame.Payload)}");

                if (frame.Type == 0x01 && frame.Sequence <= 1)
                    sequence = frame.Sequence;

                if (frame.Type == 0x0C)
                {
                    // SonyProtocolSession acknowledges each inbound DATA_MDR
                    // frame with the opposite 1-bit sequence number.
                    var ackSequence = (byte)(1 - (frame.Sequence & 1));
                    if (!SendSony(socket, 0x01, ackSequence, Array.Empty<byte>()))
                    {
                        Console.WriteLine("Protocol ACK could not be sent.");
                        return false;
                    }
                }

                if (isWanted(frame))
                {
                    matched = frame;
                    return true;
                }
            }

            int n = NativeRecv(socket, recvBuf, recvBuf.Length, 0);
            if (n == 0)
            {
                Console.WriteLine("Remote closed the RFCOMM connection.");
                return false;
            }
            if (n < 0)
            {
                int code = WSAGetLastError();
                if (code == 10060 || code == 10035)
                    continue; // receive timeout, not fatal
                Console.WriteLine($"RX failed: WSAGetLastError={code}");
                return false;
            }
            buffer.AddRange(recvBuf.Take(n));
            if (buffer.Count > 4096)
            {
                Console.WriteLine("RX exceeded safe buffer limit.");
                return false;
            }
        }
        Console.WriteLine("Timeout waiting for matching Sony frame.");
        return false;
    }

    private static NoiseState? ReadMode(IntPtr socket, List<byte> buffer, ref byte sequence)
    {
        var sentSequence = sequence;
        if (!SendSony(socket, 0x0C, sentSequence, new byte[] { 0x66, 0x15 }))
            return null;
        sequence = (byte)(1 - (sentSequence & 1));

        var result = ReceiveUntil(socket, buffer, ref sequence,
            f => f.Type == 0x0C && NoiseState.TryDecode(f.Payload, out _),
            TimeSpan.FromSeconds(6), out var matched);
        if (!result || matched == null || !NoiseState.TryDecode(matched.Payload, out var state))
            return null;

        Console.WriteLine($"ANC STATE READ: {state!.Mode}; wind=0x{state.Wind:X2}, voice={state.Voice}, level={state.Level}");
        return state;
    }

    internal static void Set(ulong address, NoiseMode? desiredMode)
    {
        const string source = "Sony Device Center, WF-1000XM4 V2 0x15 layout";
        Console.WriteLine($"Source: {source}");
        Console.WriteLine(desiredMode is null
            ? "Manual three-mode cycle: ANC -> AMBIENT -> OFF -> ANC."
            : $"Explicit mode requested: {desiredMode}.");
        Console.WriteLine("Only documented Sony V2 ANC frames are used; no arbitrary GATT writes.");

        var sockaddrLength = Marshal.SizeOf<SockAddrBth>();
        if (sockaddrLength != 30)
            throw new InvalidOperationException($"Unexpected SOCKADDR_BTH size {sockaddrLength}; refusing writes.");

        IntPtr wsa = Marshal.AllocHGlobal(512);
        IntPtr socket = new IntPtr(-1);
        bool started = false;
        try
        {
            var start = WSAStartup(0x0202, wsa);
            if (start != 0) { Console.WriteLine($"WSAStartup failed: {start}"); return; }
            started = true;
            socket = NativeSocket(32, 1, 3);
            if (socket == new IntPtr(-1))
            {
                Console.WriteLine($"Bluetooth socket creation failed: {WSAGetLastError()}");
                return;
            }

            int receiveTimeout = 1200;
            int sendTimeout = 1500;
            if (NativeSetSocketOption(socket, 0xFFFF, 0x1006, ref receiveTimeout, sizeof(int)) != 0 ||
                NativeSetSocketOption(socket, 0xFFFF, 0x1005, ref sendTimeout, sizeof(int)) != 0)
            {
                Console.WriteLine($"Setting socket timeout failed: {WSAGetLastError()}");
                return;
            }

            var remote = new SockAddrBth { Family = 32, BluetoothAddress = address, Service = Guid.Empty, Port = 9 };
            Console.WriteLine("Connecting to confirmed RFCOMM channel 9...");
            if (NativeConnect(socket, ref remote, sockaddrLength) != 0)
            {
                Console.WriteLine($"Connection failed: WSAGetLastError={WSAGetLastError()}");
                return;
            }
            Thread.Sleep(500);
            byte sequence = 0;
            var buffer = new List<byte>();

            Console.WriteLine("Reading present mode and wind/voice/level parameters first...");
            var before = ReadMode(socket, buffer, ref sequence);
            if (before == null)
            {
                Console.WriteLine("ABORTED: no valid 67 15 response. No ANC SET sent.");
                return;
            }

            var target = desiredMode ?? NoiseState.Next(before.Mode);
            if (before.Mode == target)
            {
                Console.WriteLine($"ALREADY SET: {target}. No changes sent.");
                return;
            }

            var payload = before.BuildSet(target);
            Console.WriteLine($"Requesting: {before.Mode} -> {target}; preserving wind=0x{before.Wind:X2} voice={before.Voice} level={payload[7]}.");
            Console.WriteLine($"ANC SET payload: {Convert.ToHexString(payload)}");

            byte setSeq = sequence;
            if (!SendSony(socket, 0x0C, setSeq, payload))
            {
                Console.WriteLine("SET NOT CONFIRMED: failed while transmitting.");
                return;
            }
            sequence = (byte)(1 - (setSeq & 1));

            // Try to receive the SET acknowledgement; device may also send notifications.
            var gotAck = ReceiveUntil(socket, buffer, ref sequence,
                f => f.Type == 0x01,
                TimeSpan.FromSeconds(2), out _);
            Console.WriteLine(gotAck ? "SET ACK received." : "SET ACK not confirmed; checking actual status instead.");

            // Do not report success based solely on ACK. Query the actual state.
            var after = ReadMode(socket, buffer, ref sequence);
            if (after == null)
            {
                Console.WriteLine("SET UNVERIFIED: no valid readback. No retry performed.");
                return;
            }
            if (after.Mode != target)
            {
                Console.WriteLine($"SET NOT VERIFIED: expected {target}, actual {after.Mode}. No retry performed.");
                return;
            }
            Console.WriteLine($"MODE CHANGE VERIFIED: {before.Mode} -> {after.Mode}");
        }
        catch (Exception e)
        {
            Console.WriteLine($"CONTROL ERROR: {e.GetType().Name}: {e.Message}");
        }
        finally
        {
            if (socket != new IntPtr(-1)) NativeClose(socket);
            if (started) WSACleanup();
            Marshal.FreeHGlobal(wsa);
            Console.WriteLine("RFCOMM socket closed.");
        }
    }
}
