#!/bin/sh
set -eu
[ "${CONFIGURATION:-Debug}" = "Release" ] || exit 0
case "${PRODUCT_BUNDLE_IDENTIFIER:-}" in ''|com.example.*) echo 'error: Set a real Bundle ID in Configuration/Local.xcconfig.'; exit 1;; esac
case "${AMAP_API_KEY:-}" in ''|YOUR_*) echo 'error: Configure the AMap iOS key before archiving.'; exit 1;; esac
[ "${XINGJI_CLOUD_ENABLED:-NO}" = YES ] || { echo 'error: Enable and configure iCloud before archiving the public app.'; exit 1; }
[ -n "${DEVELOPMENT_TEAM:-}" ] || { echo 'error: Select an Apple Developer Team before archiving.'; exit 1; }
[ -d "${SRCROOT}/Pods/AMap3DMap" ] || { echo 'error: Run bundle exec pod install and open Xingji.xcworkspace.'; exit 1; }
