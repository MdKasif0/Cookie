using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Cookie.Windows.Core.Imaging;

/// <summary>One picture to put in a GIF: straight (not premultiplied) RGBA, row by row from the top left.</summary>
public sealed record RgbaFrame(int Width, int Height, byte[] Rgba);

/// <summary>
/// Writes animated GIF89a files. WPF's own GIF encoder cannot animate, so this builds the file directly: a
/// median-cut palette shared by every frame, Floyd-Steinberg dithering, variable-width LZW compression, and an
/// endless loop. GIF can only make a pixel fully clear or fully solid, so alpha is thresholded at half, and
/// the soft edge of partly clear pixels is blended against a matte color close to the one behind it.
/// </summary>
public static class GifEncoder
{
    private const int AlphaThreshold = 128;
    private const int TransparentIndex = 255;

    public static byte[] Encode(IReadOnlyList<RgbaFrame> frames, int delayCentiseconds, bool loopForever = true,
        (byte R, byte G, byte B)? matte = null)
    {
        if (frames.Count == 0) throw new ArgumentException("At least one frame is required.", nameof(frames));
        int width = frames[0].Width;
        int height = frames[0].Height;
        if (width <= 0 || height <= 0 || width > ushort.MaxValue || height > ushort.MaxValue)
        {
            throw new ArgumentException("Frame size is out of range for a GIF.");
        }
        foreach (var frame in frames)
        {
            if (frame.Width != width || frame.Height != height || frame.Rgba.Length != width * height * 4)
            {
                throw new ArgumentException("Every frame must be the same size.");
            }
        }

        var background = matte ?? ((byte)250, (byte)238, (byte)225);
        bool hasTransparency = frames.Any(frame => HasClearPixels(frame.Rgba));
        var palette = BuildPalette(frames, background, hasTransparency ? 255 : 256);

        using var output = new MemoryStream();
        WriteHeader(output, width, height, palette, hasTransparency);
        if (loopForever) WriteLoopBlock(output);

        var lookup = new short[1 << 15];
        for (int i = 0; i < frames.Count; i++)
        {
            Array.Fill(lookup, (short)-1);
            var indices = Quantize(frames[i], palette, background, lookup);
            WriteFrame(output, width, height, indices, delayCentiseconds, hasTransparency);
        }

        output.WriteByte(0x3B);
        return output.ToArray();
    }

    private static bool HasClearPixels(byte[] rgba)
    {
        for (int i = 3; i < rgba.Length; i += 4)
        {
            if (rgba[i] < AlphaThreshold) return true;
        }
        return false;
    }

    private static (int R, int G, int B) Blend(byte[] rgba, int offset, (byte R, byte G, byte B) matte)
    {
        int alpha = rgba[offset + 3];
        if (alpha >= 255) return (rgba[offset], rgba[offset + 1], rgba[offset + 2]);
        return (
            (rgba[offset] * alpha + matte.R * (255 - alpha) + 127) / 255,
            (rgba[offset + 1] * alpha + matte.G * (255 - alpha) + 127) / 255,
            (rgba[offset + 2] * alpha + matte.B * (255 - alpha) + 127) / 255);
    }

