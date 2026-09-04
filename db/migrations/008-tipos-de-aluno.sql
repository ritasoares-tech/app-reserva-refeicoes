-- =============================================================================
-- 008 - Dois tipos de aluno: com e sem contrato com a cantina (backlog item 2)
-- =============================================================================
-- DEPENDE DA 001 (coluna gerada ativa, restricao unica das reservas), da 002 e
-- da 003 (reservas_guard). Correr depois da 007 e ANTES da 009.
--
-- O QUE RESOLVE
--   Ate aqui todos os alunos eram do mesmo tipo e o almoco automatico assumia
--   isso em tres sitios. Passam a existir dois tipos: COM contrato - tudo como
--   hoje, almoco reservado automaticamente ao preco do menu; SEM contrato - sem
--   almoco automatico, reserva-o o proprio se quiser, e PAGA MAIS por ele. O
--   pequeno-almoco e o jantar nao mudam para ninguem.
--
-- O QUE NAO MUDA, E TEM DE CONTINUAR A NAO MUDAR
--   1. O reservas.preco e imutavel (reservas_guard, ramo UPDATE, desde a 003).
--      Uma refeicao marcada antes de um aluno mudar de tipo fica com o preco
--      com que foi marcada. Isto NAO se toca aqui.
--   2. saldos_por_aluno (007) e relatorio_mensal somam reservas.preco e nunca
--      recalculam a partir dos menus. Nao mudam.
--
-- Ver docs/superpowers/specs/2026-09-04-contract-types-design.md
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- SECCAO 1 - alunos.tem_contrato
-- -----------------------------------------------------------------------------
-- NOT NULL DEFAULT true, e as duas metades pesam:
--   DEFAULT true  - os 149 alunos que existem e cada linha inserida a mao no
--                   futuro ficam exatamente como hoje. A cantina muda as
--                   excecoes. A direcao segura e a atual.
--   NOT NULL      - os triggers filtram por WHERE tem_contrato. Um NULL nao e
--                   verdadeiro nem falso, por isso um aluno com a coluna a NULL
--                   ficava sem almoco automatico sem erro nenhum. E a mesma
--                   forma do defeito das 1000 linhas: uma resposta errada que
--                   nao avisa.
ALTER TABLE public.alunos ADD COLUMN tem_contrato boolean NOT NULL DEFAULT true;

-- -----------------------------------------------------------------------------
-- SECCAO 2 - configuracao: uma linha, garantida
-- -----------------------------------------------------------------------------
-- O preco do almoco sem contrato vive numa unica definicao, que a cantina muda
-- num ecra, e nao numa segunda coluna em cada menu. Uma coluna por menu
-- duplicava a introducao de dados, obrigava a preencher os menus antigos, e um
-- valor esquecido caia em silencio no preco mais baixo - outra vez a mesma
-- forma de defeito.
--
-- id boolean PRIMARY KEY CHECK (id): o unico valor que passa no CHECK e true, e
-- a chave primaria torna-o unico. Uma segunda linha e impossivel.
--
-- O NOT NULL sem DEFAULT no preco e de proposito: o seed abaixo tem de dizer um
-- numero, em vez de herdar um zero em silencio. O valor 5.00 e um MARCADOR - a
-- cantina define o valor real no ecra antes de isto entrar em producao. Esta na
-- lista de merge do estado-atual.md.
CREATE TABLE public.configuracao (
  id                        boolean PRIMARY KEY DEFAULT true CHECK (id),
  preco_almoco_sem_contrato numeric NOT NULL CHECK (preco_almoco_sem_contrato > 0),
  atualizado_em             timestamptz NOT NULL DEFAULT now(),
  atualizado_por            uuid REFERENCES public.cantina(id)
);

INSERT INTO public.configuracao (id, preco_almoco_sem_contrato) VALUES (true, 5.00);

ALTER TABLE public.configuracao ENABLE ROW LEVEL SECURITY;

-- Um projeto novo do Supabase da tudo ao anon e ao authenticated em cada tabela
-- nova (db-teste-local.md, 2b). Revogar primeiro, conceder depois, sempre.
REVOKE ALL            ON public.configuracao FROM PUBLIC, anon, authenticated;
GRANT  SELECT, UPDATE ON public.configuracao TO authenticated;

