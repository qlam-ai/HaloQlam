//
//  RingSessionManager.swift
//  HaloQlam
//
//  Created by naim sassine on 02/12/2024.
//

import Foundation
import AccessorySetupKit
import CoreBluetooth
import SwiftUI

@Observable
class RingSessionManager: NSObject {
    var peripheralConnected = false
    var pickerDismissed = true
    
    var currentRing: ASAccessory?
    private var session = ASAccessorySession()
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    
    private var uartRxCharacteristic: CBCharacteristic?
    private var uartTxCharacteristic: CBCharacteristic?
    
    private static let ringServiceUUID = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
    private static let uartRxCharacteristicUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    private static let uartTxCharacteristicUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    
    private static let deviceInfoServiceUUID = "0000180A-0000-1000-8000-00805F9B34FB"
    private static let deviceHardwareUUID = "00002A27-0000-1000-8000-00805F9B34FB"
    private static let deviceFirmwareUUID = "00002A26-0000-1000-8000-00805F9B34FB"
    
    private static let ring: ASPickerDisplayItem = {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: ringServiceUUID)
        
        return ASPickerDisplayItem(
            name: "COLMI R02 Ring",
            productImage: UIImage(named: "Colmi")!,
            descriptor: descriptor
        )
    }()
    
    private var characteristicsDiscovered = false
    
    override init() {
        super.init()
        self.session.activate(on: DispatchQueue.main, eventHandler: handleSessionEvent(event:))
    }
    
    // MARK: - RingSessionManager actions
    func presentPicker() {
        session.showPicker(for: [Self.ring]) { error in
            if let error {
                print("Failed to show picker due to: \(error.localizedDescription)")
            }
        }
    }
    
    func removeRing() {
        guard let currentRing else { return }
        
        if peripheralConnected {
            disconnect()
        }
        
        session.removeAccessory(currentRing) { _ in
            self.currentRing = nil
            self.manager = nil
        }
    }
    
    func connect() {
        guard
            let manager, manager.state == .poweredOn,
            let peripheral
        else {
            return
        }
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionStartDelayKey: 1
        ]
        manager.connect(peripheral, options: options)
    }
    
    func disconnect() {
        guard let peripheral, let manager else { return }
        manager.cancelPeripheralConnection(peripheral)
    }
    
    // MARK: - ASAccessorySession functions
    private func saveRing(ring: ASAccessory) {
        currentRing = ring
        
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: nil)
        }
    }
    
    private func handleSessionEvent(event: ASAccessoryEvent) {
        switch event.eventType {
        case .accessoryAdded, .accessoryChanged:
            guard let ring = event.accessory else { return }
            saveRing(ring: ring)
        case .activated:
            guard let ring = session.accessories.first else { return }
            saveRing(ring: ring)
        case .accessoryRemoved:
            self.currentRing = nil
            self.manager = nil
        case .pickerDidPresent:
            pickerDismissed = false
        case .pickerDidDismiss:
            pickerDismissed = true
        default:
            print("Received event type \(event.eventType)")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension RingSessionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central manager state: \(central.state)")
        switch central.state {
        case .poweredOn:
            if let peripheralUUID = currentRing?.bluetoothIdentifier {
                if let knownPeripheral = central.retrievePeripherals(withIdentifiers: [peripheralUUID]).first {
                    print("Found previously connected peripheral")
                    peripheral = knownPeripheral
                    peripheral?.delegate = self
                    connect()
                } else {
                    print("Known peripheral not found, starting scan")
                }
            }
        default:
            peripheral = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("DEBUG: Connected to peripheral: \(peripheral)")
        peripheral.delegate = self
        print("DEBUG: Discovering services...")
        peripheral.discoverServices([CBUUID(string: Self.ringServiceUUID)])
        
        peripheralConnected = true
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        print("Disconnected from peripheral: \(peripheral)")
        peripheralConnected = false
        characteristicsDiscovered = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        print("Failed to connect to peripheral: \(peripheral), error: \(error.debugDescription)")
    }
}

// MARK: - CBPeripheralDelegate
extension RingSessionManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        print("DEBUG: Services discovery callback, error: \(String(describing: error))")
        guard error == nil, let services = peripheral.services else {
            print("DEBUG: No services found or error occurred")
            return
        }
        
        print("DEBUG: Found \(services.count) services")
        for service in services {
            if service.uuid == CBUUID(string: Self.ringServiceUUID) {
                print("DEBUG: Found ring service, discovering characteristics...")
                peripheral.discoverCharacteristics([
                    CBUUID(string: Self.uartRxCharacteristicUUID),
                    CBUUID(string: Self.uartTxCharacteristicUUID)
                ], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("DEBUG: Characteristics discovery callback, error: \(String(describing: error))")
        guard error == nil, let characteristics = service.characteristics else {
            print("DEBUG: No characteristics found or error occurred")
            return
        }
        
        print("DEBUG: Found \(characteristics.count) characteristics")
        for characteristic in characteristics {
            switch characteristic.uuid {
            case CBUUID(string: Self.uartRxCharacteristicUUID):
                print("DEBUG: Found UART RX characteristic")
                self.uartRxCharacteristic = characteristic
            case CBUUID(string: Self.uartTxCharacteristicUUID):
                print("DEBUG: Found UART TX characteristic")
                self.uartTxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                print("DEBUG: Found other characteristic: \(characteristic.uuid)")
            }
        }
        characteristicsDiscovered = true
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: Self.uartTxCharacteristicUUID) {
            if let value = characteristic.value {
                print("Received value: \(value)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write to characteristic failed: \(error.localizedDescription)")
        } else {
            print("Write to characteristic successful")
        }
    }
}
