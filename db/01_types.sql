DO push
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='food_status') THEN
    CREATE TYPE food_status AS ENUM ('SAFE','CAUTION','UNSAFE');
  END IF;
END push;
