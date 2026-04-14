#!/bin/bash
# Build-time validation: ensure required Info.plist keys are present.
# Add as a Run Script build phase in Xcode:
#   Build Phases > + > New Run Script Phase
#   Script: ${SRCROOT}/Scripts/validate-info-plist-keys.sh

check_key() {
    local key="$1"
    local value
    value=$(/usr/libexec/PlistBuddy -c "Print :$key" "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}" 2>/dev/null)
    if [ -z "$value" ] || [ "$value" = "" ]; then
        echo "error: Missing required Info.plist key: $key. See Config.swift for setup instructions."
        exit 1
    fi
}

check_key "GooglePlacesAPIKey"
check_key "SupabaseURL"
check_key "SupabaseAnonKey"

echo "All required Info.plist keys present."
