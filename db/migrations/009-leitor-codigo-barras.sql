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

-- Ninguem da aplicacao chama isto: so o trigger abaixo e esta migracao. O
-- EXECUTE por omissao ia para o PUBLIC, e e a licao da 004, 005 e 006.
REVOKE EXECUTE ON FUNCTION public.gerar_codigo_aluno() FROM PUBLIC, anon, authenticated;

-- Preencher os que ja existem. A funcao e volatil, por isso corre uma vez por
-- linha, que e o que se quer.
UPDATE public.alunos SET codigo = public.gerar_codigo_aluno() WHERE codigo IS NULL;

ALTER TABLE public.alunos ALTER COLUMN codigo SET NOT NULL;
ALTER TABLE public.alunos ADD CONSTRAINT alunos_codigo_key UNIQUE (codigo);
-- O trigger so cobre o INSERT. Um UPDATE a mao no SQL Editor com um codigo mal
-- formado passava sem isto, e a verificacao no fim so o DETETA; isto IMPEDE.
ALTER TABLE public.alunos ADD CONSTRAINT alunos_codigo_formato_chk CHECK (codigo ~ '^[0-9]{6}$');

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

-- =============================================================================
-- SECCAO 3 - O registo das leituras
-- =============================================================================
BEGIN;

-- aluno_id ADMITE NULO DE PROPOSITO. Uma leitura de um codigo que nao e de
-- ninguem - um cartao da biblioteca, um codigo de supermercado, um digito mal
-- lido - tem de deixar rasto na mesma, com os digitos que foram lidos. Por em
-- NOT NULL era garantir que o unico caso que mais interessa investigar e o
-- unico caso que nao deixa registo nenhum.
--
-- codigo_lido fica guardado mesmo quando se sabe quem e o aluno: se um dia um
-- codigo for regerado, o registo continua a mostrar o que foi lido naquele dia.
--
-- APPEND-ONLY POR CONSTRUCAO, NAO POR CONVENCAO. As escritas so acontecem
-- dentro da registar_leitura, que e SECURITY DEFINER. O authenticated leva
-- SELECT e mais nada - nao ha UPDATE nem DELETE para conceder, por isso nao ha
-- caminho nenhum para reescrever o registo. Nao e uma regra a pedir que
-- ninguem o faca.
--
-- ON DELETE SET NULL nas duas chaves estrangeiras: o registo sobreviver ao
-- aluno e a reserva e precisamente o objetivo de um registo.
CREATE TABLE public.leituras (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aluno_id    uuid REFERENCES public.alunos(id)   ON DELETE SET NULL,
  codigo_lido text NOT NULL,
  tipo        text NOT NULL CHECK (tipo IN ('pequeno_almoco', 'almoco', 'jantar')),
  data        date NOT NULL,
  resultado   text NOT NULL CHECK (resultado IN
                ('servido', 'sem_reserva', 'cancelada', 'repetido', 'codigo_desconhecido')),
  reserva_id  uuid REFERENCES public.reservas(id) ON DELETE SET NULL,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  criado_por  uuid REFERENCES public.cantina(id)
);

CREATE INDEX leituras_data_tipo_idx  ON public.leituras (data, tipo);
CREATE INDEX leituras_aluno_data_idx ON public.leituras (aluno_id, data);

ALTER TABLE public.leituras ENABLE ROW LEVEL SECURITY;

REVOKE ALL    ON public.leituras FROM PUBLIC, anon, authenticated;
GRANT  SELECT ON public.leituras TO authenticated;

CREATE POLICY "Cantina ve as leituras" ON public.leituras
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM cantina WHERE cantina.id = auth.uid()));

COMMIT;

-- =============================================================================
-- SECCAO 4 - Registar uma leitura
-- =============================================================================
BEGIN;