-- O aluno le o preco - o ecra do menu mostra-lhe o que vai pagar. So a cantina
-- escreve. Nao ha coluna nenhuma que um aluno devesse poder escrever, por isso
-- aqui a politica chega e nao e preciso passar por uma funcao.
CREATE POLICY "Autenticados veem a configuracao" ON public.configuracao
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "Cantina altera a configuracao" ON public.configuracao
  FOR UPDATE TO authenticated
  USING      (EXISTS (SELECT 1 FROM cantina WHERE cantina.id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM cantina WHERE cantina.id = auth.uid()));

-- Quem escreveu, quando. BEFORE UPDATE para que a linha nao possa mentir sobre
-- isto - a coluna nao e escrivel a partir do cliente com sentido nenhum.
CREATE OR REPLACE FUNCTION public.configuracao_carimbo()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.atualizado_em  := now();
  NEW.atualizado_por := auth.uid();
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_configuracao_carimbo
  BEFORE UPDATE ON public.configuracao
  FOR EACH ROW EXECUTE FUNCTION public.configuracao_carimbo();

-- -----------------------------------------------------------------------------
-- Fechar o buraco da escrita no proprio perfil
-- -----------------------------------------------------------------------------
-- A politica "Aluno atualiza o proprio perfil" e UPDATE ... USING (id =
-- auth.uid()), e o authenticated tinha UPDATE na TABELA inteira. Com o
-- tem_contrato la dentro, qualquer aluno dava a si proprio um contrato - o
-- almoco mais barato E as reservas automaticas. Esta feature abria o buraco,
-- esta feature fecha-o, na mesma migracao.
--
-- Nao chega dar privilegio por coluna a cantina: a cantina e os alunos sao os
-- DOIS o papel authenticated. So o corpo de uma funcao os distingue - e a
-- definir_contrato_aluno da seccao 6.
--
-- ATENCAO A 009. A migracao 009 (codigo de barras) faz este mesmo REVOKE/GRANT
-- pela coluna codigo. A lista (nome, email) e a lista FINAL nas duas: sem
-- tem_contrato, sem codigo. Se a 009 ja correu, isto e inofensivo e repete o
-- estado; se corre depois, repete-o na mesma. Uma lista que esqueca uma coluna
-- parte a edicao do perfil em silencio; uma que inclua uma das duas reabre o
-- buraco em silencio. A verificacao 2 no fim deste ficheiro (e o da 009)
-- confirma a lista final.
REVOKE UPDATE ON public.alunos FROM authenticated;
GRANT  UPDATE (nome, email) ON public.alunos TO authenticated;

COMMIT;

-- =============================================================================
-- SECCAO 3 - O preco, no unico sitio onde ja se decidia
-- =============================================================================
BEGIN;

