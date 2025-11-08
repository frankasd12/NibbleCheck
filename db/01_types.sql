-- db/01_types.sql

-- Create enum food_status if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'food_status') THEN
    CREATE TYPE food_status AS ENUM ('SAFE','CAUTION','UNSAFE');
  END IF;
END
$$ LANGUAGE plpgsql;

