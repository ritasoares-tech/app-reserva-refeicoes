-- =============================================================================
-- 009 - Codigo de barras do aluno e leitor na cantina (backlog item 1)
-- =============================================================================
-- DEPENDE DA 001 e da 002. Correr depois da 007 e da 008.
--
-- O QUE RESOLVE
--   A cantina nao sabe quem comeu, so sabe quem reservou, e nao tem forma de
--   recusar um aluno que cancelou ou que nunca reservou. Isto da-lhe as duas
--   coisas: um codigo por aluno, um ecra de leitura ao balcao, e um registo
--   append-only que se exporta para Excel.
--
-- O QUE ISTO NAO FAZ
--   Nao toca na tabela reservas. Nao inventa um estado novo de reserva, nao
--   mexe em precos, prazos nem agregacoes. A decisao de servir ou recusar e
--   uma LEITURA de uma reserva que ja existe. E por isso que isto e barato.
--
-- Ver docs/superpowers/specs/2026-09-04-barcode-scanner-design.md
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- SECCAO 1 - O codigo do aluno
-- -----------------------------------------------------------------------------
-- CODIGOS ALEATORIOS, NAO SEQUENCIAIS, DE PROPOSITO. Com codigos sequenciais os
-- alunos vizinhos ficam em numeros vizinhos, por isso um digito mal lido cai em
-- cima de um aluno REAL e serve a pessoa errada por baixo de um cartao verde.
-- Com 6 digitos aleatorios (1.000.000 de hipoteses) e ~149 em uso, uma leitura
-- corrompida quase de certeza nao acerta em ninguem e sai como
-- 'codigo_desconhecido', que e exatamente o que se quer ver.
--
-- Seis digitos e um limite deliberado: imprime-se num cartao, diz-se em voz alta
-- ao balcao, e escreve-se a mao em dois segundos. Essas tres propriedades SAO o
-- plano B se o leitor for laser e nao ler ecras. Um UUID nao tem nenhuma delas.

ALTER TABLE public.alunos ADD COLUMN codigo text;

CREATE OR REPLACE FUNCTION public.gerar_codigo_aluno()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_codigo     text;
  v_tentativas int := 0;
BEGIN
  LOOP
    v_codigo := lpad((floor(random() * 1000000))::int::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM alunos a WHERE a.codigo = v_codigo);

    v_tentativas := v_tentativas + 1;
    -- A colisao e rara nesta densidade, mas "rara" nao e "nunca", e um erro de
    -- chave unica em bruto a chegar a cantina nao serve a ninguem.
    IF v_tentativas > 100 THEN
      RAISE EXCEPTION 'Nao foi possivel gerar um codigo unico ao fim de 100 tentativas';
    END IF;
  END LOOP;

  RETURN v_codigo;
END; $$;

-- Preencher os que ja existem. A funcao e volatil, por isso corre uma vez por
-- linha, que e o que se quer.
UPDATE public.alunos SET codigo = public.gerar_codigo_aluno() WHERE codigo IS NULL;

ALTER TABLE public.alunos ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE public.alunos ADD CONSTRAINT alunos_codigo_key UNIQUE (codigo);

-- Os alunos entram a mao pelo SQL Editor, sem interface nenhuma. Um trigger
-- apanha todos os caminhos - e a mesma razao pela qual a 002 e um trigger.
CREATE OR REPLACE FUNCTION public.alunos_codigo_default()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.codigo IS NULL THEN
    NEW.codigo := public.gerar_codigo_aluno();
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_alunos_codigo
  BEFORE INSERT ON public.alunos
  FOR EACH ROW EXECUTE FUNCTION public.alunos_codigo_default();

-- -----------------------------------------------------------------------------
-- SECCAO 2 - Fechar o buraco da escrita no proprio perfil
-- -----------------------------------------------------------------------------
-- A politica "Aluno atualiza o proprio perfil" e UPDATE ... USING (id =
-- auth.uid()), e o authenticated tinha UPDATE na TABELA inteira. Enquanto as
-- colunas eram so nome e email isso era inofensivo. Com o codigo la dentro
-- passa a ser: um aluno reescreve o proprio codigo e come como outro - e o
-- registo fica com o nome do outro.
--
-- Nao chega dar privilegio por coluna a cantina: a cantina e os alunos sao os
-- DOIS o papel `authenticated`. O papel nao os distingue; so o corpo de uma
-- funcao os distingue. Por isso ninguem escreve o codigo por PostgREST, e a
-- cantina nem precisa de escrever esta coluna.
--
-- ATENCAO A 008. A migracao 008 (tipos de aluno) faz este mesmo REVOKE/GRANT
-- para a coluna tem_contrato. Se a 008 ja correu, a lista de colunas aqui tem
-- de continuar a ser (nome, email) - ou seja, sem tem_contrato e sem codigo. Se
-- a 008 correr depois desta, tem de repetir exatamente esta lista. Uma lista que
-- esqueca uma coluna parte a edicao do perfil em silencio; uma lista que inclua
-- codigo ou tem_contrato reabre o buraco em silencio. Nenhum dos dois levanta
-- erro nenhum. A VERIFICACAO no fim deste ficheiro confirma a lista final.

REVOKE UPDATE ON public.alunos FROM authenticated;
GRANT  UPDATE (nome, email) ON public.alunos TO authenticated;

COMMIT;