-- Devolve o NOME do aluno de proposito, e o ecra mostra-o em grande: quem esta
-- ao balcao tem de poder confrontar o nome com a cara que tem a frente. Um
-- leitor que so diz "OK" autentica um telemovel, nao autentica um aluno.
--
-- Devolve tambem o is_dieta, para servir o prato certo. A dieta ja vive na
-- reserva do almoco e ja e por ela que a cozinha se divide no ecra das
-- Reservas do Dia.
--
-- "Hoje" e sempre (now() AT TIME ZONE 'Europe/Lisbon')::date, pela mesma razao
-- que a 002 documenta ao pormenor: o servidor corre em UTC e a escola nao, por
-- isso logo a seguir a meia-noite em Lisboa o CURRENT_DATE ainda e ontem.
--
-- O 'repetido' e GRAVADO, nao e suprimido. Um leitor que dispara duas vezes
-- tem de ser visivel nos dados em vez de ser absorvido em silencio.
CREATE OR REPLACE FUNCTION public.registar_leitura(p_codigo text, p_tipo text)
RETURNS TABLE(resultado text, nome text, is_dieta boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid       uuid := auth.uid();
  v_hoje      date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_aluno     record;
  v_res       record;
  v_resultado text;
  v_reserva   uuid;
  v_dieta     boolean := false;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina c WHERE c.id = v_uid) THEN
    RAISE EXCEPTION 'Apenas a cantina pode registar leituras';
  END IF;

  IF p_tipo NOT IN ('pequeno_almoco', 'almoco', 'jantar') THEN
    RAISE EXCEPTION 'Tipo de refeicao invalido: %', p_tipo USING ERRCODE = 'LEI01';
  END IF;

  SELECT a.id, a.nome INTO v_aluno FROM alunos a WHERE a.codigo = p_codigo;

  IF NOT FOUND THEN
    INSERT INTO leituras (aluno_id, codigo_lido, tipo, data, resultado, criado_por)
    VALUES (NULL, p_codigo, p_tipo, v_hoje, 'codigo_desconhecido', v_uid);

    RETURN QUERY SELECT 'codigo_desconhecido'::text, NULL::text, false;
    RETURN;
  END IF;

  -- No maximo uma linha: reservas tem UNIQUE (aluno_id, data, tipo) desde a 001.
  SELECT r.id, r.ativa, r.is_dieta INTO v_res
  FROM reservas r
  WHERE r.aluno_id = v_aluno.id AND r.data = v_hoje AND r.tipo = p_tipo;

  IF NOT FOUND THEN
    v_resultado := 'sem_reserva';
  ELSIF NOT v_res.ativa THEN
    -- Separavel do sem_reserva unicamente porque a linha cancelada sobrevive.
    v_resultado := 'cancelada';
    v_reserva   := v_res.id;
  ELSIF EXISTS (
      SELECT 1 FROM leituras l
      WHERE l.aluno_id  = v_aluno.id
        AND l.data      = v_hoje
        AND l.tipo      = p_tipo
        AND l.resultado = 'servido'
  ) THEN
    v_resultado := 'repetido';
    v_reserva   := v_res.id;
    v_dieta     := coalesce(v_res.is_dieta, false);
  ELSE
    v_resultado := 'servido';
    v_reserva   := v_res.id;
    v_dieta     := coalesce(v_res.is_dieta, false);
  END IF;

  INSERT INTO leituras (aluno_id, codigo_lido, tipo, data, resultado, reserva_id, criado_por)
  VALUES (v_aluno.id, p_codigo, p_tipo, v_hoje, v_resultado, v_reserva, v_uid);

  RETURN QUERY SELECT v_resultado, v_aluno.nome, v_dieta;
END; $fn$;

-- A licao da 004, 005 e 006: o EXECUTE por omissao vai para o PUBLIC.
REVOKE EXECUTE ON FUNCTION public.registar_leitura(text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.registar_leitura(text, text) TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO
-- =============================================================================
-- 1) Todos os alunos com codigo unico de seis digitos:
--
--   SELECT count(*) AS total, count(codigo) AS com_codigo,
--          count(DISTINCT codigo) AS distintos,
--          count(*) FILTER (WHERE codigo !~ '^[0-9]{6}$') AS mal_formados
--   FROM alunos;
--   Esperado: total = com_codigo = distintos, mal_formados = 0.
--
-- 2) A LISTA FINAL DE COLUNAS ESCREVIVEIS. Esta e a verificacao que apanha o
--    conflito com a 008 descrito na seccao 2. Correr SEMPRE, e sobretudo depois
--    de aplicar a outra das duas migracoes:
--
--   SELECT column_name FROM information_schema.column_privileges
--   WHERE table_name = 'alunos' AND grantee = 'authenticated'
--     AND privilege_type = 'UPDATE' ORDER BY 1;
--   Esperado: exatamente nome e email. Nem codigo, nem tem_contrato.
--
-- 3) A funcao corre com os direitos de quem a criou e o anon nao lhe chega:
--
--   SELECT proname, prosecdef, proacl FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace AND proname = 'registar_leitura';
--   Esperado: prosecdef = t, sem `anon=` e sem a entrada vazia `=X/postgres`.
--
-- 4) O registo nao tem como ser reescrito:
--
--   SELECT grantee, privilege_type FROM information_schema.role_table_grants
--   WHERE table_name = 'leituras' ORDER BY 1, 2;
--   Esperado: nenhum UPDATE nem DELETE para anon ou authenticated.
-- =============================================================================
