# Location-Saving Feature Implementation Guide

This guide walks you through completing the implementation of the location-saving feature after running the database migration.

## Prerequisites

- ✅ Database schema migration file created (`create_location_saving_schema.sql`)
- ✅ Supabase project set up
- ✅ Supabase Swift client configured in your app
- ✅ User authentication working

---

## Step 1: Run the Database Migration

### 1.1 Open Supabase Dashboard

1. Go to [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Select your project (the one with URL: `https://dirqixrgkcdpixmriyge.supabase.co`)

### 1.2 Navigate to SQL Editor

1. In the left sidebar, click **"SQL Editor"**
2. Click **"New query"** button (top right)

### 1.3 Copy and Run the Migration

1. Open the file: `create_location_saving_schema.sql`
2. **Copy the entire contents** of the file
3. **Paste it into the SQL Editor** in Supabase
4. Click **"Run"** button (or press `Cmd+Enter` / `Ctrl+Enter`)

### 1.4 Verify Migration Success

You should see:
- ✅ Success message: "Success. No rows returned"
- ✅ No error messages

**If you see errors:**
- Check that you've already run `create_profiles_table.sql` (the profiles table must exist)
- Make sure you're running the entire script, not just parts of it
- Check the error message for specific issues

### 1.5 Verify Tables Were Created

1. In Supabase Dashboard, go to **"Table Editor"** (left sidebar)
2. You should see these new tables:
   - `spots`
   - `user_lists`
   - `spot_list_items`
3. Click on each table to verify the columns are correct

---

## Step 2: Create Lists for Existing Users

If you have users who signed up before this migration, you need to create their default lists.

### 2.1 Run Migration Helper

1. Go back to **"SQL Editor"** in Supabase Dashboard
2. Create a new query
3. Paste and run this command:

```sql
SELECT * FROM public.create_lists_for_existing_users();
```

### 2.2 Verify Lists Were Created

1. Go to **"Table Editor"**
2. Open the `user_lists` table
3. You should see 3 rows per existing user (one for each default list type)
4. Each row should have:
   - `list_type`: 'starred', 'favorites', or 'bucket_list'
   - `name`: NULL (system lists don't have names)
   - `user_id`: The user's UUID

**Note:** New users will automatically get their lists created via the trigger, so you only need to run this once for existing users.

---

## Step 3: Test the Schema (Optional but Recommended)

Before integrating with your app, test the schema with some queries.

### 3.1 Test: Get Your Lists

1. In **SQL Editor**, create a new query
2. Run this (replace with your actual user ID if needed):

```sql
-- Get all lists for the current authenticated user
SELECT 
  id,
  list_type,
  name,
  created_at
FROM public.user_lists
WHERE user_id = auth.uid()
ORDER BY 
  CASE list_type
    WHEN 'starred' THEN 1
    WHEN 'favorites' THEN 2
    WHEN 'bucket_list' THEN 3
    ELSE 4
  END;
```

**Expected Result:** You should see 3 rows (one for each default list).

### 3.2 Test: Save a Spot (Manual Test)

1. First, insert a test spot:

```sql
-- Insert a test spot
INSERT INTO public.spots (place_id, name, address, latitude, longitude, types)
VALUES (
  'test_place_123',
  'Test Restaurant',
  '123 Test Street, Test City',
  40.7128,
  -74.0060,
  ARRAY['restaurant', 'food']
)
ON CONFLICT (place_id) DO NOTHING;
```

2. Then, add it to your Favorites list:

```sql
-- Add spot to Favorites list
INSERT INTO public.spot_list_items (spot_id, list_id)
VALUES (
  'test_place_123',
  (SELECT id FROM public.user_lists 
   WHERE user_id = auth.uid() AND list_type = 'favorites' 
   LIMIT 1)
)
ON CONFLICT (spot_id, list_id) DO NOTHING;
```

3. Verify it was added:

```sql
-- Get all spots in Favorites list
SELECT 
  s.place_id,
  s.name,
  s.address,
  sli.saved_at
FROM public.spot_list_items sli
JOIN public.spots s ON s.place_id = sli.spot_id
WHERE sli.list_id = (
  SELECT id FROM public.user_lists 
  WHERE user_id = auth.uid() AND list_type = 'favorites' 
  LIMIT 1
)
ORDER BY sli.saved_at DESC;
```

**Expected Result:** You should see your test spot.

---

## Step 4: Create Swift Data Models

Create Swift structs that match your database schema.

### 4.1 Create Spot Model

Create a new file: `Spots.Test/Spot.swift`

```swift
import Foundation

struct Spot: Codable, Identifiable {
    let placeId: String
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let types: [String]?
    let createdAt: Date?
    let updatedAt: Date?
    
    var id: String { placeId }
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case name
        case address
        case latitude
        case longitude
        case types
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

### 4.2 Create UserList Model

Create a new file: `Spots.Test/UserList.swift`

```swift
import Foundation

enum ListType: String, Codable {
    case starred
    case favorites
    case bucketList = "bucket_list"
    
    var displayName: String {
        switch self {
        case .starred: return "Starred"
        case .favorites: return "Favorites"
        case .bucketList: return "Bucket List"
        }
    }
}

struct UserList: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let listType: ListType?
    let name: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    var displayName: String {
        if let listType = listType {
            return listType.displayName
        }
        return name ?? "Untitled List"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case listType = "list_type"
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

### 4.3 Create SpotListItem Model

Create a new file: `Spots.Test/SpotListItem.swift`

```swift
import Foundation

struct SpotListItem: Codable, Identifiable {
    let id: UUID
    let spotId: String
    let listId: UUID
    let savedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case spotId = "spot_id"
        case listId = "list_id"
        case savedAt = "saved_at"
    }
}

// Combined model for UI (spot + metadata)
struct SpotWithMetadata: Identifiable {
    let spot: Spot
    let savedAt: Date
    let listId: UUID
    
    var id: String { spot.id }
}
```

---

## Step 5: Create Location Saving Service

Create a service class to handle all database operations.

### 5.1 Create LocationSavingService

Create a new file: `Spots.Test/LocationSavingService.swift`

```swift
import Foundation
import Supabase

class LocationSavingService {
    static let shared = LocationSavingService()
    
    private let supabase = SupabaseManager.shared.client
    
    private init() {}
    
    // MARK: - Lists
    
    /// Get all lists for the current user
    func getUserLists() async throws -> [UserList] {
        let response: [UserList] = try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: try await getCurrentUserId())
            .order("list_type", ascending: true)
            .execute()
            .value
        
        return response
    }
    
    /// Get a specific list by type
    func getListByType(_ listType: ListType) async throws -> UserList? {
        let userId = try await getCurrentUserId()
        
        let response: [UserList] = try await supabase
            .from("user_lists")
            .select()
            .eq("user_id", value: userId)
            .eq("list_type", value: listType.rawValue)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Spots
    
    /// Upsert a spot (insert or update)
    func upsertSpot(
        placeId: String,
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        types: [String]?
    ) async throws {
        // Call the database function
        try await supabase.rpc("upsert_spot", params: [
            "p_place_id": placeId,
            "p_name": name,
            "p_address": address as Any,
            "p_latitude": latitude as Any,
            "p_longitude": longitude as Any,
            "p_types": types as Any
        ]).execute()
    }
    
    /// Get all spots in a list (ordered by recency)
    func getSpotsInList(listId: UUID) async throws -> [SpotWithMetadata] {
        struct Response: Codable {
            let place_id: String
            let name: String
            let address: String?
            let latitude: Double?
            let longitude: Double?
            let types: [String]?
            let created_at: String?
            let updated_at: String?
            let saved_at: String
        }
        
        let response: [Response] = try await supabase
            .from("spot_list_items")
            .select("""
                spot_id,
                saved_at,
                spots (
                    place_id,
                    name,
                    address,
                    latitude,
                    longitude,
                    types,
                    created_at,
                    updated_at
                )
            """)
            .eq("list_id", value: listId.uuidString)
            .order("saved_at", ascending: false)
            .execute()
            .value
        
        // Transform response to SpotWithMetadata
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return response.compactMap { item in
            guard let savedAt = dateFormatter.date(from: item.saved_at) else { return nil }
            
            let spot = Spot(
                placeId: item.place_id,
                name: item.name,
                address: item.address,
                latitude: item.latitude,
                longitude: item.longitude,
                types: item.types,
                createdAt: item.created_at.flatMap { dateFormatter.date(from: $0) },
                updatedAt: item.updated_at.flatMap { dateFormatter.date(from: $0) }
            )
            
            return SpotWithMetadata(spot: spot, savedAt: savedAt, listId: listId)
        }
    }
    
    /// Get spot count for a list
    func getSpotCount(listId: UUID) async throws -> Int {
        struct CountResponse: Codable {
            let count: Int
        }
        
        let response: CountResponse = try await supabase
            .rpc("get_list_spot_count", params: ["list_id": listId.uuidString])
            .execute()
            .value
        
        return response.count
    }
    
    // MARK: - Saving/Removing Spots
    
    /// Save a spot to a list
    func saveSpotToList(placeId: String, listId: UUID) async throws {
        try await supabase
            .from("spot_list_items")
            .insert([
                "spot_id": placeId,
                "list_id": listId.uuidString
            ])
            .execute()
    }
    
    /// Remove a spot from a list
    func removeSpotFromList(placeId: String, listId: UUID) async throws {
        try await supabase
            .from("spot_list_items")
            .delete()
            .eq("spot_id", value: placeId)
            .eq("list_id", value: listId.uuidString)
            .execute()
    }
    
    /// Check which lists contain a spot
    func getListsContainingSpot(placeId: String) async throws -> [UUID] {
        struct Response: Codable {
            let list_id: String
        }
        
        let response: [Response] = try await supabase
            .from("spot_list_items")
            .select("list_id")
            .eq("spot_id", value: placeId)
            .execute()
            .value
        
        return response.compactMap { UUID(uuidString: $0.list_id) }
    }
    
    // MARK: - Helper
    
    private func getCurrentUserId() async throws -> UUID {
        let session = try await supabase.auth.session
        guard let userId = session?.user.id else {
            throw NSError(domain: "LocationSavingService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        return userId
    }
}
```

---

## Step 6: Create ViewModel for Location Saving

Create a ViewModel to manage state and business logic.

### 6.1 Create LocationSavingViewModel

Create a new file: `Spots.Test/LocationSavingViewModel.swift`

```swift
import Foundation
import SwiftUI

@MainActor
class LocationSavingViewModel: ObservableObject {
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let service = LocationSavingService.shared
    
    // MARK: - Load Lists
    
    func loadUserLists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            userLists = try await service.getUserLists()
        } catch {
            errorMessage = "Failed to load lists: \(error.localizedDescription)"
            print("Error loading lists: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Save Spot
    
    func saveSpot(
        placeId: String,
        name: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        types: [String]?,
        toListId: UUID
    ) async throws {
        // First, upsert the spot
        try await service.upsertSpot(
            placeId: placeId,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            types: types
        )
        
        // Then, add it to the list
        try await service.saveSpotToList(placeId: placeId, listId: toListId)
    }
    
    // MARK: - Remove Spot
    
    func removeSpot(placeId: String, fromListId: UUID) async throws {
        try await service.removeSpotFromList(placeId: placeId, listId: fromListId)
    }
    
    // MARK: - Get Spots in List
    
    func getSpotsInList(listId: UUID) async throws -> [SpotWithMetadata] {
        return try await service.getSpotsInList(listId: listId)
    }
    
    // MARK: - Get Spot Count
    
    func getSpotCount(listId: UUID) async throws -> Int {
        return try await service.getSpotCount(listId: listId)
    }
    
    // MARK: - Check Lists
    
    func getListsContainingSpot(placeId: String) async throws -> [UUID] {
        return try await service.getListsContainingSpot(placeId: placeId)
    }
}
```

---

## Step 7: Integrate with Your UI

Now integrate the saving functionality into your existing views.

### 7.1 Update SearchView to Add Save Button

In `SearchView.swift`, add a save button to each place result:

```swift
// Add this to your SearchView
@StateObject private var locationSavingVM = LocationSavingViewModel()
@State private var selectedListId: UUID?
@State private var showListPicker = false

// In your autocompleteResultRow function, add a save button:
Button(action: {
    showListPicker = true
}) {
    Image(systemName: "bookmark")
        .foregroundColor(.blue)
}
.sheet(isPresented: $showListPicker) {
    ListPickerView(
        lists: locationSavingVM.userLists,
        onSelect: { listId in
            Task {
                await savePlaceToList(result, listId: listId)
            }
        }
    )
}

// Add this function:
private func savePlaceToList(_ result: PlaceAutocompleteResult, listId: UUID) async {
    do {
        // Get coordinates if available
        let lat = result.coordinate?.latitude
        let lng = result.coordinate?.longitude
        
        try await locationSavingVM.saveSpot(
            placeId: result.placeId,
            name: result.name,
            address: result.address,
            latitude: lat,
            longitude: lng,
            types: result.types,
            toListId: listId
        )
        
        // Show success message
        print("Saved to list!")
    } catch {
        print("Error saving spot: \(error)")
    }
}
```

### 7.2 Create ListPickerView

Create a new file: `Spots.Test/ListPickerView.swift`

```swift
import SwiftUI

struct ListPickerView: View {
    let lists: [UserList]
    let onSelect: (UUID) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(lists) { list in
                    Button(action: {
                        onSelect(list.id)
                        dismiss()
                    }) {
                        HStack {
                            Text(list.displayName)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Save to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

### 7.3 Create SavedSpotsView

Create a new file: `Spots.Test/SavedSpotsView.swift`

```swift
import SwiftUI

struct SavedSpotsView: View {
    let list: UserList
    @StateObject private var viewModel = LocationSavingViewModel()
    @State private var spots: [SpotWithMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if isLoading {
                ProgressView()
            } else if spots.isEmpty {
                Text("No spots saved yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(spots) { spotWithMetadata in
                    SpotRow(spot: spotWithMetadata.spot)
                }
            }
        }
        .navigationTitle(list.displayName)
        .task {
            await loadSpots()
        }
    }
    
    private func loadSpots() async {
        isLoading = true
        do {
            spots = try await viewModel.getSpotsInList(listId: list.id)
        } catch {
            errorMessage = "Failed to load spots: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct SpotRow: View {
    let spot: Spot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.name)
                .font(.headline)
            if let address = spot.address {
                Text(address)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

---

## Step 8: Test the Integration

### 8.1 Test Saving a Spot

1. Run your app
2. Go to Search view
3. Search for a place
4. Tap the save/bookmark button
5. Select a list
6. Verify the spot was saved

### 8.2 Test Viewing Saved Spots

1. Navigate to a list view
2. Verify saved spots appear
3. Check that they're ordered by recency (most recent first)

### 8.3 Test Removing a Spot

1. In a list view, add a delete/swipe action
2. Remove a spot
3. Verify it disappears from the list

---

## Step 9: Handle Edge Cases

### 9.1 Network Errors

Add error handling in your ViewModel:

```swift
func saveSpot(...) async throws {
    do {
        try await service.upsertSpot(...)
        try await service.saveSpotToList(...)
    } catch {
        // Handle network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                throw LocationSavingError.noInternet
            case .timedOut:
                throw LocationSavingError.timeout
            default:
                throw LocationSavingError.unknown
            }
        }
        throw error
    }
}
```

### 9.2 Duplicate Prevention

The database already prevents duplicates with the unique constraint, but you can check before saving:

```swift
func isSpotInList(placeId: String, listId: UUID) async throws -> Bool {
    let lists = try await service.getListsContainingSpot(placeId: placeId)
    return lists.contains(listId)
}
```

### 9.3 Loading States

Show loading indicators while saving:

```swift
@Published var isSaving = false

func saveSpot(...) async throws {
    isSaving = true
    defer { isSaving = false }
    
    try await service.upsertSpot(...)
    try await service.saveSpotToList(...)
}
```

---

## Troubleshooting

### Issue: "relation does not exist"
**Solution:** Make sure you ran the migration script completely.

### Issue: "permission denied"
**Solution:** Check that RLS policies are set up correctly and the user is authenticated.

### Issue: Lists not appearing
**Solution:** 
1. Check if lists exist in the database
2. Verify user is authenticated
3. Run the migration helper for existing users

### Issue: Spots not saving
**Solution:**
1. Check network connection
2. Verify user is authenticated
3. Check Supabase logs for errors
4. Verify the `upsert_spot` function exists

---

## Next Steps (Future Features)

Once this is working, you can add:

1. **Custom Lists**: Allow users to create their own lists
2. **List Management**: Rename, delete, reorder lists
3. **Spot Details**: Show more info when viewing a saved spot
4. **Social Features**: Share lists, see friends' spots
5. **Offline Support**: Cache spots locally
6. **Search Saved Spots**: Search within saved spots
7. **Categories/Tags**: Add tags to spots

---

## Summary Checklist

- [ ] Step 1: Run database migration in Supabase
- [ ] Step 2: Create lists for existing users
- [ ] Step 3: Test schema with SQL queries
- [ ] Step 4: Create Swift data models
- [ ] Step 5: Create LocationSavingService
- [ ] Step 6: Create LocationSavingViewModel
- [ ] Step 7: Integrate with UI (SearchView, ListPickerView, SavedSpotsView)
- [ ] Step 8: Test saving, viewing, and removing spots
- [ ] Step 9: Handle edge cases and errors

Good luck! 🚀

