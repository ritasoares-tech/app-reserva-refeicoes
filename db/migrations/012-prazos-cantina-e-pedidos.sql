-- =============================================================================
-- 012 - O prazo tambem vale para a cantina criar menus e para os pedidos especiais
-- =============================================================================
-- DEPENDE DA 003 (prazo_limite) E DA 005 (solicitar_cancelamento_especial).
-- Correr depois da 011.
--
-- O QUE RESOLVE (resposta da escola de 2026-11-07)
--   1. "Cantina consegue criar menus para o dia anterior e para o proprio dia,
--      ja depois das 9h." So o browser recusava, e so dias passados. Um almoco
--      criado depois das 9h ainda passava pelo alastramento da 001 e marcava o
--      almoco a todos os alunos com contrato completo - uma refeicao que aparece
--      depois do prazo, e que o aluno ve como "ja reservado". E muito
--      provavelmente isto o "aluno consegue reservar depois das 9h" da mesma
--      mensagem: o reservas_guard recusa a marcacao do aluno, testado.
--   3. "O aluno consegue pedir cancelamento especial ja depois de ter passado o
--      dia." O pedido especial passa por cima do LIMITE de 2 por mes, nunca do
--      PRAZO. A funcao nao olhava para o prazo.
--
-- A REGRA, NUMA LINHA: depois de prazo_limite(tipo, data) a refeicao esta
-- contada e comprada. Nada que se faca na app cria, marca ou pede para cancelar
-- uma refeicao depois disso.
--
-- O QUE NAO MUDA
--   - Mudar o prato de um menu ja fechado continua a poder-se: nao cria
--     refeicao nenhuma, so a descreve, e avisa os alunos.
--   - Apagar menus: fica como esta.
--   - Contextos de sistema (auth.uid() IS NULL - service_role, pg_cron,
--     migracoes) passam ao lado, como no reservas_guard.
--   - A aprovacao pela cantina de um pedido feito a tempo: ver a pergunta em
--     aberto (ponto 4 da mensagem da escola). Nao se decide aqui.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1 - menus_guard: a cantina so cria menus ainda dentro do prazo
-- -----------------------------------------------------------------------------
-- BEFORE, e por isso corre antes do AFTER INSERT do alastramento: um menu
-- recusado nao chega a marcar almoco a ninguem.
--
-- No UPDATE so interessa a data e o tipo - e a mesma porta, pelo lado: criar
-- para a semana que vem e depois mudar a data para ontem. O prato fica livre.
CREATE OR REPLACE FUNCTION public.menus_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.data IS NOT DISTINCT FROM OLD.data
     AND NEW.tipo IS NOT DISTINCT FROM OLD.tipo THEN
    RETURN NEW;
  END IF;

  IF now() >= public.prazo_limite(NEW.tipo, NEW.data) THEN
    RAISE EXCEPTION 'Prazo ultrapassado: ja nao se pode criar este menu para este dia'
      USING ERRCODE = 'RES06';
  END IF;

  RETURN NEW;
END; $function$;

COMMENT ON FUNCTION public.menus_guard() IS
  'Recusa a sessoes com utilizador criar um menu, ou mudar-lhe a data ou o tipo, '
  'depois de prazo_limite(tipo, data). Contextos de sistema passam ao lado.';

REVOKE EXECUTE ON FUNCTION public.menus_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_menus_guard ON public.menus;
CREATE TRIGGER trg_menus_guard
  BEFORE INSERT OR UPDATE OF data, tipo ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.menus_guard();

-- -----------------------------------------------------------------------------
-- 2 - solicitar_cancelamento_especial: so dentro do prazo
-- -----------------------------------------------------------------------------
-- Corpo da 005 inteiro (igual ao pg_get_functiondef de 2026-11-07), mais UMA
-- condicao no primeiro IF. Mesma assinatura, por isso os GRANT da 005 ficam.
CREATE OR REPLACE FUNCTION public.solicitar_cancelamento_especial(
  p_reserva_id uuid,
  p_motivo text,
  p_troca_por_lanche boolean DEFAULT false,
  p_lanche_substituto text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_id    uuid;
  v_aluno uuid := auth.uid();
BEGIN
  IF v_aluno IS NULL THEN
    RAISE EXCEPTION 'E preciso sessao iniciada para pedir um cancelamento';
  END IF;

  -- r.ativa e a coluna gerada da 001, que substituiu a coluna booleana antiga.
  -- NAO escrever aqui o nome dessa coluna: a verificacao 2 procura-o em prosrc,
  -- que inclui os comentarios, e passaria a acusar esta linha.
  IF NOT EXISTS (
    SELECT 1 FROM reservas r
    WHERE r.id = p_reserva_id AND r.aluno_id = v_aluno AND r.ativa AND r.tipo = 'almoco'
  ) THEN
    RAISE EXCEPTION 'Reserva invalida para cancelamento especial';
  END IF;

  -- 012: o pedido passa por cima do limite mensal, nunca do prazo.
  IF EXISTS (
    SELECT 1 FROM reservas r
    WHERE r.id = p_reserva_id AND now() >= public.prazo_limite(r.tipo, r.data)
  ) THEN
    RAISE EXCEPTION 'Prazo ultrapassado: ja nao se pode pedir o cancelamento desta refeicao'
      USING ERRCODE = 'RES06';
  END IF;

  IF EXISTS (
    SELECT 1 FROM cancelamentos_especiais
    WHERE reserva_id = p_reserva_id AND status = 'pendente'
  ) THEN
    RAISE EXCEPTION 'Ja existe um pedido pendente para esta reserva';
  END IF;

  INSERT INTO cancelamentos_especiais
    (aluno_id, reserva_id, motivo, troca_por_lanche, lanche_substituto, status)
  VALUES
    (v_aluno, p_reserva_id, p_motivo, p_troca_por_lanche, p_lanche_substituto, 'pendente')
  RETURNING id INTO v_id;

  RETURN v_id;
END; $fn$;

COMMIT;

-- =============================================================================
-- VERIFICACAO (cada uma sozinha no editor SQL: so mostra o ultimo resultado)
-- =============================================================================
-- 1) O trigger existe e esta ligado:
--
--   SELECT tgname, tgenabled FROM pg_trigger
--   WHERE tgrelid = 'public.menus'::regclass AND tgname = 'trg_menus_guard';
--   Esperado: uma linha, tgenabled = O.
--
-- 2) A funcao do pedido tem a condicao nova:
--
--   SELECT prosrc LIKE '%prazo_limite%' AS tem_prazo
--   FROM pg_proc WHERE proname = 'solicitar_cancelamento_especial';
--   Esperado: true.
--
-- 3) Nenhum dado muda: esta migracao so acrescenta recusas.
--
--   SELECT count(*) FROM menus;  SELECT count(*) FROM cancelamentos_especiais;
--   Esperado: iguais aos de antes de aplicar.
-- =============================================================================
