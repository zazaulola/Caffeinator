import Foundation
import IOKit.ps

final class PowerMonitor {
    struct Snapshot: Equatable {
        let hasBattery: Bool
        let isOnBattery: Bool
        let percentage: Int   // 0...100
    }

    var onChange: ((Snapshot) -> Void)?

    private var loopSource: CFRunLoopSource?

    func start() {
        guard loopSource == nil else { return }
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                me.onChange?(me.snapshot())
            }
        }, context) else { return }

        let source = unmanaged.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        loopSource = source
    }

    func stop() {
        if let source = loopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            loopSource = nil
        }
    }

    // The run-loop source embeds a raw (passUnretained) pointer to self, so it
    // must be torn down before this instance is freed — otherwise a later power
    // notification would dereference freed memory. stop() is idempotent.
    deinit {
        stop()
    }

    func snapshot() -> Snapshot {
        // IOPSCopy* are documented to return NULL on error / low memory; fall
        // back to the no-battery snapshot rather than trapping on a force-unwrap.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return Snapshot(hasBattery: false, isOnBattery: false, percentage: 100)
        }

        for src in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() else { continue }
            let info = raw as NSDictionary as? [String: Any] ?? [:]

            guard (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let stateStr = info[kIOPSPowerSourceStateKey] as? String
            let isOnBattery = (stateStr == kIOPSBatteryPowerValue)

            let cur = info[kIOPSCurrentCapacityKey] as? Int ?? 100
            let mx  = info[kIOPSMaxCapacityKey]     as? Int ?? 100
            let pct = mx > 0 ? (cur * 100) / mx : 100

            return Snapshot(
                hasBattery: true,
                isOnBattery: isOnBattery,
                percentage: Swift.max(0, Swift.min(100, pct))
            )
        }
        return Snapshot(hasBattery: false, isOnBattery: false, percentage: 100)
    }
}
