// Synthesizes Cookie's cute cat sound set as 16-bit mono WAV files:
// a pitch-bent meow, a rumbling purr, trills, squeaks, munches — all
// soft and small, tuned for a desktop companion. Real recordings can
// replace these any time (same file names, see Resources/Sounds).
// Usage: swift scripts/make_sounds.swift

import Foundation

let rate = 44100
let twoPi = 2.0 * Double.pi

// MARK: - DSP helpers

func smooth(_ x: Double) -> Double {
    let c = min(max(x, 0), 1)
    return c * c * (3 - 2 * c)
}

/// Additive sine voice: harmonics with decreasing amplitude, optional
/// vibrato, soft-clipped for warmth.
struct Voice {
    private var phases: [Double]
    let harmonicAmps: [Double]
    let vibratoRate: Double
    let vibratoDepth: Double

    init(harmonics: Int = 5, vibratoRate: Double = 0, vibratoDepth: Double = 0) {
        phases = [Double](repeating: 0, count: harmonics)
        harmonicAmps = (0..<harmonics).map { index in
            1.0 / pow(Double(index + 1), 1.15)
        }
        self.vibratoRate = vibratoRate
        self.vibratoDepth = vibratoDepth
    }

    mutating func sample(_ freq: Double, t: Double, rate: Int) -> Double {
        let vib = vibratoDepth * sin(twoPi * vibratoRate * t)
        var out = 0.0
        for index in 0..<phases.count {
            phases[index] += (freq * Double(index + 1) + (index == 0 ? vib : vib * 1.4)) / Double(rate)
            if phases[index] > 1 { phases[index] -= 1 }
            out += harmonicAmps[index] * sin(phases[index] * twoPi)
        }
        return tanh(out * 1.15) / 1.15
    }
}

struct Noise {
    private var last = 0.0
    private var seed: UInt64 = 0x9E3779B97F4A7C15
    mutating func raw() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: seed >> 11)) / Double(Int64.max)
    }
    /// One-pole lowpassed noise.
    mutating func lowpass(_ cutoff: Double, rate: Int) -> Double {
        let a = exp(-twoPi * cutoff / Double(rate))
        last += (1 - a) * (raw() - last)
        return last * 3.2
    }
}

func envelope(_ t: Double, duration: Double, attack: Double, release: Double) -> Double {
    if t < attack { return smooth(t / attack) }
    if t > duration - release { return smooth(max(0, (duration - t) / release)) }
    return 1
}

func render(duration: Double, peak: Double, rate: Int = 44100, generator: (Double, inout Noise) -> Double) -> [Double] {
    var noise = Noise()
    var samples = [Double](repeating: 0, count: Int(duration * Double(rate)))
    var peakSeen = 0.0
    for index in 0..<samples.count {
        let t = Double(index) / Double(rate)
        let value = generator(t, &noise)
        samples[index] = value
        peakSeen = max(peakSeen, abs(value))
    }
    if peakSeen > 0 {
        for index in 0..<samples.count {
            samples[index] = samples[index] / peakSeen * peak
        }
    }
    return samples
}

// MARK: - WAV writer

func writeWav(_ samples: [Double], to url: URL) {
    var data = Data()
    func append32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    let byteCount = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append32(36 + byteCount)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append32(16)
    append16(1)                    // PCM
    append16(1)                    // mono
    append32(UInt32(rate))
    append32(UInt32(rate * 2))     // byte rate
    append16(2)                    // block align
    append16(16)                   // bits
    data.append(contentsOf: Array("data".utf8))
    append32(byteCount)
    for sample in samples {
        let clamped = Int16(max(-32768, min(32767, Int32(sample * 32767))))
        append16(UInt16(bitPattern: clamped))
    }
    try? data.write(to: url)
}

// MARK: - Sound design

let outDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Cookie/Resources/Sounds", isDirectory: true)
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

