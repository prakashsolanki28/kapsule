// RFBClient.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import CoreGraphics
import Foundation
import Network

/// A minimal RFB (VNC) protocol client for QEMU's loopback display. Implements the subset
/// Kapsule needs: protocol 3.8, no-auth security, raw-encoding framebuffer updates, and
/// pointer/key events. Not a general VNC client — it targets QEMU on 127.0.0.1 only.
final class RFBClient: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "io.kapsule.rfb")
    private var conn: NWConnection?

    private var width = 0
    private var height = 0
    private var pixels: [UInt32] = []   // ARGB framebuffer
    private var running = false

    /// Called with a new framebuffer image whenever an update arrives.
    var onFramebuffer: ((CGImage, CGSize) -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() {
        running = true
        // Connect to QEMU's private VNC Unix socket (owner-only directory).
        let endpoint = NWEndpoint.unix(path: socketPath)
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.conn = conn
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.handshake() }
        }
        conn.start(queue: queue)
    }

    func stop() {
        running = false
        conn?.cancel()
        conn = nil
    }

    // MARK: Handshake (RFB 3.8, no auth)

    private func handshake() {
        // Server sends "RFB 003.00x\n" (12 bytes). Read it, reply with our version.
        receive(exactly: 12) { [weak self] _ in
            guard let self else { return }
            self.send(Data("RFB 003.008\n".utf8))
            // Security: server sends count + list; we accept "None" (type 1).
            self.receive(exactly: 1) { data in
                let count = Int(data.first ?? 0)
                if count == 0 {
                    // followed by a reason string (u32 len + text) — bail
                    self.stop(); return
                }
                self.receive(exactly: count) { types in
                    // Only "None" (1) is acceptable: the Unix socket is already gated by
                    // its 0700 directory, and we don't implement VNC auth. If the server
                    // doesn't offer None, refuse rather than silently negotiating something
                    // else.
                    guard types.contains(1) else { self.stop(); return }
                    self.send(Data([1]))
                    // SecurityResult (u32). 0 = OK.
                    self.receive(exactly: 4) { result in
                        if self.beU32(result) != 0 { self.stop(); return }
                        self.clientInit()
                    }
                }
            }
        }
    }

    private func clientInit() {
        // ClientInit: shared-flag = 1 (allow others).
        send(Data([1]))
        // ServerInit: width(2) height(2) pixelFormat(16) nameLen(4) name(n).
        receive(exactly: 24) { [weak self] data in
            guard let self else { return }
            self.width = Int(self.beU16(data, 0))
            self.height = Int(self.beU16(data, 2))
            self.pixels = [UInt32](repeating: 0xFF000000, count: self.width * self.height)
            let nameLen = Int(self.beU32(Data(data[20..<24])))
            self.receive(exactly: nameLen) { _ in
                self.setPixelFormat()
                self.setEncodings()
                self.requestUpdate(incremental: false)
                self.readServerMessages()
            }
        }
    }

    // MARK: Client → server setup

    private func setPixelFormat() {
        // SetPixelFormat (type 0): request 32bpp, depth 24, little-endian, true-color,
        // BGRA layout matching our ARGB buffer on little-endian.
        var m = [UInt8](repeating: 0, count: 20)
        m[0] = 0                     // message-type
        m[4] = 32                    // bits-per-pixel
        m[5] = 24                    // depth
        m[6] = 0                     // big-endian-flag = 0
        m[7] = 1                     // true-color-flag = 1
        putBE16(&m, 8, 255)          // red-max
        putBE16(&m, 10, 255)         // green-max
        putBE16(&m, 12, 255)         // blue-max
        m[14] = 16                   // red-shift
        m[15] = 8                    // green-shift
        m[16] = 0                    // blue-shift
        send(Data(m))
    }

    private func setEncodings() {
        // SetEncodings (type 2): offer only Raw (0).
        var m = [UInt8]([2, 0])
        putBE16(&m, 2, 1)            // number-of-encodings = 1
        m += [0, 0, 0, 0]           // encoding 0 = Raw
        send(Data(m))
    }

    private func requestUpdate(incremental: Bool) {
        var m = [UInt8](repeating: 0, count: 10)
        m[0] = 3                     // FramebufferUpdateRequest
        m[1] = incremental ? 1 : 0
        putBE16(&m, 2, 0)            // x
        putBE16(&m, 4, 0)            // y
        putBE16(&m, 6, UInt16(width))
        putBE16(&m, 8, UInt16(height))
        send(Data(m))
    }

    // MARK: Server messages

    private func readServerMessages() {
        receive(exactly: 1) { [weak self] data in
            guard let self, self.running else { return }
            switch data.first {
            case 0: self.readFramebufferUpdate()
            case 1: self.skipColorMap()
            case 2: self.readServerMessages()                 // bell
            case 3: self.skipServerCutText()
            default: self.readServerMessages()
            }
        }
    }

    private func readFramebufferUpdate() {
        // 1 byte padding + u16 number-of-rectangles.
        receive(exactly: 3) { [weak self] data in
            guard let self else { return }
            let rects = Int(self.beU16(data, 1))
            self.readRects(remaining: rects)
        }
    }

    private func readRects(remaining: Int) {
        guard remaining > 0 else {
            emitFrame()
            requestUpdate(incremental: true)
            readServerMessages()
            return
        }
        // Rect header: x(2) y(2) w(2) h(2) encoding(4).
        receive(exactly: 12) { [weak self] hdr in
            guard let self else { return }
            let rx = Int(self.beU16(hdr, 0)), ry = Int(self.beU16(hdr, 2))
            let rw = Int(self.beU16(hdr, 4)), rh = Int(self.beU16(hdr, 6))
            let byteCount = rw * rh * 4   // raw, 32bpp
            guard byteCount >= 0 else { self.stop(); return }
            self.receive(exactly: byteCount) { pixelData in
                self.blit(pixelData, rx: rx, ry: ry, rw: rw, rh: rh)
                self.readRects(remaining: remaining - 1)
            }
        }
    }

    private func blit(_ data: Data, rx: Int, ry: Int, rw: Int, rh: Int) {
        guard rw > 0, rh > 0 else { return }
        data.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: UInt32.self)
            for row in 0..<rh {
                let dy = ry + row
                if dy < 0 || dy >= height { continue }
                for col in 0..<rw {
                    let dx = rx + col
                    if dx < 0 || dx >= width { continue }
                    // Our SetPixelFormat put red-shift 16, green 8, blue 0 → 0xAARRGGBB.
                    let px = src[row * rw + col] | 0xFF000000
                    pixels[dy * width + dx] = px
                }
            }
        }
    }

    private func emitFrame() {
        guard width > 0, height > 0 else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                  | CGBitmapInfo.byteOrder32Little.rawValue)
        pixels.withUnsafeMutableBytes { buf in
            guard let provider = CGDataProvider(
                dataInfo: nil, data: buf.baseAddress!, size: buf.count, releaseData: { _, _, _ in })
            else { return }
            if let cg = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: cs, bitmapInfo: bmInfo,
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent) {
                onFramebuffer?(cg, CGSize(width: width, height: height))
            }
        }
    }

    private func skipColorMap() {
        receive(exactly: 5) { [weak self] data in
            guard let self else { return }
            let n = Int(self.beU16(data, 3))
            self.receive(exactly: n * 6) { _ in self.readServerMessages() }
        }
    }
    private func skipServerCutText() {
        receive(exactly: 7) { [weak self] data in
            guard let self else { return }
            let n = Int(self.beU32(Data(data[3..<7])))
            self.receive(exactly: n) { _ in self.readServerMessages() }
        }
    }

    // MARK: Input

    func sendPointer(x: Int, y: Int, buttons: Int) {
        guard running, x >= 0, y >= 0 else { return }
        var m = [UInt8](repeating: 0, count: 6)
        m[0] = 5                              // PointerEvent
        m[1] = UInt8(buttons & 0xFF)          // button-mask
        putBE16(&m, 2, UInt16(clamping: x))
        putBE16(&m, 4, UInt16(clamping: y))
        send(Data(m))
    }

    func sendKey(_ event: NSEvent, down: Bool) {
        guard running, let sym = Self.keysym(for: event) else { return }
        var m = [UInt8](repeating: 0, count: 8)
        m[0] = 4                              // KeyEvent
        m[1] = down ? 1 : 0
        putBE32(&m, 4, sym)
        send(Data(m))
    }

    // MARK: Byte helpers & IO

    private func beU16(_ d: Data, _ o: Int) -> UInt16 {
        (UInt16(d[d.startIndex + o]) << 8) | UInt16(d[d.startIndex + o + 1])
    }
    private func beU32(_ d: Data) -> UInt32 {
        d.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private func putBE16(_ m: inout [UInt8], _ o: Int, _ v: UInt16) {
        m[o] = UInt8(v >> 8); m[o + 1] = UInt8(v & 0xFF)
    }
    private func putBE32(_ m: inout [UInt8], _ o: Int, _ v: UInt32) {
        m[o] = UInt8((v >> 24) & 0xFF); m[o + 1] = UInt8((v >> 16) & 0xFF)
        m[o + 2] = UInt8((v >> 8) & 0xFF); m[o + 3] = UInt8(v & 0xFF)
    }

    private func send(_ data: Data) {
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Receive exactly `n` bytes, buffering partial reads.
    private func receive(exactly n: Int, _ completion: @escaping (Data) -> Void) {
        guard n >= 0 else { return }
        if n == 0 { completion(Data()); return }
        var acc = Data()
        func more() {
            conn?.receive(minimumIncompleteLength: 1, maximumLength: n - acc.count) { [weak self] chunk, _, _, err in
                guard let self, self.running else { return }
                if let chunk, !chunk.isEmpty {
                    acc.append(chunk)
                    if acc.count >= n { completion(acc) } else { more() }
                } else if err != nil {
                    self.stop()
                }
            }
        }
        more()
    }
}

import AppKit
private extension RFBClient {
    /// Map an AppKit key event to an X11 keysym (what RFB expects). Covers printable ASCII
    /// and common control keys — enough to drive a guest OS.
    static func keysym(for event: NSEvent) -> UInt32? {
        // Special keys by keyCode.
        switch event.keyCode {
        case 36, 76: return 0xFF0D          // Return / keypad Enter
        case 51:     return 0xFF08          // Backspace
        case 48:     return 0xFF09          // Tab
        case 53:     return 0xFF1B          // Escape
        case 123:    return 0xFF51          // Left
        case 124:    return 0xFF53          // Right
        case 125:    return 0xFF54          // Down
        case 126:    return 0xFF52          // Up
        case 117:    return 0xFFFF          // Delete (forward)
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first else {
            return nil
        }
        let v = scalar.value
        // Printable ASCII maps 1:1 to its keysym.
        if v >= 0x20 && v <= 0x7E { return v }
        return nil
    }
}
