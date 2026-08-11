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

/// DFU 升级封装类，供 Objective-C 调用
///
/// 用法示例 (OC):
/// ```objc
/// #import <MKDFUWapper/MKDFUWapper-Swift.h>
///
/// MKDFUWrapper *wrapper = [[MKDFUWrapper alloc] init];
/// wrapper.delegate = self;
/// [wrapper startDFUWithPeripheral:peripheral firmwareData:data];
/// ```
@objc public class MKDFUWrapper: NSObject {

    @objc public weak var delegate: MKDFUWrapperDelegate?

    private var transport: McuMgrBleTransport?
    private var dfuManager: FirmwareUpgradeManager?
    private var isUpdating: Bool = false

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

        transport = McuMgrBleTransport(peripheral)

        guard let transport = transport else {
            delegate?.dfuDidFail(withError: "Failed to create transport")
            isUpdating = false
            return
        }

        dfuManager = FirmwareUpgradeManager(transport: transport, delegate: self)

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
            dfuManager?.start(package: package, using: configuration)
        } catch {
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
