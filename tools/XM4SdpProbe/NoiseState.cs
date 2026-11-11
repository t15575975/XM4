using System;
using System.Linq;

internal enum NoiseMode
{
    Anc,
    Ambient,
    Off
}

internal sealed record NoiseState(NoiseMode Mode, byte Wind, byte Voice, byte Level)
{
    internal static bool TryDecode(byte[] payload, out NoiseState? state)
    {
        state = null;
        // WF-1000XM4 V2 0x15:
        // [67 15 01 enable ambient wind voice level]
        if (payload.Length != 8 || payload[0] != 0x67 || payload[1] != 0x15 ||
            payload[2] != 0x01 || payload[3] > 1 || payload[4] > 1 ||
            payload[6] > 1 || payload[7] > 20)
            return false;

        var mode = payload[3] == 0 ? NoiseMode.Off :
                   payload[4] == 1 ? NoiseMode.Ambient : NoiseMode.Anc;
        state = new NoiseState(mode, payload[5], payload[6], payload[7]);
        return true;
    }

    internal static NoiseMode Next(NoiseMode mode) => mode switch
    {
        NoiseMode.Anc => NoiseMode.Ambient,
        NoiseMode.Ambient => NoiseMode.Off,
        NoiseMode.Off => NoiseMode.Anc,
        _ => throw new ArgumentOutOfRangeException(nameof(mode))
    };

    internal byte[] BuildSet(NoiseMode target)
    {
        // Sony Device Center ProtocolV2::setNoiseControl() / Wf1000Xm4 layout.
        // MUST read the present state and preserve the raw wind byte.
        // Preserve voice/level too. Level 0 cannot be set for Ambient.
        byte enable = target == NoiseMode.Off ? (byte)0 : (byte)1;
        byte ambient = target == NoiseMode.Ambient ? (byte)1 : (byte)0;
        byte safeLevel = Level > 0 ? Level : (byte)1;
        return new byte[] { 0x68, 0x15, 0x01, enable, ambient, Wind, Voice, safeLevel };
    }

    internal static void SelfTest()
    {
        var actual = new byte[] { 0x67, 0x15, 1, 1, 1, 2, 0, 20 };
        if (!TryDecode(actual, out var current) || current == null ||
            current.Mode != NoiseMode.Ambient || current.Wind != 2 ||
            current.Voice != 0 || current.Level != 20)
            throw new Exception("Failed to decode real ambient status response.");

        var expectedAnc = new byte[] { 0x68, 0x15, 1, 1, 0, 2, 0, 20 };
        var expectedAmbient = new byte[] { 0x68, 0x15, 1, 1, 1, 2, 0, 20 };
        var expectedOff = new byte[] { 0x68, 0x15, 1, 0, 0, 2, 0, 20 };
        if (!current.BuildSet(NoiseMode.Anc).SequenceEqual(expectedAnc) ||
            !current.BuildSet(NoiseMode.Ambient).SequenceEqual(expectedAmbient) ||
            !current.BuildSet(NoiseMode.Off).SequenceEqual(expectedOff))
            throw new Exception("XM4 ANC SET command payload mismatch.");

        if (Next(NoiseMode.Anc) != NoiseMode.Ambient ||
            Next(NoiseMode.Ambient) != NoiseMode.Off ||
            Next(NoiseMode.Off) != NoiseMode.Anc)
            throw new Exception("ANC -> Ambient -> Off cycle mismatch.");

        if (TryDecode(new byte[] { 0x67, 0x17, 1, 1, 1, 2, 0, 20 }, out _) ||
            TryDecode(new byte[] { 0x67, 0x15, 1, 1, 1, 2, 0, 21 }, out _))
            throw new Exception("Unsafe or unrelated Sony ANC response accepted.");
        var preserved = new NoiseState(NoiseMode.Off, 0x05, 1, 10);
        if (preserved.BuildSet(NoiseMode.Ambient)[5] != 0x05 ||
            preserved.BuildSet(NoiseMode.Ambient)[6] != 1 ||
            preserved.BuildSet(NoiseMode.Ambient)[7] != 10)
            throw new Exception("Existing wind/voice/level values were not preserved.");

        Console.WriteLine("SELF-TEST PASS: real WF-1000XM4 status, three mode SET vectors, cycle, wind preservation, invalid frames.");
    }
}
