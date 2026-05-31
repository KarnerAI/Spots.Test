-- Create autocomplete_cache table for persistent autocomplete result caching.
-- This reduces Google Places Autocomplete API calls by reusing results across app sessions.
-- Results are stored with a 1-week TTL and automatically cleaned up.

CREATE TABLE IF NOT EXISTS autocomplete_cache (
    cache_key TEXT PRIMARY KEY,
    results_json TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

-- Index to efficiently filter expired rows
CREATE INDEX IF NOT EXISTS idx_autocomplete_cache_expires ON autocomplete_cache(expires_at);

-- Enable RLS
ALTER TABLE autocomplete_cache ENABLE ROW LEVEL SECURITY;

-- Allow all authenticated users to read and write cache entries.
-- Autocomplete results are not user-specific, so sharing across users is fine.
CREATE POLICY "Authenticated users can read autocomplete cache"
    ON autocomplete_cache FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert autocomplete cache"
    ON autocomplete_cache FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update autocomplete cache"
    ON autocomplete_cache FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Optional: scheduled cleanup of expired entries (run periodically via cron or Supabase Edge Function)
-- DELETE FROM autocomplete_cache WHERE expires_at < NOW();
