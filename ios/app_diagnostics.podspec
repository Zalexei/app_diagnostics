Pod::Spec.new do |s|
  s.name             = 'app_diagnostics'
  s.version          = '0.1.0'
  s.summary          = 'MetricKit crash, hang and exit diagnostics for Flutter.'
  s.description      = <<-DESC
iOS side of app_diagnostics: stores MetricKit diagnostic and metric payloads
until Dart reads them.
                       DESC
  s.homepage         = 'https://github.com/Zalexei/app_diagnostics'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Alexey Zalogin'
  s.source           = { :path => '.' }
  s.source_files     = 'app_diagnostics/Sources/app_diagnostics/**/*.swift'
  s.resource_bundles = { 'app_diagnostics_privacy' => ['app_diagnostics/Sources/app_diagnostics/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.frameworks       = 'MetricKit'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.9'
end
