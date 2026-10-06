#!/bin/sh
# Supplemental static check using CLT's Catalyst headers. This is NOT an iPhone build.
set -eu
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p .tools/typecheck
if [ -f .tools/vendor/MAMapKit.framework/Headers/MAMapKit.h ] && [ -f .tools/vendor/AMapSearchKit.framework/Headers/AMapSearchKit.h ]; then
  echo 'Checking App with actual AMap headers using Catalyst SDK; no device linking or signing.'
else
  echo 'AMap headers absent: only the unconfigured-map branch is checked.'
fi
swiftc -target arm64-apple-ios17.0-macabi -sdk "$SDK" -emit-module -module-name XingjiCore Sources/XingjiCore/*.swift -emit-module-path .tools/typecheck/XingjiCore.swiftmodule
swiftc -target arm64-apple-ios17.0-macabi -sdk "$SDK" -emit-module -module-name XingjiData -I .tools/typecheck Sources/XingjiData/*.swift -emit-module-path .tools/typecheck/XingjiData.swiftmodule
swiftc -target arm64-apple-ios17.0-macabi -sdk "$SDK" -F "$SDK/System/iOSSupport/System/Library/Frameworks" -I "$SDK/System/iOSSupport/usr/include" -F .tools/vendor -typecheck -I .tools/typecheck -module-name Xingji App/*.swift App/Services/*.swift App/Views/*.swift

echo 'Supplemental Catalyst type check passed; an iPhone build is still required.'
