#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift run XingjiVerify
swiftc -frontend -parse App/*.swift App/Services/*.swift App/Views/*.swift
plutil -lint Xingji.xcodeproj/project.pbxproj App/Resources/Info.plist App/Resources/Xingji.entitlements App/Resources/PrivacyInfo.xcprivacy
python3 Scripts/validate_project.py
