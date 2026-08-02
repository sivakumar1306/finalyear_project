-- Create firmware_updates table for OTA smart ring firmware releases
CREATE TABLE IF NOT EXISTS firmware_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL,
    hardware_model TEXT DEFAULT 'QRing V1',
    file_url TEXT NOT NULL,
    release_notes TEXT,
    is_mandatory BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE firmware_updates ENABLE ROW LEVEL SECURITY;

-- Allow public read access for firmware releases
CREATE POLICY "Allow public read access for firmware updates"
    ON firmware_updates FOR SELECT
    USING (true);
