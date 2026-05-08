# Google Places API Setup Guide

This guide will help you set up the Google Places API for the Spots search functionality.

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your project name for later

## Step 2: Enable Places API (New)

1. In the Google Cloud Console, navigate to **APIs & Services** > **Library**
2. Search for "Places API (New)"
3. Click on it and press **Enable**

## Step 3: Create an API Key

1. Go to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **API Key**
3. Copy your API key (you'll need it in the next step)

## Step 4: (Recommended) Restrict Your API Key

1. Click on your newly created API key to edit it
2. Under **Application restrictions**, select **iOS apps**
3. Add your app's bundle identifier: `Karnerblu.Spots-Test`
4. Under **API restrictions**, select **Restrict key**
5. Choose **Places API (New)** from the list
6. Click **Save**

## Step 5: Configure API Key in the App

You have three options to set your API key:

### Option 1: Info.plist (Recommended for development)
1. In Xcode, select your project
2. Go to the **Info** tab
3. Add a new key: `GooglePlacesAPIKey` (type: String)
4. Set the value to your API key

### Option 2: Environment Variable (Recommended for CI/CD)
Set the environment variable `GOOGLE_PLACES_API_KEY` before building.

### Option 3: Direct Configuration (Quick setup)
1. Open `Config.swift`
2. Replace `"YOUR_GOOGLE_PLACES_API_KEY_HERE"` with your actual API key
3. **Note:** This is not recommended for production as it exposes your key in source code

## Step 6: Test the Integration

1. Build and run the app
2. Navigate to the Explore/Search screen
3. Type a search query (e.g., "Equinox Nomad")
4. You should see autocomplete suggestions appear

## Troubleshooting

### "API key not configured" error
- Make sure you've set the API key using one of the methods above
- Check that `Config.swift` is reading the key correctly

### "Invalid API key" or 403 error
- Verify the API key is correct
- Check that Places API (New) is enabled in your Google Cloud project
- Ensure API restrictions allow the Places API (New)

### No results appearing
- Check your internet connection
- Verify the API key has proper permissions
- Check the Xcode console for error messages

### Location permission denied
- The app will still work but won't use location bias
- To enable location bias, grant location permissions when prompted

## API Usage and Billing

- Google Places API (New) has a free tier with generous limits
- Monitor your usage in the Google Cloud Console
- Set up billing alerts to avoid unexpected charges
- For production, consider implementing request caching to reduce API calls

## Additional Resources

- [Google Places API (New) Documentation](https://developers.google.com/maps/documentation/places/ios-sdk)
- [API Key Best Practices](https://developers.google.com/maps/api-security-best-practices)

