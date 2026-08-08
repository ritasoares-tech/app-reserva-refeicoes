-- =============================================================================
-- 001 - Modelo de reservas
-- =============================================================================
-- Resolve: D1, I1, B4, D2, B-DUPLO, D6, I3 (ver docs/internal-findings.md)
--
-- O QUE FAZ
--   Passa a haver um unico estado de cancelamento (cancelamento_tipo, texto).
--   A coluna booleana `cancelada` desaparece e e substituida por `ativa`, uma
--   coluna calculada pela propria base de dados a partir do estado, que por isso
--   nunca pode ficar dessincronizada.
--   Passa a existir no maximo uma reserva por aluno + dia + tipo de refeicao.
--   Reservar depois de cancelar passa a reativar a mesma linha, em vez de criar
--   uma nova (era isto que permitia dois pequenos-almocos no mesmo dia).
--
-- ANTES DE CORRER
--   1. Correr no SQL Editor do Supabase, de uma so vez. Esta tudo dentro de uma
--      transacao: ou passa tudo, ou nao passa nada.
--   2. A tabela `alunos` NAO e tocada. O script verifica a contagem no inicio e
--      no fim e aborta se o numero mudar.
--   3. As reservas atuais sao apagadas (dados descartaveis, decidido). Os alunos,
--      os menus e as contas mantem-se.
--   4. Depois deste script a aplicacao SO funciona com o JS novo. Aplicar os dois
--      juntos.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Rede de seguranca: guardar a contagem de alunos
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE _guarda_alunos ON COMMIT DROP AS
SELECT count(*) AS total FROM alunos;

DO $$
DECLARE n bigint;
BEGIN
  SELECT total INTO n FROM _guarda_alunos;
  RAISE NOTICE 'Alunos antes da migracao: %', n;
  IF n = 0 THEN
    RAISE EXCEPTION 'A tabela alunos esta vazia. Isto nao devia acontecer - script abortado.';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Remover o trigger que corrompe meses_em_divida (D6, I1 ponto 2)
-- -----------------------------------------------------------------------------
-- Tem de sair antes de mexer na coluna: e ele que soma a dobrar, e le `cancelada`.
DROP TRIGGER  IF EXISTS trigger_atualizar_meses_divida ON reservas;
DROP FUNCTION IF EXISTS atualizar_meses_divida();

-- -----------------------------------------------------------------------------
-- 2. Limpar as tabelas de movimento
-- -----------------------------------------------------------------------------
-- Sem CASCADE de proposito: se alguma tabela nao listada depender destas, o script
-- falha aqui em vez de apagar coisas em silencio.
TRUNCATE reservas, meses_em_divida, meses_liquidados, notificacoes,
         cancelamentos_especiais;

-- -----------------------------------------------------------------------------
-- 3. Verificar que os menus existentes nao impedem a regra de unicidade (D3)
-- -----------------------------------------------------------------------------
-- Os menus nao sao apagados. Se ja houver dois menus do mesmo tipo no mesmo dia,
-- a restricao nao pode ser criada e e preciso decidir manualmente qual fica.
DO $$
DECLARE d record; n int := 0;
BEGIN
  FOR d IN
    SELECT data, tipo, count(*) AS c FROM menus GROUP BY data, tipo HAVING count(*) > 1
  LOOP
    RAISE WARNING 'Menu duplicado: % / % (% linhas)', d.data, d.tipo, d.c;
    n := n + 1;
  END LOOP;
  IF n > 0 THEN
    RAISE EXCEPTION 'Existem % combinacoes data/tipo duplicadas em menus. Resolver antes de continuar.', n;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. Substituir `cancelada` por `ativa` (calculada)
-- -----------------------------------------------------------------------------
-- Sem CASCADE: se existir alguma vista ou indice a depender de `cancelada`, isto
-- rebenta e ficamos a saber. Funcoes em plpgsql NAO impedem o DROP (o corpo so e
-- lido em execucao), por isso todas as que liam a coluna sao tratadas abaixo.
ALTER TABLE reservas DROP COLUMN cancelada;

