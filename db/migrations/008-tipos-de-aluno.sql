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
