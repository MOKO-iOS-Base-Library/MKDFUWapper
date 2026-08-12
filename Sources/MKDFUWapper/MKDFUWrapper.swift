//
//  MKDFUWrapper.swift
//  MKDFUWapper
//
//  Created by aa on 2026/8/11.
//  Copyright © 2026 lovexiaoxia. All rights reserved.
//

import Foundation
import iOSMcuManagerLibrary
import CoreBluetooth

/// OC 兼容的 DFU 回调代理
@objc public protocol MKDFUWrapperDelegate: AnyObject {
    /// 固件升级进度回调 (0.0 ~ 1.0)
    func dfuProgressDidChange(_ progress: Float)
    /// 固件升级状态变更回调
    func dfuStateDidChange(_ state: String)
    /// 固件升级完成
    func dfuDidComplete()
    /// 固件升级失败
    func dfuDidFail(withError error: String)
    /// 固件升级被取消
    func dfuDidCancel()
}

// MARK: - DFULogDelegate

/// 日志代理实现，打印所有 McuManager 传输层和管理器日志
private class DFULogDelegate: McuMgrLogDelegate {
    func log(_ msg: String, ofCategory category: McuMgrLogCategory, atLevel level: McuMgrLogLevel) {
        print("DFU [\(category.rawValue)][\(level.name)]: \(msg)")
    }

    func minLogLevel() -> McuMgrLogLevel {
        return .debug
    }
}

// MARK: - DFUPeripheralDelegate

/// 监听 Transport 外设连接状态变化
private class DFUPeripheralDelegate: PeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didChangeStateTo state: PeripheralState) {
        let mtuInfo = state == .connected
            ? " (MTU: \(peripheral.maximumWriteValueLength(for: .withoutResponse)))"
            : ""
        print("DFU Transport: Peripheral state -> \(state)\(mtuInfo)")
    }
}

// MARK: - MKDFUWrapper

/// DFU 升级封装类，供 Objective-C 调用
@objc public class MKDFUWrapper: NSObject, @unchecked Sendable {

    @objc public weak var delegate: MKDFUWrapperDelegate?

    private var transport: McuMgrBleTransport?
    private var dfuManager: FirmwareUpgradeManager?
    private var isUpdating: Bool = false

    /// 日志代理（需强引用，因为 McuMgrBleTransport.logDelegate 是 weak）
    private let logDelegate = DFULogDelegate()
    /// 外设状态代理（需强引用，因为 McuMgrBleTransport.delegate 是 weak）
    private let peripheralDelegate = DFUPeripheralDelegate()

    @objc public override init() {
        super.init()
    }

