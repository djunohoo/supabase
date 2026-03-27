-- =============================================================================
-- PHAZE17 HUB — CLIENT SCHEMA
-- =============================================================================
-- Purpose: Power the public-facing Phaze17 Hub product platform.
-- Clients land, buy, track jobs, receive files. That's the whole game.
--
-- Auth:     Supabase Auth only. Passport.js is retired.
-- Admin:    Local instance only. Service role key. Never public.
-- Billing:  Orb for metering. Paddle for payments.
-- Prefix:   hub_*
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. CLIENT PROFILES
-- -----------------------------------------------------------------------------
-- Extends auth.users with client-facing profile data.
-- Created automatically on user signup via trigger.

CREATE TABLE IF NOT EXISTS hub_profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT,
  email         TEXT,                          -- denormalized for easy querying
  avatar_url    TEXT,
  paddle_customer_id TEXT,                     -- Paddle customer reference
  orb_customer_id    TEXT,                     -- Orb metering customer reference
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_hub_profiles_updated_at
  BEFORE UPDATE ON hub_profiles
  FOR EACH ROW EXECUTE FUNCTION p17_set_updated_at();

CREATE INDEX idx_hub_profiles_paddle ON hub_profiles(paddle_customer_id);
CREATE INDEX idx_hub_profiles_orb    ON hub_profiles(orb_customer_id);

ALTER TABLE hub_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can view own profile"
  ON hub_profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Clients can update own profile"
  ON hub_profiles FOR UPDATE
  USING (auth.uid() = id);


-- -----------------------------------------------------------------------------
-- 2. PRODUCTS
-- -----------------------------------------------------------------------------
-- The service catalog. Drives the storefront.

