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