-- O reservas_guard (003, F6) ja escrevia NEW.preco := menus.preco em TODAS as
-- insercoes, viessem de triggers, de RPCs, da cantina ou de SQL a mao. E o
-- unico sitio onde o preco se decide, por isso e o unico sitio que aprende o
-- que e um contrato. Tudo o que cria reservas herda isto de graca.
--
-- LEVANTA ERRO, NUNCA CAI NO menus.preco. Um fallback numa definicao em falta
-- cobrava o preco com contrato a um aluno que deve mais, em silencio - a forma
-- de defeito que este projeto ja encontrou tres vezes. Falhar alto no INSERT e
-- estritamente melhor do que cobrar a menos numa fatura.
--
-- O ramo UPDATE NAO MUDA. E ele que congela o preco de uma reserva ja feita.
CREATE OR REPLACE FUNCTION public.reservas_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_uid      uuid    := auth.uid();
  v_sistema  boolean := v_uid IS NULL;   -- service_role, triggers, migracoes
  v_staff    boolean := NOT (v_uid IS NULL)
                        AND EXISTS (SELECT 1 FROM cantina WHERE id = v_uid);
  m          record;
  v_contrato boolean;
  v_preco_sc numeric;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- F6: preco, tipo e data vem do menu. Nunca do cliente, para ninguem.
    SELECT preco, tipo, data INTO m FROM menus WHERE id = NEW.menu_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Menu inexistente' USING ERRCODE = 'RES03';
    END IF;
    NEW.tipo := m.tipo;
    NEW.data := m.data;

    -- 008: o almoco de um aluno sem contrato tem o preco da configuracao.
    IF m.tipo = 'almoco' THEN
      SELECT a.tem_contrato INTO v_contrato FROM alunos a WHERE a.id = NEW.aluno_id;
      IF NOT FOUND THEN
        -- Inalcancavel enquanto aluno_id tiver FK para alunos. Rede, nao caso.
        RAISE EXCEPTION 'Aluno inexistente' USING ERRCODE = 'RES08';
      END IF;
    END IF;

    IF m.tipo = 'almoco' AND NOT v_contrato THEN
      SELECT c.preco_almoco_sem_contrato INTO v_preco_sc FROM configuracao c;
      IF v_preco_sc IS NULL THEN
        RAISE EXCEPTION 'Preco do almoco sem contrato nao configurado'
          USING ERRCODE = 'RES09';
      END IF;
      NEW.preco := v_preco_sc;
    ELSE
      NEW.preco := m.preco;
    END IF;

    IF NOT v_sistema AND NOT v_staff THEN
      IF NEW.aluno_id <> v_uid THEN
        RAISE EXCEPTION 'So podes reservar para ti' USING ERRCODE = 'RES05';
      END IF;
      IF now() >= public.prazo_limite(NEW.tipo, NEW.data) THEN
        RAISE EXCEPTION 'Prazo ultrapassado para esta refeicao'
          USING ERRCODE = 'RES06';
      END IF;
    END IF;

  ELSE  -- UPDATE
    -- Imutaveis depois de criada, para toda a gente. Uma reserva nao muda de
    -- dono, de menu, de dia, de tipo nem de preco: se for preciso outra coisa,
    -- cancela-se esta e cria-se outra.
    NEW.aluno_id   := OLD.aluno_id;
    NEW.menu_id    := OLD.menu_id;
    NEW.data       := OLD.data;
    NEW.tipo       := OLD.tipo;
    NEW.preco      := OLD.preco;
    NEW.criado_em  := OLD.criado_em;
    NEW.automatico := OLD.automatico;

    IF NOT v_sistema AND NOT v_staff THEN
      IF NEW.cancelamento_tipo IS DISTINCT FROM OLD.cancelamento_tipo THEN
        IF NEW.cancelamento_tipo = 'payment' THEN
          RAISE EXCEPTION 'So a cantina pode liquidar reservas'
            USING ERRCODE = 'RES07';
        END IF;
        IF now() >= public.prazo_limite(OLD.tipo, OLD.data) THEN
          RAISE EXCEPTION 'Prazo ultrapassado para esta refeicao'
            USING ERRCODE = 'RES06';
        END IF;
      END IF;

      -- A dieta segue o prazo do almoco, como no Cluster 3 (F2).
      IF NEW.is_dieta IS DISTINCT FROM OLD.is_dieta
         AND now() >= public.prazo_limite(OLD.tipo, OLD.data) THEN
        RAISE EXCEPTION 'Prazo ultrapassado para alterar a dieta'
          USING ERRCODE = 'RES06';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END; $function$;

COMMIT;

-- =============================================================================
-- SECCAO 4 - O almoco automatico so para quem tem contrato
-- =============================================================================
BEGIN;

-- Quando nasce um menu de almoco: so os alunos com contrato.
CREATE OR REPLACE FUNCTION public.criar_reservas_automaticas_almoco()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  IF NEW.tipo = 'almoco' THEN
    INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta)
    SELECT a.id, NEW.id, NEW.tipo, NEW.data, NEW.preco, true, false
    FROM alunos a
    WHERE a.tem_contrato
    ON CONFLICT (aluno_id, data, tipo) DO NOTHING;
  END IF;
  RETURN NEW;
END; $function$;