func emit(_ name: String, _ samples: [Double]) {
    writeWav(samples, to: outDirectory.appendingPathComponent("\(name).wav"))
    print("wrote \(name).wav (\(String(format: "%.2f", Double(samples.count) / Double(rate)))s)")
}

// meow — the signature: quick rise, hang with vibrato, "ow" droop.
var meow = Voice(vibratoRate: 7.2, vibratoDepth: 26)
emit("cookie-meow", render(duration: 0.82, peak: 0.58) { t, noise in
    let p = t / 0.82
    var freq: Double
    if p < 0.2 { freq = 520 + 310 * smooth(p / 0.2) }
    else if p < 0.55 { freq = 830 - 50 * (p - 0.2) / 0.35 }
    else { freq = 780 - 350 * smooth((p - 0.55) / 0.45) }
    let breath = noise.lowpass(900, rate: rate) * 0.05
    return (meow.sample(freq, t: t, rate: rate) + breath)
        * envelope(t, duration: 0.82, attack: 0.05, release: 0.28)
})

// purr — low rumble with the characteristic 25 Hz thrust, soft breathing noise.
var purrPhase = 0.0
emit("cookie-purr", render(duration: 1.9, peak: 0.42) { t, noise in
    purrPhase += 52.0 / Double(rate)
    var carrier = 0.6 * sin(purrPhase * twoPi)
    carrier += 0.25 * sin(purrPhase * 2 * twoPi)
    carrier += 0.12 * sin(purrPhase * 3 * twoPi)
    let thrust = pow(0.5 + 0.5 * sin(twoPi * 25.0 * t), 1.4)
    let breath = noise.lowpass(420, rate: rate) * 0.35
    let env = envelope(t, duration: 1.9, attack: 0.3, release: 0.45)
    return (carrier * 0.75 + breath) * (0.35 + 0.65 * thrust) * env
})

// happy — a rising trill, "mrrp!"
var mrrp = Voice(vibratoRate: 13, vibratoDepth: 55)
emit("cookie-happy", render(duration: 0.46, peak: 0.5) { t, noise in
    let p = t / 0.46
    let freq = 620 + 240 * smooth(p) - 120 * smooth(max(0, (p - 0.75) / 0.25))
    let breath = noise.lowpass(1200, rate: rate) * 0.04
    return (mrrp.sample(freq, t: t, rate: rate) + breath)
        * envelope(t, duration: 0.46, attack: 0.03, release: 0.1)
})

// shy — tiny high mew, quieter cousin of the meow.
var shy = Voice(vibratoRate: 8.5, vibratoDepth: 18)
emit("cookie-mew", render(duration: 0.42, peak: 0.4) { t, noise in
    let p = t / 0.42
    var freq: Double
    if p < 0.3 { freq = 760 + 240 * smooth(p / 0.3) }
    else { freq = 1000 - 170 * smooth((p - 0.3) / 0.7) }
    return shy.sample(freq, t: t, rate: rate)
        * envelope(t, duration: 0.42, attack: 0.05, release: 0.16)
})

// surprise — a short startled squeak.
var squeak = Voice(vibratoRate: 11, vibratoDepth: 40)
emit("cookie-surprise", render(duration: 0.3, peak: 0.5) { t, noise in
    let p = t / 0.3
    var freq: Double
    if p < 0.4 { freq = 950 + 430 * smooth(p / 0.4) }
    else { freq = 1380 - 340 * smooth((p - 0.4) / 0.6) }
    let breath = noise.lowpass(1600, rate: rate) * 0.06
    return (squeak.sample(freq, t: t, rate: rate) + breath)
        * envelope(t, duration: 0.3, attack: 0.012, release: 0.1)
})

