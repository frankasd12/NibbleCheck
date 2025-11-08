SELECT extname FROM pg_extension WHERE extname='pg_trgm';
SELECT typname FROM pg_type WHERE typname='food_status';

SELECT 'foods' AS t, COUNT(*) FROM foods
UNION ALL SELECT 'synonyms', COUNT(*) FROM synonyms
UNION ALL SELECT 'rules', COUNT(*) FROM rules;
