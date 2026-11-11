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
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index].name = device.name
            devices[index].rssi = device.rssi
        } else {
            devices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        errorMessage = "Connected. Discovering GATT services…"
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        errorMessage = "Connection failed: \(error?.localizedDescription ?? "unknown")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        errorMessage = "Disconnected: \(error?.localizedDescription ?? "normal")"
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
            addDetail("Characteristic: \(characteristic.uuid.uuidString), properties: \(characteristic.properties.rawValue)",
                      to: peripheral.identifier)
        }
    }
}
