-- db/02_tables.sql
-- Core tables for NibbleCheck

-- =========================================================
-- foods
--  - canonical_name: canonical food name ("grape", "white rice")
--  - group_name: category ("fruit", "protein", etc.)
--  - default_status: SAFE / CAUTION / UNSAFE (food_status enum from 01_types.sql)
--  - notes: human-readable guidance (portion, caveats)
--  - sources: array of citation names / URLs
--  - created_at / updated_at: timestamps
-- =========================================================
CREATE TABLE IF NOT EXISTS foods (
  id             SERIAL PRIMARY KEY,
  canonical_name TEXT NOT NULL,
  group_name     TEXT,
  default_status food_status NOT NULL,
  notes          TEXT,
  sources        TEXT[],
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now()
);

-- =========================================================
-- synonyms
--  - maps alternate labels / spellings to a food
-- =========================================================
CREATE TABLE IF NOT EXISTS synonyms (
  id         SERIAL PRIMARY KEY,
  food_id    INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================================================
-- rules
--  - per-food safety rules that can override default_status
--  - condition: JSONB to hold things like "tiny amount", "certain breeds", etc.
-- =========================================================
CREATE TABLE IF NOT EXISTS rules (
  id         SERIAL PRIMARY KEY,
  food_id    INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  condition  JSONB NOT NULL,
  status     food_status NOT NULL,
  rationale  TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- =========================================================
-- inferences
--  - stores model outputs for auditing / analytics
-- =========================================================
CREATE TABLE IF NOT EXISTS inferences (
  id            SERIAL PRIMARY KEY,
  uploaded_at   TIMESTAMPTZ DEFAULT now(),
  image_url     TEXT,
  detections    JSONB,
  final_status  food_status,
  kb_hits       JSONB,
  user_feedback JSONB
);

-- =========================================================
-- barcode_items
--  - maps barcodes to ingredient text so we can reuse the same
--    ingredients resolver as the text flow
-- =========================================================
CREATE TABLE IF NOT EXISTS barcode_items (
  barcode          TEXT PRIMARY KEY,
  display_name     TEXT NOT NULL,
  ingredients_text TEXT,
  brand            TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- =========================================================
-- updated_at helper + triggers
-- =========================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- foods.updated_at
DROP TRIGGER IF EXISTS trg_foods_updated_at ON foods;
CREATE TRIGGER trg_foods_updated_at
BEFORE UPDATE ON foods
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- synonyms.updated_at
DROP TRIGGER IF EXISTS trg_synonyms_updated_at ON synonyms;
CREATE TRIGGER trg_synonyms_updated_at
BEFORE UPDATE ON synonyms
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- rules.updated_at
DROP TRIGGER IF EXISTS trg_rules_updated_at ON rules;
CREATE TRIGGER trg_rules_updated_at
BEFORE UPDATE ON rules
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- barcode_items.updated_at
DROP TRIGGER IF EXISTS trg_barcode_items_updated_at ON barcode_items;
CREATE TRIGGER trg_barcode_items_updated_at
BEFORE UPDATE ON barcode_items
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