-- Quando nasce um aluno (002): so se tiver contrato. A regra do "hoje antes das
-- 9h" e o fuso de Lisboa ficam exatamente como a 002 os escreveu.
CREATE OR REPLACE FUNCTION public.criar_reservas_almoco_novo_aluno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_local timestamp := now() AT TIME ZONE 'Europe/Lisbon';
  v_hoje  date      := v_local::date;
  v_hora  time      := v_local::time;
BEGIN
  IF NOT NEW.tem_contrato THEN
    RETURN NEW;
  END IF;

  INSERT INTO reservas (aluno_id, menu_id, tipo, data, preco, automatico, is_dieta)
  SELECT NEW.id, m.id, m.tipo, m.data, m.preco, true, false
  FROM menus m
  WHERE m.tipo = 'almoco'
    AND (
          m.data > v_hoje                                  -- almocos futuros
       OR (m.data = v_hoje AND v_hora < TIME '09:00')       -- hoje, so antes das 9h
        )
  ON CONFLICT (aluno_id, data, tipo) DO NOTHING;

  RETURN NEW;
END; $$;

COMMIT;

-- =============================================================================
-- SECCAO 5 - 'contrato', um cancelamento que nao e do aluno
-- =============================================================================
BEGIN;

-- Cancelar os almocos automaticos futuros de quem perde o contrato precisa de
-- um valor proprio. Reutilizar 'user' dizia que o aluno cancelou, o que e falso
-- e lhe mostrava um cancelamento que nao fez. A coluna gerada ativa e
-- (cancelamento_tipo IS NULL OR = 'reactivated'), por isso 'contrato' conta
-- como inativa sem lhe tocar.
ALTER TABLE public.reservas DROP CONSTRAINT reservas_cancelamento_tipo_chk;
ALTER TABLE public.reservas ADD  CONSTRAINT reservas_cancelamento_tipo_chk
  CHECK (cancelamento_tipo IS NULL
         OR cancelamento_tipo = ANY (ARRAY['user'::text, 'payment'::text,
                                           'reactivated'::text, 'contrato'::text]));

