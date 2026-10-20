-- Esquema auxiliar de la reproduccion (vive fuera de bna; el DROP DATABASE bna no lo borra).
-- Cada comprobacion registra aqui su veredicto en lenguaje simple.
DROP DATABASE IF EXISTS repro;
CREATE DATABASE repro CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE TABLE repro.resultado (
  n           INT AUTO_INCREMENT PRIMARY KEY,
  bug         VARCHAR(10)  NOT NULL,
  titulo      VARCHAR(200) NOT NULL,
  que_se_hizo VARCHAR(500) NOT NULL,
  esperado    VARCHAR(500) NOT NULL,
  obtenido    VARCHAR(500) NOT NULL,
  ok          TINYINT(1)   NOT NULL,
  significa   VARCHAR(500) NOT NULL
);

DELIMITER $$
CREATE PROCEDURE repro.reg(
  IN p_bug VARCHAR(10), IN p_titulo VARCHAR(200), IN p_hizo VARCHAR(500),
  IN p_esperado VARCHAR(500), IN p_obtenido VARCHAR(500), IN p_ok TINYINT,
  IN p_significa VARCHAR(500))
BEGIN
  INSERT INTO repro.resultado (bug, titulo, que_se_hizo, esperado, obtenido, ok, significa)
  VALUES (p_bug, p_titulo, p_hizo, p_esperado, COALESCE(p_obtenido, '(sin dato)'), COALESCE(p_ok, 0), p_significa);
END $$
DELIMITER ;
