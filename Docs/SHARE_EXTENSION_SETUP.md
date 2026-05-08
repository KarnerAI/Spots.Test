# Share Extension Setup Guide

This guide explains how to complete the setup of the Share Extension feature in Xcode.

## Prerequisites

1. **OpenAI API Key**: You'll need an OpenAI API key with access to GPT-4 and GPT-4 Vision
2. **Apple Developer Account**: Required for App Groups configuration
3. **Xcode**: Latest version recommended

## Step 1: Add Share Extension Target in Xcode

1. Open your project in Xcode
2. Go to **File > New > Target**
3. Select **Share Extension** under iOS
4. Name it "ShareExtension" (or "SpotsShareExtension")
5. Make sure "Embed in Application" is set to your main app target
6. Click **Finish**

## Step 2: Configure Share Extension Target

1. Select the ShareExtension target in Xcode
2. Go to **General** tab:
   - Set **Bundle Identifier** to: `com.karnerblu.Spots-Test.ShareExtension` (or your bundle ID + `.ShareExtension`)
   - Set **Deployment Target** to match your main app (iOS 17.0 or later)

3. Go to **Signing & Capabilities**:
   - Enable **App Groups**
   - Add the App Group: `group.com.karnerblu.Spots-Test`
   - Make sure this matches `Config.appGroupIdentifier`

## Step 3: Add Source Files to Share Extension Target

The following files need to be added to BOTH the main app target AND the ShareExtension target:

### Required Files (add to both targets):
- `Spots.Test/Config.swift`
- `Spots.Test/AppGroupManager.swift`
- `Spots.Test/ShareContentProcessor.swift`
- `Spots.Test/OpenAIService.swift`
- `Spots.Test/PlaceExtractionService.swift`
- `Spots.Test/ShareConfirmationView.swift`
- `Spots.Test/PlacesAPIService.swift`
- `Spots.Test/PlaceAutocompleteResult.swift`
- `Spots.Test/LocationSavingService.swift`
- `Spots.Test/SupabaseManager.swift`
- `Spots.Test/Spot.swift`
- `Spots.Test/UserList.swift`
- `Spots.Test/SpotListItem.swift`
- `ShareExtension/ShareViewController.swift`

### How to Add Files to Multiple Targets:

1. Select a file in Xcode
2. Open the **File Inspector** (right panel)
3. Under **Target Membership**, check both:
   - `Spots.Test` (main app)
   - `ShareExtension` (extension)

Repeat for all files listed above.

## Step 4: Configure Info.plist Files

### Main App Info.plist (`Spots-Test-Info.plist`)

Add the OpenAI API key:

```xml
<key>OpenAIAPIKey</key>
<string>YOUR_OPENAI_API_KEY_HERE</string>
```

### Share Extension Info.plist

The `ShareExtension/Info.plist` file has already been created with the correct configuration. Verify it includes:
- `NSExtensionActivationSupportsImageWithMaxCount`: 10
- `NSExtensionActivationSupportsText`: true
- `NSExtensionActivationSupportsWebURLWithMaxCount`: 1
- `NSExtensionActivationSupportsWebPageWithMaxCount`: 1

## Step 5: Configure App Groups in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com/account/)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Go to **Identifiers** > **App Groups**
4. Click the **+** button to create a new App Group
5. Set the identifier to: `group.com.karnerblu.Spots-Test`
6. Save and return to Xcode
7. In Xcode, refresh your provisioning profiles

## Step 6: Add OpenAI API Key

1. Get your OpenAI API key from [OpenAI Platform](https://platform.openai.com/api-keys)
2. Add it to `Spots-Test-Info.plist`:
   ```xml
   <key>OpenAIAPIKey</key>
   <string>sk-your-key-here</string>
   ```

## Step 7: Update Share Extension Info.plist Location

The Share Extension's Info.plist needs to be properly referenced:

1. Select the ShareExtension target
2. Go to **Build Settings**
3. Search for "Info.plist File"
4. Set it to: `ShareExtension/Info.plist`

## Step 8: Configure URL Scheme (Optional)

To enable deep linking from the extension:

1. Select the main app target
2. Go to **Info** tab
3. Under **URL Types**, add a new URL Type:
   - **Identifier**: `com.karnerblu.spots`
   - **URL Schemes**: `spots`
   - **Role**: Editor

## Step 9: Build and Test

1. Build the project (⌘B)
2. Run on a device (Share Extensions don't work in Simulator for all apps)
3. Test by sharing content from:
   - Instagram (image + caption)
   - TikTok (image + caption)
   - Safari (URL)
   - Notes (text)

## Troubleshooting

### "No such module" errors
- Make sure all required files are added to the ShareExtension target
- Check that imports are correct

### "App Group not found" errors
- Verify App Group is configured in both targets
- Check that the identifier matches exactly: `group.com.karnerblu.Spots-Test`
- Ensure App Group is created in Apple Developer Portal

### "Session token not found" errors
- Make sure user is logged in to the main app first
- Check that `AppGroupManager` is saving the token correctly

### Extension doesn't appear in share sheet
- Make sure the extension target is built
- Check that the extension's Info.plist is correctly configured
- Verify the extension is embedded in the main app

### OpenAI API errors
- Verify API key is correct in Info.plist
- Check that you have credits in your OpenAI account
- Ensure GPT-4 Vision access is enabled

## Architecture Notes

- **Share Extension** runs in a separate process from the main app
- **App Group** is used to share data (session tokens) between app and extension
- **Authentication** is handled by sharing the Supabase session token via App Group
- **Content Processing** extracts text from images using Vision framework OCR
- **OpenAI API** extracts place names from text and images
- **Google Places API** searches for and validates the extracted places
- **Confirmation Screen** allows users to select which places to save

## Next Steps

After setup is complete:
1. Test with various content types
2. Monitor OpenAI API usage and costs
3. Consider adding error handling for edge cases
4. Add analytics to track usage
5. Optimize for performance (batch API calls, caching, etc.)

