Pod::Spec.new do |s|
  s.name             = 'MKDFUWapper'
  s.version          = '1.0.2'
  s.summary          = 'OC-compatible wrapper for Nordic iOSMcuManagerLibrary DFU'

  s.description      = <<-DESC
  MKDFUWapper wraps the Nordic iOSMcuManagerLibrary's FirmwareUpgradeManager
  and exposes it as an @objc-compatible interface, allowing Objective-C
  projects to perform McuManager DFU firmware upgrades.
  DESC

  s.homepage         = 'https://github.com/lovexiaoxia/MKDFUWapper'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'lovexiaoxia' => 'lovexiaoxia@example.com' }

  s.source           = { :git => 'git@github.com:MOKO-iOS-Base-Library/MKDFUWapper.git',
                         :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions         = ['5.0']

  s.source_files = 'Sources/MKDFUWapper/**/*.swift'

  s.dependency 'iOSMcuManagerLibrary', '~> 1.7'
end
