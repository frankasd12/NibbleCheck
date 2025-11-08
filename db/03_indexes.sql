-- Case-insensitive uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS uniq_food_name_ci ON foods (LOWER(canonical_name));
CREATE UNIQUE INDEX IF NOT EXISTS uniq_syn_name_ci  ON synonyms (LOWER(name));

-- Fuzzy search (trigram)
CREATE INDEX IF NOT EXISTS idx_foods_trgm    ON foods    USING gin (canonical_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_synonyms_trgm ON synonyms USING gin (name gin_trgm_ops);

-- Prevent duplicate rules per (food, condition)
CREATE UNIQUE INDEX IF NOT EXISTS uniq_rules_food_condition ON rules (food_id, condition);
