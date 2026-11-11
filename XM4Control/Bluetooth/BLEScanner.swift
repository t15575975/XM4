import Foundation
import CoreBluetooth

struct DiscoveredDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var details: [String] = []
}

@MainActor
final class BLEScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var observations: [String] = []
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var xm4BLEConnected = false
    @Published private(set) var lastXM4SeenAt: Date?

    private var xm4PeripheralIDs = Set<UUID>()

    private func record(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        observations.insert("[\(stamp)] \(message)", at: 0)
        if observations.count > 250 { observations.removeLast(observations.count - 250) }
    }

    func clearObservations() { observations.removeAll() }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn else {
            errorMessage = "Bluetooth is not ready. Check iPhone Bluetooth settings."
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        observations.removeAll()
        errorMessage = nil
        isScanning = true
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stop() {
        central.stopScan()
        isScanning = false
    }

    func inspect(_ id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        stop()
        peripheral.delegate = self
        errorMessage = "Connecting to \(peripheral.name ?? "BLE device")…"
        record("Connecting to \(peripheral.name ?? peripheral.identifier.uuidString)")
        central.connect(peripheral, options: nil)
    }

    private func addDetail(_ value: String, to id: UUID) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        if !devices[index].details.contains(value) {
            devices[index].details.append(value)
        }
    }
}

extension BLEScanner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            isScanning = false
            xm4BLEConnected = false
            errorMessage = "Bluetooth state: \(central.state.rawValue)"
        } else {
            errorMessage = nil
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unnamed BLE device"
        if name.uppercased().contains("WF-1000XM4") || name.uppercased().contains("WF1000XM4") {
            xm4PeripheralIDs.insert(peripheral.identifier)
            lastXM4SeenAt = Date()
        }
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].name = device.name
            devices[index].rssi = device.rssi
        } else {
            devices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDeviceID = peripheral.identifier
        if xm4PeripheralIDs.contains(peripheral.identifier) {
            xm4BLEConnected = true
        }
        errorMessage = "Connected. Discovering GATT services…"
        record("Connected: \(peripheral.name ?? "device")")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if xm4PeripheralIDs.contains(peripheral.identifier) { xm4BLEConnected = false }
        errorMessage = "Connection failed: \(error?.localizedDescription ?? "unknown")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectedDeviceID == peripheral.identifier { connectedDeviceID = nil }
        if xm4PeripheralIDs.contains(peripheral.identifier) { xm4BLEConnected = false }
        errorMessage = "Disconnected: \(error?.localizedDescription ?? "normal")"
        record("Disconnected")
    }
}

extension BLEScanner: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            errorMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }
        let services = peripheral.services ?? []
        errorMessage = "Found \(services.count) GATT service(s)."
        for service in services {
            record("Service \(service.uuid.uuidString)")
            addDetail("Service: \(service.uuid.uuidString)", to: peripheral.identifier)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addDetail("Discovery error: \(error.localizedDescription)", to: peripheral.identifier)
            return
        }
        for characteristic in service.characteristics ?? [] {
            record("Characteristic \(service.uuid.uuidString) / \(characteristic.uuid.uuidString) props=\(characteristic.properties.rawValue)")
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            addDetail("Characteristic: \(characteristic.uuid.uuidString), properties: \(characteristic.properties.rawValue)",
                      to: peripheral.identifier)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let service = characteristic.service?.uuid.uuidString ?? "unknown"
        if let error = error {
            record("Read/notify error \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        let hex = (characteristic.value ?? Data()).map { String(format: "%02X", $0) }.joined(separator: " ")
        record("Value \(service) / \(characteristic.uuid.uuidString): \(hex.isEmpty ? "(empty)" : hex)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            record("Notify error \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            record("Notify \(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "on" : "off")")
        }
    }

}
