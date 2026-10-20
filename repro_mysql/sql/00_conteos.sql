-- Conteos de objetos tras la carga (los docs esperan 66 / 9 / 7 / 3 / 1).
SELECT 'tablas' AS objeto, COUNT(*) AS cantidad FROM information_schema.tables
 WHERE table_schema = 'bna' AND table_type = 'BASE TABLE'
UNION ALL SELECT 'vistas',   COUNT(*) FROM information_schema.views    WHERE table_schema = 'bna'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'bna'
UNION ALL SELECT 'routines', COUNT(*) FROM information_schema.routines WHERE routine_schema = 'bna'
UNION ALL SELECT 'eventos',  COUNT(*) FROM information_schema.events   WHERE event_schema = 'bna'
UNION ALL SELECT 'fks',      COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema = 'bna'
UNION ALL SELECT 'checks',   COUNT(*) FROM information_schema.check_constraints WHERE constraint_schema = 'bna'
UNION ALL SELECT 'columnas', COUNT(*) FROM information_schema.columns c
  JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
 WHERE c.table_schema = 'bna' AND t.table_type = 'BASE TABLE';

SET @conteo = CONCAT_WS(' / ',
  (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'bna' AND table_type = 'BASE TABLE'),
  (SELECT COUNT(*) FROM information_schema.views    WHERE table_schema = 'bna'),
  (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'bna'),
  (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'bna'),
  (SELECT COUNT(*) FROM information_schema.events   WHERE event_schema = 'bna'));
CALL repro.reg('-', 'La base tiene los objetos que promete la guia',
  'Se contaron tablas / vistas / triggers / rutinas / eventos en la base cargada.',
  '66 / 9 / 7 / 3 / 1, como dicen GUIA_EJECUCION.md y verificar_bna.ps1',
  @conteo, @conteo = '66 / 9 / 7 / 3 / 1',
  'La carga crea todo lo que el equipo documento; los problemas son de diseno y logica, no de instalacion.');
