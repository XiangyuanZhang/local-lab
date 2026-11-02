import SwiftUI
import Network
import IOKit.ps

struct BatteryStatus: Equatable {
    let percent: Int?
    let charging: Bool
    let onACPower: Bool
    static let unavailable = Self(percent: nil, charging: false, onACPower: false)
    static func read(_ sources: [[String: Any]]) -> Self {
        guard let source = sources.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else { return Self(percent: nil, charging: false, onACPower: true) }
        let current = (source[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let maximum = (source[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let percent: Int?
        if let current, let maximum, current.isFinite, maximum.isFinite, maximum > 0, current >= 0 {
            percent = Int(min(100, max(0, (current / maximum * 100).rounded())))
        } else { percent = nil }
        return Self(percent: percent, charging: (source[kIOPSIsChargingKey] as? Bool) == true,
                    onACPower: (source[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
    }
    var stateLabel: String? { charging ? "充電中" : onACPower ? "已接電" : nil }
    var symbol: String {
        guard let percent else { return "powerplug" }
        if charging { return "battery.100percent.bolt" }
        return "battery.\(percent <= 10 ? 0 : percent <= 35 ? 25 : percent <= 60 ? 50 : percent <= 85 ? 75 : 100)percent"
    }
    var text: String { percent.map { "\($0)%" } ?? (onACPower ? "AC" : "—") }
}

enum NetworkStatus: Equatable {
    case unknown, offline, wifi, wired, other
    var symbol: String {
        switch self {
        case .unknown: "network"
        case .offline: "wifi.slash"
        case .wifi: "wifi"
        case .wired: "cable.connector"
        case .other: "network"
        }
    }
    var description: String {
        switch self {
        case .unknown: "正在讀取網路狀態"
        case .offline: "網路未連線"
        case .wifi: "Wi-Fi 已連線"
        case .wired: "有線網路已連線"
        case .other: "網路已連線"
        }
    }
}

/// Event-driven system observations. No shell commands, Wi-Fi names, reachability probes or polling.
@MainActor
final class SystemStatusStore: ObservableObject {
    @Published private(set) var battery = BatteryStatus.unavailable
    @Published private(set) var network = NetworkStatus.unknown
    private let monitor = NWPathMonitor()
    private var powerSource: CFRunLoopSource?
    init() {
        refreshPower()
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // The source is registered on the main run loop and removed before deallocation.
            MainActor.assumeIsolated {
                Unmanaged<SystemStatusStore>.fromOpaque(context).takeUnretainedValue().refreshPower()
            }
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        monitor.pathUpdateHandler = { [weak self] path in
            let state: NetworkStatus = path.status != .satisfied ? .offline : path.usesInterfaceType(.wifi) ? .wifi : path.usesInterfaceType(.wiredEthernet) ? .wired : .other
            Task { @MainActor [weak self] in
                guard let self, network != state else { return }
                network = state
            }
        }
        monitor.start(queue: DispatchQueue(label: "local.edward.LocalLab.network-status", qos: .utility))
    }
    deinit {
        monitor.cancel()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
    }
    private func refreshPower() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        let descriptions = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
        let value = BatteryStatus.read(descriptions)
        if value != battery { battery = value }
    }
}