ALTER TABLE reservas ADD COLUMN ativa boolean
  GENERATED ALWAYS AS (cancelamento_tipo IS NULL OR cancelamento_tipo = 'reactivated') STORED;

COMMENT ON COLUMN reservas.cancelamento_tipo IS
  'Estado da reserva: NULL = ativa | reactivated = cancelada e reposta | user = cancelada pelo aluno | payment = servida e liquidada';
COMMENT ON COLUMN reservas.ativa IS
  'Calculada. Verdadeira quando a refeicao vai ser servida e cobrada. Nao editar.';

-- -----------------------------------------------------------------------------
-- 5. Unicidade (D2, D3, B-DUPLO)
-- -----------------------------------------------------------------------------
ALTER TABLE reservas
  ADD CONSTRAINT reservas_aluno_data_tipo_key UNIQUE (aluno_id, data, tipo);

ALTER TABLE menus
  ADD CONSTRAINT menus_data_tipo_key UNIQUE (data, tipo);

-- Uma linha de divida por aluno e por mes.
-- Descoberto ao extrair o esquema real: esta restricao NAO existia. O trigger
-- atualizar_meses_divida (removido na seccao 1) contava com ela - apanhava
-- `unique_violation` para decidir entre inserir e somar. Sem restricao nenhuma,
-- essa excecao nunca acontecia e o trigger inseria sempre uma linha nova. Ou
-- seja, nao era so somar a dobrar como estava escrito no D6: acumulava linhas
-- repetidas para o mesmo aluno e o mesmo mes, sem limite.
-- Depois desta migracao so `fechar_mes_anterior` escreve aqui, e essa apaga
-- antes de inserir. A restricao existe para o caso de alguem (ou alguma politica
-- permissiva) voltar a inserir por fora: `obter_divida_por_mes` le esta tabela
-- sem agrupar, por isso uma linha repetida aparecia como um mes duplicado no
-- ecra do aluno.
ALTER TABLE meses_em_divida
  ADD CONSTRAINT meses_em_divida_aluno_ano_mes_key UNIQUE (aluno_id, ano, mes);

-- -----------------------------------------------------------------------------
-- 6. Almoco automatico: criado so pela base de dados, uma vez (I3)
-- -----------------------------------------------------------------------------
-- Mudancas: deixa de escrever `cancelada` (a coluna ja nao existe, sem isto o
-- trigger rebentava ao criar um menu) e passa a ignorar reservas ja existentes.
CREATE OR REPLACE FUNCTION public.criar_reservas_automaticas_almoco()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.tipo = 'almoco' THEN
    INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta)
    SELECT a.id, NEW.id, NEW.tipo, NEW.data, NEW.preco, true, false
    FROM alunos a
    ON CONFLICT (aluno_id, data, tipo) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;

