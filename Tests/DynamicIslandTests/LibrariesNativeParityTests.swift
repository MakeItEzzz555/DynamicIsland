import XCTest
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import enum LibrariesNative.OrbState
import enum LibrariesNative.OrbSize
import func LibrariesNative.resolvePreset
@testable import DynamicIsland

/// Development-only review harness. Frozen engine time and fixed seeds make
/// captures reproducible. These images are fixture evidence, never live agents.
@MainActor
final class LibrariesNativeParityTests: XCTestCase {
    func testRenderReferenceParityReview() throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIBRARIES_PARITY_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_LIBRARIES_PARITY_DIR for the native fidelity review grids.")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            let theme = scheme == .dark ? "dark" : "light"
            let orbGrid = VStack(spacing: 16) {
                ForEach([0.6, 1.7, 3.2], id: \.self) { instant in
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(AgentOrbVisualState.allCases) { state in
                            VStack(spacing: 6) {
                                AgentOrbView(state: state, size: 64, frozenTime: instant)
                                AgentOrbView(state: state, size: 20, frozenTime: instant)
                                Text(state.displayName).font(.system(size: 9))
                            }
                        }
                    }
                }
            }.padding(24)
            try save(orbGrid, scheme: scheme, to: directory.appendingPathComponent("orbs-\(theme).png"))

            for material in BotAvatarShading.allCases {
                let avatarGrid = VStack(spacing: 10) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 12) {
                            ForEach(Array(BotAvatarType.allCases[(row*6)..<(row*6+6)])) { type in
                                VStack(spacing: 8) {
                                    ForEach([AgentState.idle, .working, .completed], id: \.self) { state in
                                        BotAvatarView(sessionID: nil, configuration: self.avatar(material: material, size: 64), state: state, overrideType: type, paused: true, frozenTime: 1.7).frame(width: 92, height: 96)
                                    }
                                    BotAvatarView(sessionID: nil, configuration: self.avatar(material: material, size: 20), state: .working, overrideType: type, compact: true, frozenTime: 1.7)
                                    Text(type.displayName).font(.system(size: 10))
                                }.frame(width: 92)
                            }
                        }
                    }
                }.padding(24)
                try save(avatarGrid, scheme: scheme, to: directory.appendingPathComponent("avatars-\(material.rawValue)-\(theme).png"))
            }
            let poses = VStack(spacing: 10) {
                ForEach([0.18, 0.5, 0.82], id: \.self) { seed in
                    HStack(spacing: 14) {
                        ForEach([BotAvatarFace.eyes, .mouth]) { face in
                            ForEach([0.3, 0.6, 1.0, 1.7, 2.5], id: \.self) { instant in
                                VStack {
                                    BotAvatarView(sessionID: nil, configuration: self.seeded(seed, face), state: .working, overrideType: .clover, frozenTime: instant).frame(width: 90, height: 100)
                                    BotAvatarView(sessionID: nil, configuration: self.seeded(seed, face), state: .working, overrideType: .clover, compact: true, frozenTime: instant)
                                }
                            }
                        }
                    }
                }
            }.padding(24)
            try save(poses, scheme: scheme, to: directory.appendingPathComponent("working-seeds-faces-\(theme).png"))
            let heldPoses = HStack(spacing: 24) {
                ForEach([-40.0, 0, 40], id: \.self) { yaw in
                    BotAvatarView(sessionID: nil, configuration: self.held(yaw), state: .idle, overrideType: .cat, frozenTime: 0.6).frame(width: 100, height: 120)
                }
            }.padding(24)
            try save(heldPoses, scheme: scheme, to: directory.appendingPathComponent("paused-poses-\(theme).png"))
            let accessories = HStack(spacing: 20) {
                ForEach(BotAvatarHat.allCases) { hat in
                    VStack(spacing: 12) {
                        ForEach(BotAvatarGlasses.allCases) { glasses in
                            BotAvatarView(sessionID: nil, configuration: self.decorated(hat, glasses), state: .idle, overrideType: .cat, paused: true, frozenTime: 0.6).frame(width: 120, height: 120)
                        }
                        Text(hat.displayName).font(.caption)
                    }
                }
            }.padding(24)
            try save(accessories, scheme: scheme, to: directory.appendingPathComponent("accessories-\(theme).png"))
        }
        // An animation contact sheet alone cannot show the reference rhythm.
        // This fixed-clock GIF supplements the PNGs; it remains fixture evidence.
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(directory.appendingPathComponent("native-motion.gif") as CFURL, UTType.gif.identifier as CFString, 45, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<45 {
            let clock = Double(frame)/15
            let motion = VStack(spacing: 24) {
                HStack(spacing: 18) {
                    ForEach(AgentOrbVisualState.allCases) { state in
                        AgentOrbView(state: state, size: 20, frozenTime: clock*resolvePreset(OrbState(rawValue: state.rawValue)!, .px20).speed)
                    }
                }
                HStack(spacing: 24) {
                    ForEach([AgentState.idle, .working, .completed], id: \.self) { state in
                        BotAvatarView(sessionID: nil, configuration: self.seeded(0.32, .mouth), state: state, overrideType: .cat, frozenTime: clock).frame(width: 100, height: 120)
                    }
                }
            }.padding(20).background(Color.black).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: motion); renderer.scale = 2
            CGImageDestinationAddImage(destination, try XCTUnwrap(renderer.cgImage), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0/15]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func held(_ yaw: Double) -> BotAvatarConfiguration {
        var cfg = seeded(0.5, .eyes)
        cfg.fidelity?.poseEnabled = true; cfg.fidelity?.yaw = yaw; cfg.fidelity?.pitch = 12; cfg.fidelity?.roll = -8
        return cfg
    }
    private func seeded(_ seed: Double, _ face: BotAvatarFace) -> BotAvatarConfiguration {
        var cfg = avatar(material: .fabric, size: 64); cfg.face = face
        cfg.fidelity = .init(); cfg.fidelity?.seed = seed; cfg.whirl = 0.7
        return cfg
    }
    private func avatar(material: BotAvatarShading, size: Double) -> BotAvatarConfiguration {
        var a = BotAvatarConfiguration(); a.size = size; a.shading = material; a.face = .mouth
        return a
    }
    private func decorated(_ hat: BotAvatarHat, _ glasses: BotAvatarGlasses) -> BotAvatarConfiguration {
        var a = avatar(material: .fabric, size: 72)
        a.hat = hat; a.glasses = glasses; a.headphones = true; a.bowTie = true; a.accessoryColorHex = "#BC559C"
        return a
    }
    private func save<V: View>(_ view: V, scheme: ColorScheme, to url: URL) throws {
        let renderer = ImageRenderer(content: view.foregroundStyle(scheme == .dark ? Color.white : Color.black).background(scheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color.white).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "Native parity canvas must render")
        let bitmap = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
