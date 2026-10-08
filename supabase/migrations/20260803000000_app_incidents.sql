-- Migration: 20260803000000_app_incidents.sql
-- Table to store application crash logs and incidents from Frontend (Flutter/Android) and Backend (FastAPI).

CREATE TABLE IF NOT EXISTS public.app_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    source TEXT NOT NULL, -- 'flutter_ui', 'flutter_async', 'android_native', 'backend_fastapi', 'client_rest'
    error_type TEXT,
    message TEXT NOT NULL,
    stack_trace TEXT,
    device_info JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.app_incidents ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to insert their own or app incidents
CREATE POLICY "Allow authenticated insert into app_incidents"
    ON public.app_incidents
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Allow anonymous users (e.g. before login or pre-auth crashes) to report incidents
CREATE POLICY "Allow anon insert into app_incidents"
    ON public.app_incidents
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Allow service role full access for monitoring/backend analytics
CREATE POLICY "Allow service_role full access on app_incidents"
    ON public.app_incidents
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Index for fast queries by created_at and source
CREATE INDEX IF NOT EXISTS idx_app_incidents_created_at ON public.app_incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_incidents_source ON public.app_incidents(source);
CREATE INDEX IF NOT EXISTS idx_app_incidents_user_id ON public.app_incidents(user_id);
