CREATE TABLE IF NOT EXISTS foods (
  id SERIAL PRIMARY KEY,
  canonical_name TEXT NOT NULL,
  group_name TEXT,
  default_status food_status NOT NULL,
  notes TEXT,
  sources TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS synonyms (
  id SERIAL PRIMARY KEY,
  food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rules (
  id SERIAL PRIMARY KEY,
  food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
  condition JSONB NOT NULL,
  status food_status NOT NULL,
  rationale TEXT
);

CREATE TABLE IF NOT EXISTS inferences (
  id SERIAL PRIMARY KEY,
  image_url TEXT,
  detections JSONB,
  final_status food_status,
  kb_hits JSONB,
  user_feedback JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- updated_at trigger
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS push
BEGIN
  NEW.updated_at = now(); RETURN NEW;
END; push LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_updated_at ON foods;
CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON foods
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
