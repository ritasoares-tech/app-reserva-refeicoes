-- =============================================================================
-- ANTES de aplicar a 011 - quem vai ficar bloqueado no momento em que ela entra
-- =============================================================================
-- Colar o ficheiro INTEIRO no editor de SQL, com a 011 AINDA POR APLICAR.
-- Devolve uma tabela so: aluno | mes por pagar | total | bloqueia. So le.
--
-- A regra da 011: um mes por pagar de ha dois meses ou mais bloqueia sempre; o
-- mes anterior so bloqueia a partir do dia 15. (Ainda nao ha excecoes da
-- cantina, porque a tabela desbloqueios so nasce com a 011.)
--
-- Aplicada logo a seguir a 001 - que apaga meses_em_divida - isto sai vazio.
-- =============================================================================

WITH por_pagar AS (
  SELECT a.nome, md.ano, md.mes, md.total, make_date(md.ano, md.mes, 1) AS inicio
  FROM meses_em_divida md
  JOIN alunos a ON a.id = md.aluno_id
  WHERE make_date(md.ano, md.mes, 1) < date_trunc('month', CURRENT_DATE)::date
    AND NOT EXISTS (SELECT 1 FROM meses_liquidados ml
                    WHERE ml.aluno_id = md.aluno_id AND ml.ano = md.ano AND ml.mes = md.mes)
)
SELECT nome AS aluno,
       lpad(mes::text, 2, '0') || '/' || ano AS mes_por_pagar,
       total,
       CASE
         WHEN inicio < (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::date
           THEN 'SIM, logo (dois meses ou mais)'
         WHEN EXTRACT(DAY FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int >= 15
           THEN 'SIM, logo (mes anterior, ja passou o dia 15)'
         ELSE 'a partir do dia 15, se nao pagar'
       END AS bloqueia
FROM por_pagar
ORDER BY nome, ano, mes;