    private static int Key(int r, int g, int b) => ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);

    // --- Palette ----------------------------------------------------------------

    private sealed class Box
    {
        public List<int> Colors = new();
        public long Count;

        public (int Channel, int Range) WidestChannel(int[] histogram)
        {
            int minR = 31, maxR = 0, minG = 31, maxG = 0, minB = 31, maxB = 0;
            foreach (int key in Colors)
            {
                int r = key >> 10, g = (key >> 5) & 31, b = key & 31;
                minR = Math.Min(minR, r); maxR = Math.Max(maxR, r);
                minG = Math.Min(minG, g); maxG = Math.Max(maxG, g);
                minB = Math.Min(minB, b); maxB = Math.Max(maxB, b);
            }
            int rangeR = maxR - minR, rangeG = maxG - minG, rangeB = maxB - minB;
            // Green weighs more because the eye is most sensitive to it.
            if (rangeG * 2 >= rangeR * 2 && rangeG * 2 >= rangeB * 2 - 1 && rangeG >= rangeR && rangeG >= rangeB) return (1, rangeG);
            return rangeR >= rangeB ? (0, rangeR) : (2, rangeB);
        }
    }

    private static List<(byte R, byte G, byte B)> BuildPalette(IReadOnlyList<RgbaFrame> frames, (byte R, byte G, byte B) matte, int size)
    {
        var histogram = new int[1 << 15];
        foreach (var frame in frames)
        {
            for (int offset = 0; offset < frame.Rgba.Length; offset += 4)
            {
                if (frame.Rgba[offset + 3] < AlphaThreshold) continue;
                var (r, g, b) = Blend(frame.Rgba, offset, matte);
                histogram[Key(r, g, b)]++;
            }
        }

        var first = new Box();
        for (int key = 0; key < histogram.Length; key++)
        {
            if (histogram[key] > 0)
            {
                first.Colors.Add(key);
                first.Count += histogram[key];
            }
        }

        var boxes = new List<Box> { first };
        while (boxes.Count < size)
        {
            // Split the most populous box that still has more than one color.
            var candidate = boxes.Where(box => box.Colors.Count > 1).OrderByDescending(box => box.Count).FirstOrDefault();
            if (candidate == null) break;

            var (channel, _) = candidate.WidestChannel(histogram);
            int Component(int key) => channel switch { 0 => key >> 10, 1 => (key >> 5) & 31, _ => key & 31 };
            candidate.Colors.Sort((a, b) => Component(a).CompareTo(Component(b)));

            long half = candidate.Count / 2, running = 0;
            int split = 0;
            for (; split < candidate.Colors.Count - 1; split++)
            {
                running += histogram[candidate.Colors[split]];
                if (running >= half) { split++; break; }
            }
            split = Math.Clamp(split, 1, candidate.Colors.Count - 1);

            var upper = new Box { Colors = candidate.Colors.GetRange(split, candidate.Colors.Count - split) };
            upper.Count = upper.Colors.Sum(key => (long)histogram[key]);
            candidate.Colors = candidate.Colors.GetRange(0, split);
            candidate.Count = candidate.Colors.Sum(key => (long)histogram[key]);
            boxes.Add(upper);
        }

        var palette = new List<(byte, byte, byte)>();
        foreach (var box in boxes)
        {
            long r = 0, g = 0, b = 0, total = 0;
            foreach (int key in box.Colors)
            {
                long weight = histogram[key];
                r += ((key >> 10) * 8 + 4) * weight;
                g += (((key >> 5) & 31) * 8 + 4) * weight;
                b += ((key & 31) * 8 + 4) * weight;
                total += weight;
            }
            if (total == 0) total = 1;
            palette.Add(((byte)(r / total), (byte)(g / total), (byte)(b / total)));
        }
        if (palette.Count == 0) palette.Add(matte);
        return palette;
    }

    // --- Mapping pixels to the palette --------------------------------------------

    private static byte[] Quantize(RgbaFrame frame, List<(byte R, byte G, byte B)> palette, (byte R, byte G, byte B) matte, short[] lookup)
    {
        int width = frame.Width, height = frame.Height;
        var indices = new byte[width * height];
        var errorCurrent = new float[(width + 2) * 3];
        var errorNext = new float[(width + 2) * 3];

        for (int y = 0; y < height; y++)
        {
            Array.Clear(errorNext, 0, errorNext.Length);
            for (int x = 0; x < width; x++)
            {
                int offset = (y * width + x) * 4;
                int e = (x + 1) * 3;
                if (frame.Rgba[offset + 3] < AlphaThreshold)
                {
                    indices[y * width + x] = TransparentIndex;
                    continue;
                }

                var (r, g, b) = Blend(frame.Rgba, offset, matte);
                int adjustedR = Math.Clamp((int)Math.Round(r + errorCurrent[e]), 0, 255);
                int adjustedG = Math.Clamp((int)Math.Round(g + errorCurrent[e + 1]), 0, 255);
                int adjustedB = Math.Clamp((int)Math.Round(b + errorCurrent[e + 2]), 0, 255);

                int key = Key(adjustedR, adjustedG, adjustedB);
                int index = lookup[key];
                if (index < 0)
                {
                    index = Nearest(palette, adjustedR, adjustedG, adjustedB);
                    lookup[key] = (short)index;
                }
                indices[y * width + x] = (byte)index;

                // Spread what the palette couldn't show onto the neighbors still to come.
                float errR = adjustedR - palette[index].R;
                float errG = adjustedG - palette[index].G;
                float errB = adjustedB - palette[index].B;
                Spread(errorCurrent, e + 3, errR, errG, errB, 7f / 16f);
                Spread(errorNext, e - 3, errR, errG, errB, 3f / 16f);
                Spread(errorNext, e, errR, errG, errB, 5f / 16f);
                Spread(errorNext, e + 3, errR, errG, errB, 1f / 16f);
            }
            (errorCurrent, errorNext) = (errorNext, errorCurrent);
        }
        return indices;
    }

    private static void Spread(float[] buffer, int at, float r, float g, float b, float share)
    {
        if (at < 0 || at + 2 >= buffer.Length) return;
        buffer[at] += r * share;
        buffer[at + 1] += g * share;
        buffer[at + 2] += b * share;
    }

    private static int Nearest(List<(byte R, byte G, byte B)> palette, int r, int g, int b)
    {
        int best = 0, bestDistance = int.MaxValue;
        for (int i = 0; i < palette.Count; i++)
        {
            int dr = r - palette[i].R, dg = g - palette[i].G, db = b - palette[i].B;
            int distance = dr * dr * 3 + dg * dg * 4 + db * db * 2;
            if (distance < bestDistance)
            {
                bestDistance = distance;
                best = i;
            }
        }
        return best;
    }

    // --- File structure ---------------------------------------------------------

    private static void WriteHeader(Stream output, int width, int height, List<(byte R, byte G, byte B)> palette, bool hasTransparency)
    {
        output.Write("GIF89a"u8);
        WriteShort(output, width);
        WriteShort(output, height);
        output.WriteByte(0xF7); // global color table, 8 bits per color, 256 entries
        output.WriteByte(0);    // background color index
        output.WriteByte(0);    // pixel aspect ratio

        for (int i = 0; i < 256; i++)
        {
            var color = i < palette.Count ? palette[i] : ((byte)0, (byte)0, (byte)0);
            output.WriteByte(color.Item1);
            output.WriteByte(color.Item2);
            output.WriteByte(color.Item3);
        }
    }

    private static void WriteLoopBlock(Stream output)
    {
        output.WriteByte(0x21);
        output.WriteByte(0xFF);
        output.WriteByte(11);
        output.Write("NETSCAPE2.0"u8);
        output.WriteByte(3);
        output.WriteByte(1);
        WriteShort(output, 0); // zero loops means forever
        output.WriteByte(0);
    }

    private static void WriteFrame(Stream output, int width, int height, byte[] indices, int delay, bool hasTransparency)
    {
        output.WriteByte(0x21);
        output.WriteByte(0xF9);
        output.WriteByte(4);
        // Disposal method 2 clears to the background between frames, so transparent areas never show the last frame.
        output.WriteByte((byte)((2 << 2) | (hasTransparency ? 1 : 0)));
        WriteShort(output, Math.Max(2, delay));
        output.WriteByte(hasTransparency ? (byte)TransparentIndex : (byte)0);
        output.WriteByte(0);

        output.WriteByte(0x2C);
        WriteShort(output, 0);
        WriteShort(output, 0);
        WriteShort(output, width);
        WriteShort(output, height);
        output.WriteByte(0);

        output.WriteByte(8); // minimum LZW code size
        WriteSubBlocks(output, LzwCompress(indices));
        output.WriteByte(0);
    }

    private static void WriteShort(Stream output, int value)
    {
        output.WriteByte((byte)(value & 0xFF));
        output.WriteByte((byte)((value >> 8) & 0xFF));
    }

    private static void WriteSubBlocks(Stream output, byte[] data)
    {
        for (int offset = 0; offset < data.Length; offset += 255)
        {
            int length = Math.Min(255, data.Length - offset);
            output.WriteByte((byte)length);
            output.Write(data, offset, length);
        }
    }

    // --- LZW ----------------------------------------------------------------------

    /// <summary>Variable-width LZW with 8-bit pixels, packed least significant bit first.</summary>
    public static byte[] LzwCompress(byte[] pixels)
    {
        const int MinCodeSize = 8;
        const int ClearCode = 1 << MinCodeSize;
        const int EndCode = ClearCode + 1;
        const int MaxCodes = 4096;

        var result = new MemoryStream();
        int bitBuffer = 0, bitCount = 0;
        int codeSize = MinCodeSize + 1;
        int nextCode = EndCode + 1;

        void Write(int code)
        {
            bitBuffer |= code << bitCount;
            bitCount += codeSize;
            while (bitCount >= 8)
            {
                result.WriteByte((byte)(bitBuffer & 0xFF));
                bitBuffer >>= 8;
                bitCount -= 8;
            }
        }

        // After a code is written the width grows once the table has outgrown it.
        void GrowIfNeeded()
        {
            if (nextCode > (1 << codeSize) - 1 && codeSize < 12) codeSize++;
        }

        var dictionary = new Dictionary<int, int>();
        Write(ClearCode);

        int prefix = pixels[0];
        for (int i = 1; i < pixels.Length; i++)
        {
            int next = pixels[i];
            int key = (prefix << 8) | next;
            if (dictionary.TryGetValue(key, out int existing))
            {
                prefix = existing;
                continue;
            }

            Write(prefix);
            GrowIfNeeded();
            if (nextCode < MaxCodes)
            {
                dictionary[key] = nextCode++;
            }
            else
            {
                Write(ClearCode);
                dictionary.Clear();
                nextCode = EndCode + 1;
                codeSize = MinCodeSize + 1;
            }
            prefix = next;
        }

        Write(prefix);
        GrowIfNeeded();
        Write(EndCode);
        if (bitCount > 0) result.WriteByte((byte)(bitBuffer & 0xFF));
        return result.ToArray();
    }
}
