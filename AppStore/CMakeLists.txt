cmake_minimum_required(VERSION 3.29)
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build a universal Mac App Store binary" FORCE)
project(SignalMonitorAppStore LANGUAGES Swift)

set(SIGNAL_MONITOR_SOURCES
    ../Sources/SignalMonitor/AppMain.swift
    ../Sources/SignalMonitor/AppStoreMain.swift
    ../Sources/SignalMonitor/AppStoreCodexSource.swift
    ../Sources/SignalMonitor/FocusSettingsView.swift
    ../Sources/SignalMonitor/SignalState.swift
    ../Sources/SignalMonitor/SignalStore.swift
    ../Sources/SignalMonitor/SignalView.swift
)

set(SIGNAL_MONITOR_RESOURCES
    ../Resources/AppIcon.icns
    ../Resources/PrivacyInfo.xcprivacy
)

add_executable(SignalMonitorAppStore MACOSX_BUNDLE
    ${SIGNAL_MONITOR_SOURCES}
    ${SIGNAL_MONITOR_RESOURCES}
)

set_source_files_properties(${SIGNAL_MONITOR_RESOURCES}
    PROPERTIES MACOSX_PACKAGE_LOCATION Resources
)

target_compile_definitions(SignalMonitorAppStore PRIVATE APP_STORE)
target_link_libraries(SignalMonitorAppStore PRIVATE
    "-framework AppKit"
    "-framework Combine"
    "-framework ServiceManagement"
    "-framework SwiftUI"
    sqlite3
)

set_target_properties(SignalMonitorAppStore PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/../Resources/AppStoreInfo.plist"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
    XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/../Resources/SignalMonitorAppStore.entitlements"
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "2YT8NRXC26"
    XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf-with-dsym"
    XCODE_ATTRIBUTE_ENABLE_HARDENED_RUNTIME "YES"
    XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "@executable_path/../Frameworks"
    XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET "13.0"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.caiyuli.signalmonitor"
    XCODE_ATTRIBUTE_PRODUCT_NAME "Signal Monitor"
    XCODE_ATTRIBUTE_SDKROOT "macosx"
    XCODE_ATTRIBUTE_SKIP_INSTALL "NO"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "macosx"
    XCODE_ATTRIBUTE_INSTALL_PATH "/Applications"
    XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
)
