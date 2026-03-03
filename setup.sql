-- ╔══════════════════════════════════════════════════════════════╗
-- ║              RAAH — Supabase Database Setup                  ║
-- ║                                                               ║
-- ║  Run this SQL in your Supabase SQL Editor after creating      ║
-- ║  your project at https://supabase.com/dashboard               ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Enable pgvector extension for semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- User preferences table (long-term memory)
CREATE TABLE IF NOT EXISTS user_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    value TEXT NOT NULL,
    confidence DOUBLE PRECISION DEFAULT 0.5,
    extracted_from TEXT,
    embedding vector(1536),  -- OpenAI text-embedding-ada-002 dimensions
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Interactions log
CREATE TABLE IF NOT EXISTS interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    context_pois TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Spatial cache (for Overpass/Wikipedia data to reduce API calls)
CREATE TABLE IF NOT EXISTS spatial_cache (
    id TEXT PRIMARY KEY,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    data JSONB NOT NULL,
    source TEXT NOT NULL,  -- 'overpass', 'wikipedia', 'google_places'
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast spatial queries
CREATE INDEX IF NOT EXISTS idx_spatial_cache_location 
    ON spatial_cache (latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_spatial_cache_expiry 
    ON spatial_cache (expires_at);

-- Index for preference semantic search
CREATE INDEX IF NOT EXISTS idx_preferences_embedding 
    ON user_preferences 
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Function for semantic search
CREATE OR REPLACE FUNCTION match_preferences(
    query_embedding vector(1536),
    match_count INT DEFAULT 5,
    match_threshold FLOAT DEFAULT 0.7
)
RETURNS TABLE (
    id UUID,
    category TEXT,
    value TEXT,
    confidence DOUBLE PRECISION,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        up.id,
        up.category,
        up.value,
        up.confidence,
        1 - (up.embedding <=> query_embedding) AS similarity
    FROM user_preferences up
    WHERE 1 - (up.embedding <=> query_embedding) > match_threshold
    ORDER BY up.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Row Level Security (enable after testing)
-- ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE interactions ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE spatial_cache ENABLE ROW LEVEL SECURITY;

-- Cleanup function for expired cache
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM spatial_cache WHERE expires_at < NOW();
END;
$$;
