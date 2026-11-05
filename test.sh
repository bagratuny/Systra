#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p .build/Checks
swiftc -parse-as-library Sources/SystraApp/TabRailGeometry.swift Tests/TabRailChecks.swift -o .build/Checks/tab-rail-checks
.build/Checks/tab-rail-checks
cp Resources/English.json .build/Checks/English.json
swiftc -parse-as-library Sources/SystraApp/Localization.swift Sources/SystraApp/DisplayFormatting.swift Tests/LocalizationChecks.swift -o .build/Checks/localization-checks
.build/Checks/localization-checks
clang -O2 -c Sources/SensorBridge/Sensors.c -o .build/Checks/Sensors.o
swiftc -parse-as-library -swift-version 5 -import-objc-header Sources/SensorBridge/Sensors.h Sources/SystraApp/Localization.swift Sources/SystraApp/TemperatureModels.swift Sources/SystraApp/SystemUptime.swift Sources/SystraApp/DisplayFormatting.swift Sources/SystraApp/Telemetry.swift Sources/SystraApp/Processes.swift Sources/SystraApp/TableModels.swift Tests/SortingChecks.swift .build/Checks/Sensors.o -framework IOKit -framework Metal -o .build/Checks/sorting-checks
swiftc -parse-as-library -swift-version 5 -import-objc-header Sources/SensorBridge/Sensors.h Sources/SystraApp/Localization.swift Sources/SystraApp/TemperatureModels.swift Sources/SystraApp/SystemUptime.swift Sources/SystraApp/DisplayFormatting.swift Sources/SystraApp/Telemetry.swift Sources/SystraApp/Processes.swift Sources/SystraApp/MenuBarMetrics.swift Sources/SystraApp/LoginItem.swift Tests/MenuBarSettingsChecks.swift .build/Checks/Sensors.o -framework IOKit -framework Metal -framework ServiceManagement -o .build/Checks/menu-settings-checks
.build/Checks/menu-settings-checks
swiftc -parse-as-library -swift-version 5 -import-objc-header Sources/SensorBridge/Sensors.h Sources/SystraApp/Localization.swift Sources/SystraApp/TemperatureModels.swift Sources/SystraApp/SystemUptime.swift Sources/SystraApp/DisplayFormatting.swift Sources/SystraApp/Telemetry.swift Sources/SystraApp/Processes.swift Sources/SystraApp/AppSummaryModels.swift Tests/AppSummaryChecks.swift .build/Checks/Sensors.o -framework IOKit -framework Metal -o .build/Checks/summary-checks
.build/Checks/summary-checks
swiftc -parse-as-library Sources/SystraApp/RowSelection.swift Tests/SelectionChecks.swift -o .build/Checks/selection-checks
.build/Checks/selection-checks
.build/Checks/sorting-checks
swiftc -parse-as-library Sources/SystraApp/Localization.swift Sources/SystraApp/TemperatureModels.swift Tests/TemperatureChecks.swift -o .build/Checks/temperature-checks
.build/Checks/temperature-checks
if [[ "${SYSTRA_LIVE_CHECKS:-0}" == "1" ]]; then
  swiftc -parse-as-library -swift-version 5 -import-objc-header Sources/SensorBridge/Sensors.h Sources/SystraApp/Localization.swift Sources/SystraApp/TemperatureModels.swift Sources/SystraApp/SystemUptime.swift Sources/SystraApp/DisplayFormatting.swift Sources/SystraApp/Telemetry.swift Sources/SystraApp/Processes.swift Tests/ProcessChecks.swift .build/Checks/Sensors.o -framework IOKit -framework Metal -o .build/Checks/process-checks
  .build/Checks/process-checks
fi
