import Foundation
import CoreBluetooth

/// On-demand scanning only. Continuous unfiltered BLE scanning can itself
/// drain a phone quickly, so the scan ends automatically after 18 seconds.
@MainActor
final class BluetoothBatteryScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
    private let larqService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var readings: [String: AccessoryBattery] = [:]
    private var stopWork: DispatchWorkItem?
    private var selectedIDs: Set<UUID> = []
    private(set) var scanning = false { didSet { onScanningChange?(scanning) } }
    var onChange: (([AccessoryBattery]) -> Void)?
    var onScanningChange: ((Bool) -> Void)?
    var onBluetoothMessage: ((String) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: false,
            CBCentralManagerOptionRestoreIdentifierKey: "com.soumen.voltscope.bluetooth"
        ])
    }

    func startScan() {
        guard central.state == .poweredOn else {
            onBluetoothMessage?(central.state == .unauthorized
                ? "Allow Bluetooth in iOS Settings to discover battery-capable accessories."
                : "Bluetooth is not available yet.")
            return
        }
        stopScan()
        // nil is intentionally foreground-only: many devices do not advertise 180F.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        discoverConnected()
        scanning = true
        let work = DispatchWorkItem { [weak self] in self?.stopScan() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: work)
    }

    func stopScan() {
        stopWork?.cancel()
        stopWork = nil
        if central?.isScanning == true { central.stopScan() }
        scanning = false
    }

    func connect(to id: String) {
        guard let uuid = UUID(uuidString: id), let peripheral = peripherals[uuid] else {
            onBluetoothMessage?("Scan again to locate this accessory.")
            return
        }
        selectedIDs.insert(uuid)
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        change(id) { $0.note = "Connecting…" }
    }

    func disconnect(_ id: String) {
        guard let uuid = UUID(uuidString: id), let peripheral = peripherals[uuid] else { return }
        selectedIDs.remove(uuid)
        central.cancelPeripheralConnection(peripheral)
    }

    private func discoverConnected() {
        for peripheral in central.retrieveConnectedPeripherals(withServices: [batteryService, larqService]) {
            peripherals[peripheral.identifier] = peripheral
            let id = peripheral.identifier.uuidString
            if readings[id] == nil {
                readings[id] = AccessoryBattery(id: id, name: peripheral.name ?? "Bluetooth accessory",
                    percentage: nil, connected: peripheral.state == .connected,
                    rssi: nil, updated: .now, source: .bluetooth,
                    note: "Read battery service to get a percentage")
            }
            publish()
        }
    }

    private func change(_ id: String, _ update: (inout AccessoryBattery) -> Void) {
        guard var value = readings[id] else { return }
        update(&value)
        readings[id] = value
        publish()
    }

    private func publish() {
        onChange?(readings.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { discoverConnected() }
        else { stopScan() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let list = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in list {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
        }
        discoverConnected()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) else { return }
        let id = peripheral.identifier.uuidString
        peripherals[peripheral.identifier] = peripheral
        let old = readings[id]
        readings[id] = AccessoryBattery(id: id, name: name,
            percentage: old?.percentage, connected: peripheral.state == .connected,
            rssi: RSSI.intValue, updated: old?.updated ?? .now,
            source: .bluetooth, note: old?.note ?? "Tap Read battery to connect")
        publish()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        change(peripheral.identifier.uuidString) {
            $0.connected = true
            $0.note = "Reading standard BLE Battery Service…"
        }
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        change(peripheral.identifier.uuidString) {
            $0.connected = false
            $0.note = error?.localizedDescription ?? "Connection failed"
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        change(peripheral.identifier.uuidString) {
            $0.connected = false
            $0.note = error?.localizedDescription ?? "Disconnected • last reading retained"
        }
        selectedIDs.remove(peripheral.identifier)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            change(peripheral.identifier.uuidString) { $0.note = error?.localizedDescription ?? "Service discovery failed" }
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == batteryService }) else {
            change(peripheral.identifier.uuidString) {
                $0.note = "Battery Service 180F not exposed by this accessory"
            }
            return
        }
        peripheral.discoverCharacteristics([batteryLevel], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == batteryLevel }) else {
            change(peripheral.identifier.uuidString) { $0.note = "Battery Level 2A19 unavailable" }
            return
        }
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == batteryLevel,
              let byte = characteristic.value?.first, byte <= 100 else { return }
        change(peripheral.identifier.uuidString) {
            $0.percentage = Int(byte)
            $0.updated = .now
            $0.connected = true
            $0.note = "Live standard BLE battery reading"
        }
    }
}
