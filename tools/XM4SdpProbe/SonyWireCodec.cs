using System;
using System.Collections.Generic;
using System.Linq;

internal sealed record SonyWireFrame(byte Type, byte Sequence, byte[] Payload);

/// <summary>
/// Sony Bluetooth Classic frame codec, independently implemented from
/// marconvcm/sony-device-center/libs/sony-protocol/src/FrameCodec.cpp.
/// The wire header uses TYPE (1), SEQ (1), LENGTH (4 big endian),
/// and the checksum is a wrapping byte sum of the unescaped body.
/// </summary>
internal static class SonyWireCodec
{
    internal static byte[] Encode(byte type, byte sequence, params byte[] payload)
    {
        if (payload.Length > 1024)
            throw new ArgumentOutOfRangeException(nameof(payload));

        var inner = new List<byte> { type, sequence };
        var len = (uint)payload.Length;
        inner.Add((byte)(len >> 24));
        inner.Add((byte)(len >> 16));
        inner.Add((byte)(len >> 8));
        inner.Add((byte)len);
        inner.AddRange(payload);
        byte sum = 0;
        foreach (var b in inner)
            sum = unchecked((byte)(sum + b));
        inner.Add(sum);

        var output = new List<byte> { 0x3E }; // '>'
        foreach (var b in inner)
        {
            switch (b)
            {
                case 0x3C: output.Add(0x3D); output.Add(0x2C); break;
                case 0x3D: output.Add(0x3D); output.Add(0x2D); break;
                case 0x3E: output.Add(0x3D); output.Add(0x2E); break;
                default: output.Add(b); break;
            }
        }
        output.Add(0x3C); // '<'
        return output.ToArray();
    }

    /// <summary>Consume one complete frame, if present. Returns true even when invalid (via error).</summary>
    internal static bool TryTake(List<byte> stream, out SonyWireFrame? frame, out string? error)
    {
        frame = null;
        error = null;
        var start = stream.IndexOf(0x3E);
        if (start < 0) { stream.Clear(); return false; }
        if (start > 0) stream.RemoveRange(0, start);
        var end = stream.IndexOf(0x3C, 1);
        if (end < 0)
        {
            if (stream.Count > 4096) { stream.Clear(); error = "Oversize unterminated frame"; return true; }
            return false;
        }
        var wireBody = stream.GetRange(1, end - 1);
        stream.RemoveRange(0, end + 1);
        var body = new List<byte>(wireBody.Count);
        for (int i = 0; i < wireBody.Count; i++)
        {
            var b = wireBody[i];
            if (b == 0x3D)
            {
                if (++i >= wireBody.Count) { error = "Truncated escape"; return true; }
                b = wireBody[i] switch
                {
                    0x2C => (byte)0x3C,
                    0x2D => (byte)0x3D,
                    0x2E => (byte)0x3E,
                    _ => (byte)0
                };
                if (b == 0) { error = "Unknown escape"; return true; }
            }
            body.Add(b);
        }
        if (body.Count < 7) { error = "Frame body shorter than 7 bytes"; return true; }
        uint len = ((uint)body[2] << 24) | ((uint)body[3] << 16) | ((uint)body[4] << 8) | body[5];
        if (len > 1024 || (ulong)body.Count != 7UL + len)
        {
            error = $"Unexpected payload size {len} in {body.Count}-byte frame body";
            return true;
        }
        byte sum = 0;
        for (int i = 0; i < body.Count - 1; i++)
            sum = unchecked((byte)(sum + body[i]));
        if (sum != body[^1])
        {
            error = $"Checksum mismatch (expected {sum:X2}, received {body[^1]:X2})";
            return true;
        }
        frame = new SonyWireFrame(body[0], body[1], body.Skip(6).Take((int)len).ToArray());
        return true;
    }

    internal static void SelfTest()
    {
        var getAnc = Encode(0x0C, 0, 0x66, 0x15);
        var expected = new byte[] { 0x3E, 0x0C, 0, 0, 0, 0, 2, 0x66, 0x15, 0x89, 0x3C };
        if (!getAnc.SequenceEqual(expected))
            throw new Exception("ANC GET wire vector mismatch.");
        var cases = new byte[] { 0x3C, 0x3D, 0x3E, 0, 0x15 };
        var frameBytes = Encode(0x0C, 1, cases);
        var stream = new List<byte>(frameBytes);
        if (!TryTake(stream, out var parsed, out var error) ||
            error != null || parsed == null || parsed.Type != 0x0C ||
            parsed.Sequence != 1 || !parsed.Payload.SequenceEqual(cases) || stream.Count != 0)
            throw new Exception($"Frame round trip failed: {error}");
        var split = new List<byte>(frameBytes.Take(3));
        if (TryTake(split, out _, out _)) throw new Exception("Partial frame parsed as complete.");
        split.AddRange(frameBytes.Skip(3));
        if (!TryTake(split, out parsed, out error) || error != null || parsed == null)
            throw new Exception("Fragmented frame parsing failed.");
        Console.WriteLine("SELF-TEST PASS: big-endian length, checksum, escaping, fragmentation, ANC GET frame.");
    }
}