-- -----------------------------------------------------------------------------
-- 7. Reservar = inserir ou reativar (D2, B-DUPLO, parte de F6)
-- -----------------------------------------------------------------------------
-- O preco, o tipo e a data passam a vir do menu e nao do navegador.
-- Uma reserva liquidada ('payment') nunca e reativada por aqui.
--
-- ERROS QUE O JS TEM DE DISTINGUIR (ler error.code, nao a mensagem):
--   RES01 - ja existe uma reserva ativa para este aluno/dia/refeicao. Normalmente
--           significa que o ecra esta dessincronizado (era isto o bug dos dois
--           pequenos-almocos). O JS deve recarregar a lista, nao insistir.
--   RES02 - a reserva desse dia ja foi liquidada. Nao pode voltar a ficar ativa
--           sem a cantina desfazer a liquidacao.
--   RES03 - o menu nao existe.
-- Sem estes codigos a funcao devolvia void em silencio e o JS dizia "reservado"
-- sem nada ter mudado.
CREATE OR REPLACE FUNCTION public.reservar_refeicao(p_menu_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m record;
  v_estado text;
BEGIN
  SELECT id, data, tipo, preco INTO m FROM menus WHERE id = p_menu_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Menu inexistente' USING ERRCODE = 'RES03';
  END IF;

  INSERT INTO reservas (aluno_id, menu_id, data, tipo, preco, is_dieta, automatico, cancelamento_tipo)
  VALUES (auth.uid(), m.id, m.data, m.tipo, m.preco, false, false, NULL)
  ON CONFLICT (aluno_id, data, tipo) DO UPDATE
    SET cancelamento_tipo = 'reactivated',
        menu_id           = EXCLUDED.menu_id,
        preco             = EXCLUDED.preco
    WHERE reservas.cancelamento_tipo = 'user';

  -- FOUND fica falso quando houve conflito e o WHERE acima nao deixou reativar,
  -- ou seja: existe uma linha e nao esta em 'user'. Descobrir em que estado esta
  -- para dizer ao aluno o que se passa.
  IF NOT FOUND THEN
    SELECT r.cancelamento_tipo INTO v_estado
    FROM reservas r
    WHERE r.aluno_id = auth.uid() AND r.data = m.data AND r.tipo = m.tipo;

    IF v_estado = 'payment' THEN
      RAISE EXCEPTION 'Esta refeicao ja foi liquidada e nao pode ser reservada de novo'
        USING ERRCODE = 'RES02';
    ELSE
      -- NULL ou 'reactivated' (ambos ativos). Se nao veio nada, a linha desapareceu
      -- entre o INSERT e este SELECT; e o mesmo conselho para o JS: recarregar.
      RAISE EXCEPTION 'Ja tens uma reserva para esta refeicao neste dia'
        USING ERRCODE = 'RES01';
    END IF;
  END IF;
END; $$;

-- -----------------------------------------------------------------------------
-- 8. Divida por mes: mes corrente ao vivo, meses fechados pelo registo (I1 ponto 1)
-- -----------------------------------------------------------------------------
-- Assinatura mantida (ano, mes, valor, em_atraso) para o JS existente continuar a ler.
CREATE OR REPLACE FUNCTION public.obter_divida_por_mes(p_aluno_id uuid)
RETURNS TABLE(ano integer, mes integer, valor numeric, em_atraso boolean)
LANGUAGE sql STABLE SET search_path = public AS $$
  WITH corrente AS (
    SELECT EXTRACT(YEAR  FROM r.data)::integer AS ano,
           EXTRACT(MONTH FROM r.data)::integer AS mes,
           SUM(r.preco)::numeric               AS valor
    FROM reservas r
    WHERE r.aluno_id = p_aluno_id
      AND r.ativa
      AND date_trunc('month', r.data) >= date_trunc('month', CURRENT_DATE)
    GROUP BY 1, 2
  ),
  passados AS (
    SELECT md.ano, md.mes, md.total AS valor
    FROM meses_em_divida md
    WHERE md.aluno_id = p_aluno_id
      AND make_date(md.ano, md.mes, 1) < date_trunc('month', CURRENT_DATE)::date
      AND NOT EXISTS (
        SELECT 1 FROM meses_liquidados ml
        WHERE ml.aluno_id = md.aluno_id AND ml.ano = md.ano AND ml.mes = md.mes
      )
  )
  SELECT ano, mes, valor, false FROM corrente
  UNION ALL
  SELECT ano, mes, valor, true  FROM passados
  ORDER BY 1 DESC, 2 DESC;
$$;

-- -----------------------------------------------------------------------------
-- 9. Fecho do mes (D6). Agendamento fica para a migracao do pg_cron.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fechar_mes_anterior()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE mes_ref date := date_trunc('month', CURRENT_DATE)::date - INTERVAL '1 month';
BEGIN
  DELETE FROM meses_em_divida
  WHERE ano = EXTRACT(YEAR FROM mes_ref) AND mes = EXTRACT(MONTH FROM mes_ref);

  INSERT INTO meses_em_divida (aluno_id, ano, mes, data, total)
  SELECT r.aluno_id,
         EXTRACT(YEAR  FROM mes_ref)::integer,
         EXTRACT(MONTH FROM mes_ref)::integer,
         mes_ref,
         SUM(r.preco)
  FROM reservas r
  WHERE date_trunc('month', r.data) = date_trunc('month', mes_ref)
    AND r.ativa
  GROUP BY r.aluno_id;
END; $$;

-- -----------------------------------------------------------------------------
-- 10. Liquidacao: so cobra o que esta ativo
-- -----------------------------------------------------------------------------
-- Antes somava tambem as reservas canceladas pelo aluno ('user'), ou seja, cobrava
-- refeicoes que o aluno tinha cancelado.
--
-- ATENCAO AO SECURITY DEFINER. A versao original NAO era SECURITY DEFINER, e era
-- so isso que impedia um aluno de a usar contra outro: sem privilegios especiais,
-- o RLS limitava-o as suas proprias reservas. Passar a DEFINER faz a funcao correr
-- com os privilegios do dono e ignorar o RLS por completo - sem a verificacao
-- abaixo, qualquer utilizador autenticado podia liquidar a divida de qualquer
-- aluno e escrever linhas em meses_liquidados em nome dele.
-- auth.uid() continua a devolver quem chamou, mesmo dentro de SECURITY DEFINER,
-- por isso a verificacao funciona. O Cluster 2 acrescenta a mesma barreira ao
-- nivel do trigger; esta e a que fecha a janela ate la.
CREATE OR REPLACE FUNCTION public.liquidar_mes_divida(p_aluno_id uuid, p_ano integer, p_mes integer)
RETURNS TABLE(success boolean, message text, valor_liquidado numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_valor numeric := 0;
  v_linhas integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode liquidar dividas'
      USING ERRCODE = 'RES04';
  END IF;

  SELECT COALESCE(SUM(preco), 0) INTO v_valor
  FROM reservas
  WHERE aluno_id = p_aluno_id
    AND EXTRACT(YEAR  FROM data) = p_ano
    AND EXTRACT(MONTH FROM data) = p_mes
    AND ativa;

  IF v_valor = 0 THEN
    RETURN QUERY SELECT false, 'Nao ha divida para este mes'::text, 0::numeric;
    RETURN;
  END IF;

  UPDATE reservas
  SET cancelamento_tipo = 'payment'
  WHERE aluno_id = p_aluno_id
    AND EXTRACT(YEAR  FROM data) = p_ano
    AND EXTRACT(MONTH FROM data) = p_mes
    AND ativa;

  GET DIAGNOSTICS v_linhas = ROW_COUNT;

  INSERT INTO meses_liquidados (aluno_id, ano, mes, valor_pago, liquidado_em)
  VALUES (p_aluno_id, p_ano, p_mes, v_valor, now());

  RETURN QUERY SELECT true,
    format('%s reserva(s) liquidada(s) com sucesso', v_linhas)::text,
    v_valor;
END; $$;

-- -----------------------------------------------------------------------------
-- 11. Funcoes substituidas por este modelo (D5)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS gerar_meses_em_divida(integer, integer);
DROP FUNCTION IF EXISTS trigger_gerar_meses_divida();
DROP FUNCTION IF EXISTS liquidar_divida_aluno(uuid, integer, integer);            -- APAGAVA reservas
DROP FUNCTION IF EXISTS liquidar_divida_aluno_emergencia(uuid, integer, integer);

-- -----------------------------------------------------------------------------
-- 12. Relatorios nao usados por nenhum ecra (MANTIDAS, por decisao)
-- -----------------------------------------------------------------------------
-- Nenhuma destas e chamada pela aplicacao: o relatorio mensal do ecra da cantina
-- constroi as suas proprias queries.
--
-- DECIDIDO: ficam na base de dados por agora, comentadas em baixo. ATENCAO: todas
-- leem `cancelada`, que deixa de existir, por isso qualquer chamada futura falha
-- com "column cancelada does not exist". Nao sao chamadas hoje, logo nao partem
-- nada, mas ou sao actualizadas para ler `ativa` ou sao apagadas antes de alguem
-- as voltar a usar. Fica em aberto para o Cluster 7.
--
-- ASSINATURAS CONFERIDAS contra o esquema real (db/tools/schema-original.sql).
-- Reparar em `pode_gerar_relatorio`: os argumentos sao **bigint**, nao integer.
-- Estava escrito (integer, integer), que nao corresponde a nenhuma funcao - o
-- DROP passava sem erro e sem apagar nada, e a funcao ficava viva a ler uma
-- coluna que ja nao existe. E exatamente a armadilha descrita no cabecalho da
-- VERIFICACAO no fim deste ficheiro. Corrigido aqui para quando for descomentado.
--DROP FUNCTION IF EXISTS aluno_tem_divida_mes(uuid, integer, integer);
--DROP FUNCTION IF EXISTS gerar_relatorio_mensal(integer, integer);
--DROP FUNCTION IF EXISTS resumo_mensal(integer, integer);
--DROP FUNCTION IF EXISTS listar_meses_disponiveis();
--DROP FUNCTION IF EXISTS pode_gerar_relatorio(bigint, bigint);
--DROP FUNCTION IF EXISTS verificar_mes_com_dados(bigint, bigint);
--DROP FUNCTION IF EXISTS verificar_mes_com_dados(integer, integer);

-- -----------------------------------------------------------------------------
-- 13. Confirmar que `alunos` nao foi tocada
-- -----------------------------------------------------------------------------
DO $$
DECLARE antes bigint; agora bigint;
BEGIN
  SELECT total INTO antes FROM _guarda_alunos;
  SELECT count(*) INTO agora FROM alunos;
  IF antes <> agora THEN
    RAISE EXCEPTION 'A tabela alunos mudou de % para % linhas. Migracao revertida.', antes, agora;
  END IF;
  RAISE NOTICE 'Alunos intactos: % linhas.', agora;
END $$;

COMMIT;

-- =============================================================================
-- VERIFICACAO (correr depois, ja fora da transacao)
-- =============================================================================
-- SELECT count(*) FROM alunos;                    -- igual ao numero do inicio
-- SELECT column_name, is_generated FROM information_schema.columns
--   WHERE table_name = 'reservas' ORDER BY ordinal_position;
-- As tres restricoes de unicidade. Esperado: menus_data_tipo_key,
-- reservas_aluno_data_tipo_key, meses_em_divida_aluno_ano_mes_key.
-- SELECT conrelid::regclass::text AS tabela, conname FROM pg_constraint
--   WHERE conrelid IN ('reservas'::regclass, 'menus'::regclass,
--                      'meses_em_divida'::regclass)
--     AND contype = 'u' ORDER BY 1, 2;
--
-- Triggers. Esperado: SO dois, ambos em `menus` -
--   trg_criar_reservas_automatica_almoco e trigger_registrar_alteracao_menu.
-- Se `trigger_atualizar_meses_divida` ainda aparecer em `reservas`, o trigger que
-- corrompe meses_em_divida sobreviveu (seccao 1) e cada reserva volta a inflacionar
-- a divida. Nesse caso parar e investigar antes de testar seja o que for.
-- SELECT tgname, tgrelid::regclass::text AS tabela FROM pg_trigger
--   WHERE NOT tgisinternal
--     AND tgrelid IN ('reservas'::regclass, 'menus'::regclass) ORDER BY 1;
--
-- Contagem de funcoes: 33 originais - 5 apagadas + 1 nova (reservar_refeicao) = 29.
-- As 5: atualizar_meses_divida (seccao 1), gerar_meses_em_divida,
-- trigger_gerar_meses_divida, liquidar_divida_aluno, liquidar_divida_aluno_emergencia.
--
-- A MAIS IMPORTANTE. `DROP FUNCTION IF EXISTS` com os tipos de argumentos errados
-- nao da erro nenhum: nao apaga nada e a transacao passa na mesma. Esta lista
-- mostra o que ficou mesmo na base de dados. Confirmar que ja NAO aparecem
-- gerar_meses_em_divida, trigger_gerar_meses_divida, liquidar_divida_aluno e
-- liquidar_divida_aluno_emergencia (seccao 11), e que aparecem reservar_refeicao,
-- obter_divida_por_mes, fechar_mes_anterior e liquidar_mes_divida.
-- SELECT proname, pg_get_function_identity_arguments(oid)
--   FROM pg_proc WHERE pronamespace = 'public'::regnamespace ORDER BY 1;
-- =============================================================================