    /// 开始 DFU 升级
    /// - Parameters:
    ///   - peripheral: 已连接的 BLE 外设
    ///   - firmwareData: 固件文件数据 (.bin / .zip / .suit)
    @objc public func startDFU(with peripheral: CBPeripheral, firmwareData: Data) {
        guard !isUpdating else {
            delegate?.dfuDidFail(withError: "DFU is already in progress")
            return
        }

        isUpdating = true

        // 使用 identifier 初始化 Transport，确保 Transport 通过自己的 CBCentralManager
        // 检索 CBPeripheral，而不是复用 App 的 CBCentralManager 创建的 CBPeripheral 对象。
        // CBPeripheral 对象与创建它的 CBCentralManager 绑定，跨 CentralManager 使用
        // 可能导致 writeValue/type=.withoutResponse 写入静默失败。
        transport = McuMgrBleTransport(peripheral.identifier)

        guard let transport = transport else {
            delegate?.dfuDidFail(withError: "Failed to create transport")
            isUpdating = false
            return
        }

        // 设置日志代理，输出传输层详细日志（MTU、写入状态、重试等）
        transport.logDelegate = logDelegate
        transport.delegate = peripheralDelegate

        // ⚠️ 关键修复：强制设置 MTU 为 iOS 默认最大值（524）。
        // McuMgrBleTransport 初始化时外设未连接，maximumWriteValueLength 返回 20，
        // 导致初始 MTU = min(max(73, 20), 524) = 73。
        // _send() 中的 MTU 调整逻辑只会下调（if mtu > negotiatedMTU），不会上调。
        // 所以如果不手动设置，MTU 永远停留在 73，每个上传包只携带 ~50 字节数据，
        // 479KB 固件需要 8000+ 个包，极易超时导致 "Sending the request failed"。
        // 设置为 524 后，_send() 会检测到 524 > 协商后的实际值（如 244），
        // 从而正确下调到实际协商值。
        transport.mtu = McuManager.getDefaultMtu(scheme: .ble)
        print("DFU: Transport MTU set to \(transport.mtu ?? -1) (will be adjusted to negotiated value on connect)")

        // 创建 DFU 管理器
        dfuManager = FirmwareUpgradeManager(transport: transport, delegate: self)
        // 设置日志代理（自动传播到 ImageManager、DefaultManager、SuitManager）
        dfuManager?.logDelegate = logDelegate

        let configuration = FirmwareUpgradeConfiguration(
            estimatedSwapTime: 10.0,
            eraseAppSettings: false,
            pipelineDepth: 1,
            byteAlignment: .disabled,
            reassemblyBufferSize: 0,
            upgradeMode: .confirmOnly
        )

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("firmware.bin")
            try firmwareData.write(to: tempURL)
            let package = try McuMgrPackage(from: tempURL)

            // 打印诊断信息
            print("DFU: Transport initial MTU: \(transport.mtu ?? -1)")
            print("DFU: Package images count: \(package.images.count)")
            for image in package.images {
                let hashHex = image.hash.map { String(format: "%02x", $0) }.joined()
                let hashDisplay = hashHex.isEmpty ? "(empty)" : String(hashHex.prefix(16)) + "..."
                print("DFU: Image \(image.image) - Size: \(image.data.count) bytes, Hash: \(hashDisplay)")

                // 检查固件文件是否包含有效的 MCUboot 头
                if image.hash.isEmpty {
                    print("DFU: ⚠️ Image hash is empty! The .bin file may not have a valid MCUboot image header.")
                    print("DFU: ⚠️ This could cause the device to reject the upload or fail during boot.")
                }
            }

            dfuManager?.start(package: package, using: configuration)
        } catch {
            print("DFU: Package creation error: \(error)")
            delegate?.dfuDidFail(withError: "Failed to create package: \(error.localizedDescription)")
            isUpdating = false
        }
    }

    /// 取消正在进行的 DFU 升级
    @objc public func cancelDFU() {
        dfuManager?.cancel()
        isUpdating = false
    }
}

// MARK: - FirmwareUpgradeDelegate
extension MKDFUWrapper: FirmwareUpgradeDelegate {

    public func upgradeDidStart(controller: any iOSMcuManagerLibrary.FirmwareUpgradeController) {
        print("DFU: Upgrade started")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuStateDidChange("Started")
        }
    }

    public func upgradeStateDidChange(from previousState: iOSMcuManagerLibrary.FirmwareUpgradeState, to newState: iOSMcuManagerLibrary.FirmwareUpgradeState) {
        let stateString = Self.stateToString(newState)
        print("DFU State: \(stateString)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuStateDidChange(stateString)
        }
    }

    public func upgradeDidComplete() {
        print("DFU: Upgrade completed successfully!")
        isUpdating = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuDidComplete()
        }
    }

    public func upgradeDidFail(inState state: iOSMcuManagerLibrary.FirmwareUpgradeState, with error: any Error) {
        let stateString = Self.stateToString(state)
        print("DFU: Upgrade failed in state: \(stateString), error: \(error.localizedDescription)")
        print("DFU: Error type: \(type(of: error))")
        isUpdating = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuDidFail(withError: "Failed in \(stateString): \(error.localizedDescription)")
        }
    }

    public func upgradeDidCancel(state: iOSMcuManagerLibrary.FirmwareUpgradeState) {
        let stateString = Self.stateToString(state)
        print("DFU: Upgrade cancelled in state: \(stateString)")
        isUpdating = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuDidCancel()
        }
    }

    public func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        let progress = imageSize > 0 ? Float(bytesSent) / Float(imageSize) : 0
        print("DFU Progress: \(Int(progress * 100))% (\(bytesSent)/\(imageSize) bytes)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dfuProgressDidChange(progress)
        }
    }

    // MARK: - Private Helpers

    private static func stateToString(_ state: iOSMcuManagerLibrary.FirmwareUpgradeState) -> String {
        switch state {
        case .none:                     return "None"
        case .requestMcuMgrParameters:  return "Requesting Parameters"
        case .bootloaderInfo:           return "Getting Bootloader Info"
        case .eraseAppSettings:         return "Erasing Settings"
        case .upload:                   return "Uploading"
        case .success:                  return "Success"
        case .validate:                 return "Validating"
        case .test:                     return "Testing"
        case .confirm:                  return "Confirming"
        case .reset:                    return "Resetting"
        case .resetIntoFirmwareLoader:  return "Resetting into FW Loader"
        @unknown default:               return "Unknown"
        }
    }
}