// notice — two quick pips when she spots the cursor.
emit("cookie-chirp", render(duration: 0.3, peak: 0.4) { t, noise in
    var freq: Double
    if t < 0.1 { freq = 860 + 320 * smooth(t / 0.1) }
    else if t < 0.15 { freq = 0 }
    else if t < 0.25 { freq = 900 + 300 * smooth((t - 0.15) / 0.1) }
    else { freq = 0 }
    let env = t < 0.12
        ? envelope(t, duration: 0.11, attack: 0.008, release: 0.04)
        : envelope(t - 0.15, duration: 0.11, attack: 0.008, release: 0.04)
    return (freq > 0 ? sin(twoPi * freq * t) : 0) * env + noise.lowpass(1400, rate: rate) * 0.02 * env
})

// eat — three crunchy munches.
emit("cookie-eat", render(duration: 0.62, peak: 0.45) { t, noise in
    var out = 0.0
    for start in [0.0, 0.21, 0.42] {
        let local = t - start
        if local >= 0, local < 0.13 {
            let crunch = noise.lowpass(2100, rate: rate) * exp(-local / 0.035)
            let thump = sin(twoPi * (95 - 40 * local / 0.13) * local) * exp(-local / 0.05) * 0.5
            out += crunch * 0.8 + thump
        }
    }
    return out * envelope(t, duration: 0.62, attack: 0.005, release: 0.08)
})

// toy — bouncy double blip.
emit("cookie-toy", render(duration: 0.34, peak: 0.42) { t, noise in
    var out = 0.0
    if t < 0.14 {
        out += tanh(sin(twoPi * (640 - 320 * (t / 0.14)) * t) * 1.4) * envelope(t, duration: 0.14, attack: 0.006, release: 0.05)
    } else if t > 0.2 {
        let local = t - 0.2
        out += tanh(sin(twoPi * (540 - 320 * (local / 0.14)) * local) * 1.4) * envelope(local, duration: 0.14, attack: 0.006, release: 0.05)
    }
    return out + noise.lowpass(1500, rate: rate) * 0.02
})

// drop — a soft landing: little thump, tiny embarrassed "oof".
var dropBlip = Voice()
emit("cookie-drop", render(duration: 0.38, peak: 0.45) { t, noise in
    var out = sin(twoPi * (150 - 85 * smooth(t / 0.16)) * t) * exp(-t / 0.07) * 0.9
    if t > 0.14, t < 0.3 {
        let local = t - 0.14
        out += dropBlip.sample(760 - 200 * (local / 0.16), t: local, rate: rate)
            * envelope(local, duration: 0.16, attack: 0.01, release: 0.06) * 0.5
    }
    let breath = noise.lowpass(600, rate: rate) * 0.03 * envelope(t, duration: 0.38, attack: 0.01, release: 0.1)
    return out + breath
})

// sleep — slow, very soft breathing rhythm for naps.
emit("cookie-sleep", render(duration: 2.4, peak: 0.2) { t, noise in
    let breath = pow(0.5 + 0.5 * sin(twoPi * (t / 1.2 - 0.25)), 1.6)
    let hum = sin(twoPi * 88 * t) * 0.25 + sin(twoPi * 132 * t) * 0.1
    let air = noise.lowpass(320, rate: rate) * 0.5
    let env = envelope(t, duration: 2.4, attack: 0.4, release: 0.5)
    return (hum + air) * breath * env
})

// welcome — a bright little two-note greeting.
var welcome = Voice(vibratoRate: 9, vibratoDepth: 20)
emit("cookie-welcome", render(duration: 0.55, peak: 0.45) { t, noise in
    var freq: Double
    if t < 0.22 { freq = 700 + 260 * smooth(t / 0.22) }
    else if t < 0.3 { freq = 0 }
    else { freq = 860 + 220 * smooth((t - 0.3) / 0.25) }
    let env = t < 0.24
        ? envelope(t, duration: 0.23, attack: 0.02, release: 0.06)
        : envelope(t - 0.3, duration: 0.25, attack: 0.02, release: 0.09)
    return (freq > 0 ? welcome.sample(freq, t: t, rate: rate) : 0) * env
})

print("done")