-- O reservar_refeicao so reativava linhas em 'user'. Sem isto, um aluno que
-- perdeu o contrato era recebido com RES01 "ja tens uma reserva" ao tentar
-- marcar o almoco que agora tem de marcar sozinho - um bloqueio, nao uma
-- feature. So muda o WHERE do ON CONFLICT; o resto e o da 001.
CREATE OR REPLACE FUNCTION public.reservar_refeicao(p_menu_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
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
    WHERE reservas.cancelamento_tipo IN ('user', 'contrato');

  -- FOUND fica falso quando houve conflito e o WHERE acima nao deixou reativar,
  -- ou seja: existe uma linha e nao esta em 'user' nem em 'contrato'. Descobrir
  -- em que estado esta para dizer ao aluno o que se passa.
  IF NOT FOUND THEN
    SELECT r.cancelamento_tipo INTO v_estado
    FROM reservas r
    WHERE r.aluno_id = auth.uid() AND r.data = m.data AND r.tipo = m.tipo;

    IF v_estado = 'payment' THEN
      RAISE EXCEPTION 'Esta refeicao ja foi liquidada e nao pode ser reservada de novo'
        USING ERRCODE = 'RES02';
    ELSE
      RAISE EXCEPTION 'Ja tens uma reserva para esta refeicao neste dia'
        USING ERRCODE = 'RES01';
    END IF;
  END IF;
END; $function$;

COMMIT;

-- =============================================================================
-- SECCAO 6 - definir_contrato_aluno
-- =============================================================================
BEGIN;

-- A cantina muda o tipo de um aluno por aqui, e so por aqui: a coluna nao e
-- escrivel por PostgREST por ninguem (seccao 2). SECURITY DEFINER com a
-- verificacao de staff, como a liquidar_mes_divida e a saldos_por_aluno.
--
-- true -> false: cancela (nao apaga, nao reprecifica) os almocos AUTOMATICOS,
-- ATIVOS e FUTUROS do aluno. Deixados como estavam, cobravam-lhe ate uma
-- semana de almocos ao preco de um contrato que ja nao tem - e como os menus
-- se publicam uma semana antes, essa semana e o caso normal e nao a excecao.
--
-- Estritamente futuros: data > hoje em Lisboa. O almoco de HOJE nunca e
-- cancelado, mesmo antes das 9h. A regra das 9h da 002 e sobre um aluno que
-- ainda nao teve oportunidade de comer; isto e sobre uma mudanca de contrato
-- que nao deve perturbar uma refeicao que esta a ser servida. Os passados nao
-- se tocam pela mesma razao, mais a regra 6.
--
-- false -> true: nao cria nada retroativamente. O proximo menu publicado
-- apanha o aluno pelo trigger. Foi a opcao mais estreita das duas oferecidas.
--
-- Devolve quantos almocos cancelou, para o ecra o dizer antes e depois.
CREATE OR REPLACE FUNCTION public.definir_contrato_aluno(p_aluno_id uuid, p_tem_contrato boolean)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_hoje       date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_cancelados integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina c WHERE c.id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode alterar o contrato de um aluno';
  END IF;

  UPDATE alunos a SET tem_contrato = p_tem_contrato WHERE a.id = p_aluno_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aluno inexistente' USING ERRCODE = 'RES08';
  END IF;

  IF NOT p_tem_contrato THEN
    UPDATE reservas r
    SET cancelamento_tipo = 'contrato'
    WHERE r.aluno_id   = p_aluno_id
      AND r.tipo       = 'almoco'
      AND r.automatico
      AND r.ativa
      AND r.data       > v_hoje;
    GET DIAGNOSTICS v_cancelados = ROW_COUNT;
  END IF;

  RETURN v_cancelados;
END; $fn$;

REVOKE EXECUTE ON FUNCTION public.definir_contrato_aluno(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.definir_contrato_aluno(uuid, boolean) TO authenticated;

-- Para o ecra dizer "vai cancelar N almocos" ANTES de confirmar. So conta.
CREATE OR REPLACE FUNCTION public.contar_almocos_automaticos_futuros(p_aluno_id uuid)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $fn$
  SELECT count(*)::int FROM reservas r
  WHERE r.aluno_id = p_aluno_id AND r.tipo = 'almoco' AND r.automatico AND r.ativa
    AND r.data > (now() AT TIME ZONE 'Europe/Lisbon')::date
    AND EXISTS (SELECT 1 FROM cantina c WHERE c.id = auth.uid());
$fn$;

REVOKE EXECUTE ON FUNCTION public.contar_almocos_automaticos_futuros(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.contar_almocos_automaticos_futuros(uuid) TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO
-- =============================================================================
-- 1) Todos os alunos existentes com contrato, e a configuracao com uma linha:
--
--   SELECT count(*) FILTER (WHERE tem_contrato) AS com, count(*) AS total FROM alunos;
--   SELECT * FROM configuracao;
--   Esperado: com = total; uma linha, preco > 0.
--
-- 2) A LISTA FINAL DE COLUNAS ESCREVIVEIS EM alunos (partilhada com a 009):
--
--   SELECT column_name FROM information_schema.column_privileges
--   WHERE table_name = 'alunos' AND grantee = 'authenticated'
--     AND privilege_type = 'UPDATE' ORDER BY 1;
--   Esperado: exatamente email e nome. Nem tem_contrato, nem codigo.
--
-- 3) As funcoes novas sao SECURITY DEFINER e o anon nao lhes chega:
--
--   SELECT proname, prosecdef, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('definir_contrato_aluno', 'contar_almocos_automaticos_futuros');
--   Esperado: prosecdef = t, sem `anon=` e sem `=X/postgres`.
--
-- 4) O preco continua imutavel (correr numa transacao e fazer ROLLBACK):
--
--   BEGIN; UPDATE reservas SET preco = 99.99 WHERE id = (SELECT id FROM reservas LIMIT 1);
--   SELECT preco FROM reservas WHERE id = (SELECT id FROM reservas LIMIT 1); ROLLBACK;
--   Esperado: o preco original, nao 99.99.
--
-- 5) A conta dos saldos nao mudou para ninguem com contrato: correr como a
--    cantina, antes e depois de aplicar isto, e comparar:
--
--   SELECT count(*), sum(total) FROM saldos_por_aluno();
--   Esperado: identico. Esta migracao nao muda nenhum valor ja cobrado.
-- =============================================================================
