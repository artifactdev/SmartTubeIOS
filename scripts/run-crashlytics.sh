#!/bin/sh
set -e

firebase_plist="${SRCROOT}/SmartTubeApp/GoogleService-Info.plist"
firebase_app_id=$(/usr/libexec/PlistBuddy -c 'Print :GOOGLE_APP_ID' "$firebase_plist" 2>/dev/null || true)
firebase_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$firebase_plist" 2>/dev/null || true)

if [ "$firebase_bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ] || \
    ! printf '%s' "$firebase_app_id" | /usr/bin/grep -Eq '^[0-9]+:[0-9]+:ios:[A-Za-z0-9_-]+$'; then
    printf 'Skipping Crashlytics dSYM upload: no valid Firebase configuration for %s.\n' "$PRODUCT_BUNDLE_IDENTIFIER"
    exit 0
fi

"${BUILD_DIR%Build/*}SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run" \
    -gsp "$firebase_plist"