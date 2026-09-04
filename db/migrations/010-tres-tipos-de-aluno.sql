-- =============================================================================
-- 010 - Tres tipos de aluno: contrato completo, contrato parcial, sem contrato
-- =============================================================================
-- DEPENDE DA 008. Correr depois da 009.
--
-- O QUE RESOLVE
--   A 008 assumiu dois tipos. Sao tres. O contrato PARCIAL tem o preco do
--   contrato (o do menu) mas NAO tem almoco automatico - o aluno marca-o. As
--   duas coisas que o tem_contrato da 008 decidia juntas - preco e almoco
--   automatico - deixam de andar juntas.
--
-- O QUE NAO MUDA
--   Nenhum valor ja cobrado. O reservas_guard, a preco_para_reserva, o
--   reservar_refeicao e a reativar_reserva_cancelada ficam como estao: leem o
--   tem_contrato, que continua a existir e a dizer o mesmo (completo e parcial
--   sao true, sem e false).
--
-- Ver docs/superpowers/specs/2026-09-04-contract-types-v2-design.md
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- SECCAO 1 - tipo_contrato, e o tem_contrato passa a ser derivado
-- -----------------------------------------------------------------------------
-- Uma coluna que a cantina escolhe, e dois comportamentos derivados dela:
--   preco              -> tem_contrato = (tipo_contrato <> 'sem')
--   almoco automatico  -> tipo_contrato = 'completo'
--
-- O tem_contrato fica, mas GERADO. Apaga-lo obrigava a mexer em todos os
-- leitores por uma renomeacao sem ganho nenhum; mante-lo como coluna normal
-- sincronizada por trigger era uma segunda fonte de verdade. Gerado e uma
-- fonte de verdade so, com o nome antigo ainda valido - e um UPDATE ao
-- tem_contrato passa a ser ERRO do Postgres em vez de uma divergencia
-- silenciosa, o que apanha qualquer teste ou script que ainda o escreva.
--
-- A ORDEM IMPORTA: uma coluna gerada nao se preenche a mao, por isso primeiro
-- nasce a nova, preenche-se a partir da antiga, e so depois a antiga da lugar
-- a gerada.
ALTER TABLE public.alunos ADD COLUMN tipo_contrato text;

UPDATE public.alunos
   SET tipo_contrato = CASE WHEN tem_contrato THEN 'completo' ELSE 'sem' END;

ALTER TABLE public.alunos ALTER COLUMN tipo_contrato SET NOT NULL;
ALTER TABLE public.alunos ALTER COLUMN tipo_contrato SET DEFAULT 'completo';
ALTER TABLE public.alunos ADD CONSTRAINT alunos_tipo_contrato_chk
  CHECK (tipo_contrato IN ('completo', 'parcial', 'sem'));

ALTER TABLE public.alunos DROP COLUMN tem_contrato;
ALTER TABLE public.alunos ADD COLUMN tem_contrato boolean
  GENERATED ALWAYS AS (tipo_contrato <> 'sem') STORED;

-- A lista de colunas escreviveis pelo authenticated continua a ser exatamente
-- (nome, email): o tipo_contrato nao entra, e o tem_contrato e gerado e nao
-- se escreve. Repetido aqui pela mesma razao da 008 e da 009 - quem correr por
-- ultimo na escola tem de deixar esta lista, e a verificacao no fim confirma.
REVOKE UPDATE ON public.alunos FROM authenticated;
GRANT  UPDATE (nome, email) ON public.alunos TO authenticated;

COMMIT;

-- =============================================================================
-- SECCAO 2 - O almoco automatico so para o contrato completo
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.criar_reservas_automaticas_almoco()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  IF NEW.tipo = 'almoco' THEN
    INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta)
    SELECT a.id, NEW.id, NEW.tipo, NEW.data, NEW.preco, true, false
    FROM alunos a
    WHERE a.tipo_contrato = 'completo'
    ON CONFLICT (aluno_id, data, tipo) DO NOTHING;
  END IF;
  RETURN NEW;
END; $function$;

-- Trigger AFTER INSERT: o NEW.tipo_contrato ja vem com o default aplicado.
CREATE OR REPLACE FUNCTION public.criar_reservas_almoco_novo_aluno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_local timestamp := now() AT TIME ZONE 'Europe/Lisbon';
  v_hoje  date      := v_local::date;
  v_hora  time      := v_local::time;
BEGIN
  IF NEW.tipo_contrato <> 'completo' THEN
    RETURN NEW;
  END IF;

  INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta)
  SELECT NEW.id, m.id, m.tipo, m.data, m.preco, true, false
  FROM menus m
  WHERE m.tipo = 'almoco'
    AND (m.data > v_hoje OR (m.data = v_hoje AND v_hora < TIME '09:00'))
  ON CONFLICT (aluno_id, data, tipo) DO NOTHING;

  RETURN NEW;
END; $$;

COMMIT;