CREATE TABLE IF NOT EXISTS hub_products (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          TEXT UNIQUE NOT NULL,          -- e.g. 'stem-separation', 'mvp-studio'
  name          TEXT NOT NULL,
  description   TEXT,
  pricing_model TEXT NOT NULL DEFAULT 'usage', -- 'usage', 'fixed', 'quote'
  price_per_unit DECIMAL(10,4),               -- for usage: price per second
  currency      TEXT NOT NULL DEFAULT 'USD',
  status        TEXT NOT NULL DEFAULT 'active', -- 'active', 'coming_soon', 'retired'
  sort_order    INT DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_hub_products_updated_at
  BEFORE UPDATE ON hub_products
  FOR EACH ROW EXECUTE FUNCTION p17_set_updated_at();

ALTER TABLE hub_products ENABLE ROW LEVEL SECURITY;

-- Products are public read
CREATE POLICY "Anyone can view active products"
  ON hub_products FOR SELECT
  USING (status = 'active');

-- Seed the product catalog
INSERT INTO hub_products (slug, name, description, pricing_model, price_per_unit, status, sort_order) VALUES
  ('stem-separation',  'Phase 17 Stem Service',      'AI-powered stem separation. Pay per second. No subscriptions.', 'usage',  0.01,  'active',      1),
  ('mvp-studio',       'MVP Studio',                 'We build your app idea to MVP. Fast, clean, no fluff.',          'quote',  NULL,  'active',      2),
  ('streamer-hub',     'Streamer / Small-Biz Hub',   'Custom dashboards and automation for streamers and small biz.',  'quote',  NULL,  'active',      3),
  ('twitch-bots',      'Twitch Bots & Automation',   'Custom Twitch bots, overlays, and stream automation tools.',     'quote',  NULL,  'active',      4),
  ('metacrate',        'MetaCrate',                  'DJ music library taxonomy engine. Smart tagging, stem-aware.',   'usage',  NULL,  'coming_soon', 5)
ON CONFLICT (slug) DO NOTHING;


-- -----------------------------------------------------------------------------
-- 3. ORDERS
-- -----------------------------------------------------------------------------
-- A client purchased a product or initiated a service.

CREATE TABLE IF NOT EXISTS hub_orders (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     UUID NOT NULL REFERENCES hub_profiles(id) ON DELETE RESTRICT,
  product_id    UUID NOT NULL REFERENCES hub_products(id) ON DELETE RESTRICT,
  status        TEXT NOT NULL DEFAULT 'pending', -- 'pending','active','complete','cancelled','refunded'
  paddle_order_id TEXT,
  total_billed  DECIMAL(10,2),
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_hub_orders_updated_at
  BEFORE UPDATE ON hub_orders
  FOR EACH ROW EXECUTE FUNCTION p17_set_updated_at();

CREATE INDEX idx_hub_orders_client    ON hub_orders(client_id);
CREATE INDEX idx_hub_orders_product   ON hub_orders(product_id);
CREATE INDEX idx_hub_orders_status    ON hub_orders(status);
CREATE INDEX idx_hub_orders_created   ON hub_orders(created_at DESC);

ALTER TABLE hub_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can view own orders"
  ON hub_orders FOR SELECT
  USING (auth.uid() = client_id);

CREATE POLICY "Clients can create own orders"
  ON hub_orders FOR INSERT
  WITH CHECK (auth.uid() = client_id);


-- -----------------------------------------------------------------------------
-- 4. STEM JOBS
-- -----------------------------------------------------------------------------
-- Full lifecycle of a stem separation job.
-- This is the core revenue engine right now.

CREATE TABLE IF NOT EXISTS hub_stem_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID REFERENCES hub_orders(id) ON DELETE SET NULL,
  client_id       UUID NOT NULL REFERENCES hub_profiles(id) ON DELETE RESTRICT,
  status          TEXT NOT NULL DEFAULT 'uploaded',
                  -- 'uploaded' → 'queued' → 'processing' → 'complete' → 'delivered' → 'failed'
  input_filename  TEXT NOT NULL,
  input_file_url  TEXT,                        -- S3/GCS URL of uploaded file
  duration_sec    DECIMAL(10,3),               -- actual audio duration in seconds
  model_used      TEXT,                        -- e.g. 'htdemucs', 'htdemucs_ft'
  error_message   TEXT,                        -- populated on failure
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER set_hub_stem_jobs_updated_at
  BEFORE UPDATE ON hub_stem_jobs
  FOR EACH ROW EXECUTE FUNCTION p17_set_updated_at();

CREATE INDEX idx_hub_stem_jobs_client   ON hub_stem_jobs(client_id);
CREATE INDEX idx_hub_stem_jobs_status   ON hub_stem_jobs(status);
CREATE INDEX idx_hub_stem_jobs_created  ON hub_stem_jobs(created_at DESC);

ALTER TABLE hub_stem_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can view own stem jobs"
  ON hub_stem_jobs FOR SELECT
  USING (auth.uid() = client_id);

CREATE POLICY "Clients can create stem jobs"
  ON hub_stem_jobs FOR INSERT
  WITH CHECK (auth.uid() = client_id);


-- -----------------------------------------------------------------------------
-- 5. STEM JOB FILES
-- -----------------------------------------------------------------------------
-- Output files per job. One row per stem track delivered.

CREATE TABLE IF NOT EXISTS hub_stem_job_files (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id      UUID NOT NULL REFERENCES hub_stem_jobs(id) ON DELETE CASCADE,
  stem_type   TEXT NOT NULL,   -- 'vocals', 'drums', 'bass', 'other', 'guitar', 'piano'
  file_url    TEXT NOT NULL,   -- S3/GCS delivery URL
  file_size   BIGINT,          -- bytes
  expires_at  TIMESTAMPTZ,     -- signed URL expiry if applicable
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_hub_stem_files_job ON hub_stem_job_files(job_id);

ALTER TABLE hub_stem_job_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can view own stem files"
  ON hub_stem_job_files FOR SELECT
  USING (
    job_id IN (
      SELECT id FROM hub_stem_jobs WHERE client_id = auth.uid()
    )
  );


-- -----------------------------------------------------------------------------
-- 6. BILLING EVENTS
-- -----------------------------------------------------------------------------
-- Usage events emitted to Orb for metering.
-- One event per completed stem job. Orb aggregates and bills via Paddle.

CREATE TABLE IF NOT EXISTS hub_billing_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID NOT NULL REFERENCES hub_profiles(id) ON DELETE RESTRICT,
  job_id          UUID REFERENCES hub_stem_jobs(id) ON DELETE SET NULL,
  event_type      TEXT NOT NULL DEFAULT 'stem_seconds_processed',
  quantity        DECIMAL(10,3) NOT NULL,      -- seconds processed
  orb_event_id    TEXT,                        -- Orb's event ID after emit
  emitted_at      TIMESTAMPTZ,                 -- when we sent it to Orb
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_hub_billing_client  ON hub_billing_events(client_id);
CREATE INDEX idx_hub_billing_job     ON hub_billing_events(job_id);
CREATE INDEX idx_hub_billing_emitted ON hub_billing_events(emitted_at DESC);

ALTER TABLE hub_billing_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can view own billing events"
  ON hub_billing_events FOR SELECT
  USING (auth.uid() = client_id);


-- -----------------------------------------------------------------------------
-- AUTO-CREATE PROFILE ON SIGNUP TRIGGER
-- -----------------------------------------------------------------------------
-- When a new user signs up via Supabase Auth, auto-create their hub_profile.

CREATE OR REPLACE FUNCTION hub_handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO hub_profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION hub_handle_new_user();


-- =============================================================================
-- ARCHIVED: workspace_investments schema
-- The old hub used a workspace investment tracker for DJ collective finance.
-- That concept is shelved but the RLS patterns were solid.
-- See: phaze17-hub/sql/workspace_investments.sql (legacy)
-- =============================================================================
