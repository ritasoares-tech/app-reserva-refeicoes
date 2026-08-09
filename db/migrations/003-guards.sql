-- =============================================================================
-- 003 - Guardas de seguranca (Cluster 2)
-- =============================================================================
-- DEPENDE DA 001. Correr depois da 001 e da 002.
--
-- Esta migracao e construida por passos e revista passo a passo. Esta COMPLETA:
-- contem os PASSOS 1, 2, 3, 4, 4b e 5, ou seja, o Cluster 2 inteiro.
--
-- Os PASSOS 1 a 4b ja foram aplicados a base de testes e verificados (5 politicas
-- sem INSERT aberto; trigger, funcoes e fuso horario conferidos; as duas
-- restricoes CHECK a recusar valores invalidos; RLS em todas as nove tabelas e o
-- anon sem acesso). Correr a 003 inteira
-- outra vez e seguro e e a forma recomendada de aplicar um passo novo: os DROP
-- de politicas e de restricoes sao IF EXISTS, as funcoes sao CREATE OR REPLACE,
-- o trigger e DROP IF EXISTS + CREATE, e ENABLE ROW LEVEL SECURITY e REVOKE nao
-- se queixam de ja estarem feitos.
--
-- ATENCAO, PARA QUEM CHEGAR AQUI PELO CLUSTER 6: a RLS de
-- cancelamentos_especiais foi LIGADA NO PASSO 4, aqui no Cluster 2, e nao no
-- Cluster 6 como o plano dizia. Ver o bloco "DESVIO AO PLANO" mais abaixo.
--
-- -----------------------------------------------------------------------------
-- PASSO 1 - Remover as politicas abertas de INSERT em reservas
-- -----------------------------------------------------------------------------
-- Hoje ha duas politicas de INSERT em reservas com with_check = true, ou seja,
-- QUALQUER utilizador autenticado pode inserir QUALQUER linha - com o aluno_id,
-- preco, data e tipo que quiser. A chave anon e publica (esta no supabase.js),
-- por isso isto e uma porta aberta, nao teoria.
--
--   "permitir inserir reservas"  INSERT  with_check (true)
--   "meses_em_divida"            INSERT  with_check (true)   <- nome errado, e de
--                                                               reservas, nao de
--                                                               meses_em_divida
--
-- Ao cair estas duas, ficam as politicas com ambito, que ja cobrem tudo o que e
-- legitimo:
--   "Aluno pode criar reservas"          INSERT  with_check (aluno_id = auth.uid())
--   "Aluno vê apenas as suas reservas"   SELECT  (aluno_id = auth.uid())
--   "Aluno pode atualizar as suas reservas" UPDATE (aluno_id = auth.uid())
--   "Cantina pode ver todas as reservas" SELECT  (é cantina)
--   "Cantina pode modificar reservas"    UPDATE  (é cantina)
--
-- Nota: nao ha politica de INSERT para a cantina, e de proposito - a cantina nao
-- insere reservas a mao; sao criadas pelos triggers automaticos (SECURITY
-- DEFINER, passam ao lado da RLS). Se algum dia a cantina precisar de inserir uma
-- reserva pela interface, e ai que se acrescenta uma politica com ambito, nunca
-- se volta a por with_check (true).
-- =============================================================================

BEGIN;

-- Verificar que a 001 ja correu (ativa e o sinal mais barato de que o modelo novo
-- esta aplicado). Sem isto, correr a 003 numa base antiga passaria despercebido.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reservas' AND column_name = 'ativa'
  ) THEN
    RAISE EXCEPTION
      'Falta a coluna reservas.ativa. Correr as migracoes 001 e 002 primeiro.';
  END IF;
END $$;

DROP POLICY IF EXISTS "permitir inserir reservas" ON reservas;
DROP POLICY IF EXISTS "meses_em_divida"           ON reservas;

COMMIT;

-- =============================================================================
-- VERIFICACAO (correr a seguir, fora da transacao)
-- =============================================================================
-- Devem sobrar exatamente 5 politicas em reservas, e NENHUMA de INSERT com
-- with_check = 'true'. Se aparecer alguma linha com cmd = INSERT e with_check
-- 'true', um DROP nao apanhou o nome certo - conferir o nome exato acima.
--
--   SELECT policyname, cmd, with_check
--   FROM   pg_policies
--   WHERE  schemaname = 'public' AND tablename = 'reservas'
--   ORDER  BY cmd, policyname;
--
-- Esperado (5 linhas):
--   Aluno pode atualizar as suas reservas    UPDATE  (aluno_id = auth.uid())
--   Aluno pode criar reservas                INSERT  (aluno_id = auth.uid())
--   Aluno vê apenas as suas reservas         SELECT  -
--   Cantina pode modificar reservas          UPDATE  -
--   Cantina pode ver todas as reservas       SELECT  -
-- =============================================================================


-- =============================================================================
-- PASSO 2 - Trigger-guarda em reservas, com o prazo do lado do servidor
-- =============================================================================
-- A RLS diz QUEM toca em QUE LINHAS. Nao diz que VALORES pode la por. Com as
-- politicas do PASSO 1, um aluno continua a poder alterar as suas proprias
-- reservas para o que lhe apetecer: preco 0.01, cancelamento_tipo 'payment'
-- (divida liquidada sem pagar), ou reservar uma refeicao cujo prazo ja passou.
-- E a RLS nao tem como travar nada disto - a linha e mesmo dele.
--
-- O trigger e a camada que falta: corre BEFORE INSERT OR UPDATE, reescreve o que
-- o cliente nao tem o direito de decidir, e recusa o resto.
--
-- TRES DECISOES QUE NAO ESTAVAM NO PLANO ORIGINAL (internal-solutions.md
-- Cluster 2 Passo 2), todas deliberadas:
--
-- 1. ISENCAO DE SISTEMA (auth.uid() IS NULL). O plano so distinguia cantina de
--    aluno. Mas auth.uid() e NULL no service_role, nas migracoes e em tudo o que
--    corre fora de uma sessao de utilizador - incluindo o trigger da 002, que
--    dispara quando um aluno novo e inserido por um administrador e nao por
--    alguem com sessao iniciada. Sem esta isencao, acrescentar um aluno depois
--    das 9h passaria a rebentar. A RLS continua a tapar o caminho do anon: a
--    politica de INSERT exige aluno_id = auth.uid(), que com uid nulo nunca da.
--
-- 2. PRAZO NO SERVIDOR. Decisao 4 do estado-atual.md, encontrada no Cluster 3
--    (cluster3-js.md D3.1): todos os prazos eram calculados no cliente, por isso
--    o relogio do dispositivo derrubava-os a todos. Confirmado em app. A
--    verificacao no frontend FICA como esta - e a camada de UX, e responde sem
--    ida ao servidor. Esta e a defesa a serio, por baixo. Duas camadas.
--
-- 3. FUSO HORARIO EXPLICITO. A base de dados corre em UTC; as regras da cantina
--    sao horas de relogio de parede portuguesas. Sem 'Europe/Lisbon', no verao
--    (UTC+1) as 09:00 do servidor seriam 10:00 ca, e o aluno ganhava uma hora
--    extra de borla todos os dias. A verificacao la em baixo compara uma data de
--    verao com uma de inverno exatamente para provar que o fuso esta a ser
--    aplicado, e nao apenas escrito.
-- =============================================================================

BEGIN;

-- O mesmo prazo que o _prazoLimite() do aluno.js, calculado no servidor.
-- STABLE e nao IMMUTABLE de proposito: as regras de fuso horario mudam, por isso
-- o resultado nao e imutavel ao longo do tempo, so dentro da mesma transacao.
CREATE OR REPLACE FUNCTION public.prazo_limite(p_tipo text, p_data date)
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE p_tipo
    WHEN 'pequeno_almoco' THEN ((p_data - 1) + time '23:00') AT TIME ZONE 'Europe/Lisbon'
    ELSE                       ( p_data      + time '09:00') AT TIME ZONE 'Europe/Lisbon'
  END;
$$;

COMMENT ON FUNCTION public.prazo_limite(text, date) IS
  'Prazo de reserva/cancelamento. Espelha _prazoLimite() do aluno.js. '
  'Pequeno almoco: 23:00 da vespera. Almoco e jantar: 09:00 do proprio dia.';

CREATE OR REPLACE FUNCTION public.reservas_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid    := auth.uid();
  v_sistema boolean := v_uid IS NULL;   -- service_role, triggers, migracoes
  v_staff   boolean := NOT (v_uid IS NULL)
                       AND EXISTS (SELECT 1 FROM cantina WHERE id = v_uid);
  m         record;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- F6: preco, tipo e data vêm do menu. Nunca do cliente, para ninguem.
    SELECT preco, tipo, data INTO m FROM menus WHERE id = NEW.menu_id;
    IF NOT FOUND THEN
      -- Inalcancavel enquanto menu_id for NOT NULL com FK para menus. Fica como
      -- rede: se a FK cair um dia, isto rebenta em vez de gravar uma reserva
      -- com preco nulo.
      RAISE EXCEPTION 'Menu inexistente' USING ERRCODE = 'RES03';
    END IF;
    NEW.preco := m.preco;
    NEW.tipo  := m.tipo;
    NEW.data  := m.data;

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
END; $$;

COMMENT ON FUNCTION public.reservas_guard() IS
  'Guarda de escrita em reservas: deriva preco/tipo/data do menu, congela os '
  'campos imutaveis, e aplica o prazo do servidor a sessoes de aluno. '
  'Cantina e contextos de sistema (auth.uid() IS NULL) passam ao lado.';

DROP TRIGGER IF EXISTS trg_reservas_guard ON reservas;
CREATE TRIGGER trg_reservas_guard
  BEFORE INSERT OR UPDATE ON reservas
  FOR EACH ROW EXECUTE FUNCTION public.reservas_guard();

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 2 (correr a seguir, fora da transacao)
-- =============================================================================
-- Sao 3 consultas. As duas primeiras confirmam que existe; a terceira e a que
-- interessa, porque prova que o fuso esta mesmo a ser aplicado.
--
-- 1) O trigger existe e esta ativo. Esperado: 1 linha, trg_reservas_guard | O
--
--   SELECT tgname, tgenabled
--   FROM   pg_trigger
--   WHERE  tgrelid = 'public.reservas'::regclass AND NOT tgisinternal;
--
-- 2) As duas funcoes existem e a guarda e SECURITY DEFINER.
--    Esperado (2 linhas):  prazo_limite | f      (nao precisa de definer)
--                          reservas_guard | t
--
--   SELECT proname, prosecdef
--   FROM   pg_proc
--   WHERE  pronamespace = 'public'::regnamespace
--     AND  proname IN ('prazo_limite','reservas_guard')
--   ORDER  BY proname;
--
-- 3) O FUSO. Uma data de verao e uma de inverno, lado a lado. Se os dois pares
--    derem a mesma hora UTC, 'Europe/Lisbon' NAO esta a ser aplicado e os alunos
--    ganham uma hora no verao - parar e corrigir antes de seguir.
--
--   SELECT public.prazo_limite('almoco',         DATE '2026-08-10') AS almoco_verao,
--          public.prazo_limite('almoco',         DATE '2026-01-15') AS almoco_inverno,
--          public.prazo_limite('pequeno_almoco', DATE '2026-08-10') AS pa_verao,
--          public.prazo_limite('pequeno_almoco', DATE '2026-01-15') AS pa_inverno;
--
--   Esperado, com a sessao em UTC (verao = WEST, UTC+1; inverno = WET, UTC+0):
--     almoco_verao    2026-08-10 08:00:00+00   <- 09:00 em Lisboa
--     almoco_inverno  2026-01-15 09:00:00+00   <- 09:00 em Lisboa
--     pa_verao        2026-08-09 22:00:00+00   <- 23:00 da vespera em Lisboa
--     pa_inverno      2026-01-14 23:00:00+00   <- 23:00 da vespera em Lisboa
--
--   (Se a tua sessao do editor SQL nao estiver em UTC, as horas aparecem no teu
--   fuso. O que tem de bater certo e a DIFERENCA de uma hora entre verao e
--   inverno, nao o texto exato.)
--
-- A verificacao a serio e a suite: `cd tests && bun test api/guards.test.ts`.
-- Depois deste passo devem passar a verde, das que hoje falham:
--   - a student cannot mark their own reservation as paid        (RES07)
--   - a student cannot set their own price                       (campos congelados)
--   - the server refuses a late dinner reservation ...           (RES06)
-- As restantes esperam pelos passos 3 a 5.
-- =============================================================================


-- =============================================================================
-- PASSO 3 - Restringir os valores permitidos (cancelamento_tipo e menus.tipo)
-- =============================================================================
-- O PASSO 2 ja policia o cancelamento_tipo, mas SO em sessoes de aluno: a
-- isencao de sistema (auth.uid() IS NULL) deixa passar o service_role, as
-- migracoes, os triggers e o editor SQL. E de proposito e e precisa. So que
-- isso quer dizer que o trigger nao e o sitio certo para garantir que o VALOR
-- em si faz sentido - uma restricao de tabela vale em todos os caminhos,
-- incluindo os que o trigger tem de deixar passar. Ameacas diferentes, nao
-- redundancia. E por isso que o teste "only allowed cancellation states can be
-- written" continua vermelho depois do PASSO 2: escreve por ligacao direta.
--
-- PORQUE E QUE UM VALOR ERRADO AQUI E PERIGOSO E NAO SO FEIO:
--
-- 1. reservas.ativa e GERADA como
--        cancelamento_tipo IS NULL OR cancelamento_tipo = 'reactivated'
--    Qualquer valor desconhecido - um erro de escrita, um caminho de codigo
--    futuro, um UPDATE a mao - da ativa = false EM SILENCIO. O aluno ve a
--    reserva desaparecer e a cozinha nunca a cozinha. Nao ha erro nenhum em
--    lado nenhum: o valor mau nao se anuncia, so desativa a reserva.
--
-- 2. public.prazo_limite() (PASSO 2) faz
--        CASE tipo WHEN 'pequeno_almoco' THEN 23:00 da vespera ELSE 09:00 $$
--    ou seja, um tipo desconhecido cai no ELSE e recebe o prazo do almoco em
--    vez de dar erro. Um menu com tipo mal escrito passaria a ter um prazo
--    silenciosamente errado.
--
-- Depois do PASSO 2, reservas.tipo vem sempre do menu (o trigger reescreve-o),
-- por isso a origem de um tipo mau so pode ser uma linha de menus. E ai que a
-- restricao tem de estar.
--
-- Verificado na base de testes antes de escrever isto: menus.tipo tem apenas
-- almoco (5), pequeno_almoco (3) e jantar (3); cancelamento_tipo tem apenas
-- NULL (744), reactivated (3) e user (1). Nenhuma linha fora do conjunto, nos
-- dois casos - nao ha dados para corrigir antes.
-- =============================================================================

BEGIN;

-- Falhar com uma mensagem util em vez de uma violacao de restricao cifrada.
-- Na base de testes nao ha linhas fora do conjunto; na da escola pode haver, e
-- nesse caso interessa saber QUAIS sao os valores, nao so que existem.
DO $$
DECLARE
  v_maus_cancel text;
  v_maus_tipo   text;
BEGIN
  SELECT string_agg(DISTINCT quote_literal(cancelamento_tipo), ', ')
    INTO v_maus_cancel
  FROM reservas
  WHERE cancelamento_tipo IS NOT NULL
    AND cancelamento_tipo NOT IN ('user','payment','reactivated');

  SELECT string_agg(DISTINCT quote_literal(tipo), ', ')
    INTO v_maus_tipo
  FROM menus
  WHERE tipo NOT IN ('pequeno_almoco','almoco','jantar');

  IF v_maus_cancel IS NOT NULL THEN
    RAISE EXCEPTION
      'Ha reservas com cancelamento_tipo fora do conjunto: %. '
      'Corrigir esses valores antes de aplicar a restricao.', v_maus_cancel;
  END IF;

  IF v_maus_tipo IS NOT NULL THEN
    RAISE EXCEPTION
      'Ha menus com tipo fora do conjunto: %. '
      'Corrigir esses valores antes de aplicar a restricao.', v_maus_tipo;
  END IF;
END $$;

-- DROP + ADD, e nao so ADD: nao existe ADD CONSTRAINT IF NOT EXISTS, e este
-- ficheiro tem de continuar a poder ser colado inteiro outra vez.
ALTER TABLE reservas DROP CONSTRAINT IF EXISTS reservas_cancelamento_tipo_chk;
ALTER TABLE reservas
  ADD CONSTRAINT reservas_cancelamento_tipo_chk
  CHECK (cancelamento_tipo IS NULL
         OR cancelamento_tipo IN ('user','payment','reactivated'));

ALTER TABLE menus DROP CONSTRAINT IF EXISTS menus_tipo_chk;
ALTER TABLE menus
  ADD CONSTRAINT menus_tipo_chk
  CHECK (tipo IN ('pequeno_almoco','almoco','jantar'));

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 3 (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) As duas restricoes existem. Esperado: 2 linhas.
--
--   SELECT conrelid::regclass AS tabela, conname, pg_get_constraintdef(oid) AS def
--   FROM   pg_constraint
--   WHERE  conname IN ('reservas_cancelamento_tipo_chk','menus_tipo_chk')
--   ORDER  BY conname;
--
--   Esperado:
--     menus     menus_tipo_chk                  CHECK (tipo = ANY (ARRAY['pequeno_almoco','almoco','jantar']))
--     reservas  reservas_cancelamento_tipo_chk  CHECK (cancelamento_tipo IS NULL OR cancelamento_tipo = ANY (...))
--
-- 2) PROVA DE QUE TRAVAM MESMO. Existir nao chega - isto tenta escrever valores
--    invalidos e tem de dar erro. Correr o bloco inteiro; o ROLLBACK garante que
--    nao fica nada. Depois do primeiro erro a transacao fica abortada, por isso
--    correr UM de cada vez, cada um com o seu BEGIN/ROLLBACK.
--
--   BEGIN;
--     UPDATE reservas SET cancelamento_tipo = 'nonsense'
--     WHERE  id = (SELECT id FROM reservas LIMIT 1);
--   ROLLBACK;
--
--   Esperado: ERROR ... viola a restricao de verificacao
--             "reservas_cancelamento_tipo_chk"   (SQLSTATE 23514)
--
--   BEGIN;
--     UPDATE menus SET tipo = 'lanche'
--     WHERE  id = (SELECT id FROM menus LIMIT 1);
--   ROLLBACK;
--
--   Esperado: ERROR ... viola a restricao de verificacao "menus_tipo_chk"
--             (SQLSTATE 23514)
--
--   Se ALGUM dos dois passar sem erro, a restricao respetiva nao ficou aplicada.
--   NOTA: ambos dao erro de proposito. Nao e a migracao a falhar - e a prova de
--   que a migracao funcionou. O ROLLBACK nao deixa rasto nenhum.
--
-- Depois deste passo, na suite:
--   - "only allowed cancellation states can be written" passa a verde.
--   Ficam 4 vermelhos, a espera dos passos 4, 4b e 5.
-- =============================================================================


-- =============================================================================
-- PASSOS 4 e 4b - RLS na cantina, revogar o anon, e limpar meses_liquidados
-- =============================================================================
-- Os dois passos vao juntos porque sao o mesmo problema visto de dois lados:
-- tabelas que qualquer pessoa consegue ler ou escrever por nao terem ambito
-- nenhum definido.
--
-- A CHAVE anon E PUBLICA - esta no supabase.js, vai no browser, e para isso que
-- serve. Por isso "so o anon consegue" nao e barreira nenhuma: e o mesmo que
-- dizer "qualquer pessoa com um navegador". Hoje, sem estar autenticado, da para
-- ler a tabela cantina inteira. Nao e teoria, e o que o teste
-- "an anonymous caller cannot read the staff table" prova todos os dias.
--
-- Levantamento feito na base de testes antes de escrever isto: de nove tabelas,
-- SO DUAS estao sem RLS - cantina e cancelamentos_especiais. As outras sete tem
-- RLS ligada, por isso o GRANT ao anon nelas nao da acesso a nada (fica la, mas
-- inerte; nao se mexe nisso aqui para nao alargar o passo sem necessidade).
--
-- QUATRO VERIFICACOES DE COMPATIBILIDADE, todas confirmadas contra a base real
-- antes de escrever este bloco. Estao aqui porque cada uma delas, se fosse
-- falsa, partia a aplicacao de maneira dificil de diagnosticar:
--
-- 1. O LOGIN CONTINUA A FUNCIONAR. O app.js le a cantina na linha 465, DEPOIS do
--    signInWithPassword da linha 439 - ou seja, ja como authenticated, nunca
--    como anon. Um utilizador da cantina encontra a sua propria linha pela nova
--    politica; um aluno sai antes disso, na consulta a alunos da linha 462.
--
-- 2. OS TESTES DE STAFF NOUTRAS POLITICAS CONTINUAM A RESOLVER. As politicas de
--    alunos, reservas e meses_liquidados fazem
--        EXISTS (SELECT 1 FROM cantina WHERE cantina.id = auth.uid())
--    Essa subconsulta passa agora pela RLS da cantina: a cantina ve a sua linha
--    (da true), o aluno nao ve nenhuma (da false). Certo nos dois sentidos - e o
--    que torna isto seguro em vez de sortudo.
--
-- 3. O reservas_guard() do PASSO 2 nao e afetado: e SECURITY DEFINER, por isso
--    a sua propria consulta a cantina passa ao lado da RLS.
--
-- 4. O UNICO RISCO REAL DO 4b ESTA COBERTO. obter_divida_por_mes e chamada pelo
--    cantina.js e NAO e SECURITY DEFINER, por isso le meses_liquidados como o
--    utilizador que a chama. Depois de cair o lixo, continua coberta pela
--    politica "Cantina vê todos meses liquidados" - que por sua vez depende da
--    subconsulta do ponto 2. As duas coisas tem de se aguentar em conjunto, e
--    aguentam.
--
-- -----------------------------------------------------------------------------
-- DESVIO AO PLANO - LER ANTES DO CLUSTER 6
-- -----------------------------------------------------------------------------
-- O plano acordado (internal-solutions.md, Cluster 2 Passo 4) revoga o anon em
-- cancelamentos_especiais e deixa a RLS dessa tabela para o CLUSTER 6.
--
-- >>> A RLS DE cancelamentos_especiais E LIGADA AQUI, NO CLUSTER 2. <<<
-- >>> O CLUSTER 6 NAO VOLTA A LIGA-LA. So lhe faltam POLITICAS.     <<<
--
-- Porque se antecipou: revogar so o anon fechava metade da porta. A tabela esta
-- sem RLS e o role authenticated tem DELETE, INSERT, SELECT e UPDATE - ou seja,
-- qualquer aluno com sessao iniciada pode ler e escrever la assim que houver
-- linhas. O teste da suite so verifica o lado anonimo, por isso teria ficado
-- verde com o buraco na mesma aberto.
--
-- Porque nao custa nada agora: a tabela tem 0 linhas, nenhum ficheiro JS lhe
-- toca, e as cinco RPC dela (solicitar_/aprovar_/rejeitar_cancelamento_especial,
-- listar_solicitacoes_pendentes, verificar_status_cancelamentos) nao sao
-- chamadas de lado nenhum. A funcionalidade esta inalcancavel hoje.
--
-- O QUE ISTO CUSTA, dito com todas as letras: liga-se a RLS sem politica
-- nenhuma, portanto a tabela fica FECHADA A TODOS menos ao service_role. Como
-- aquelas cinco RPC nao sao SECURITY DEFINER, quando o Cluster 6 ligar a
-- funcionalidade tera OBRIGATORIAMENTE de escrever politicas - senao rebenta.
-- E deliberado: falha fechada e barulhenta, em vez de funcionar enquanto
-- qualquer aluno le o que la esta.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 4 ---
ALTER TABLE cantina ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Cantina vê o seu registo" ON cantina;
CREATE POLICY "Cantina vê o seu registo" ON cantina
  FOR SELECT TO authenticated USING (id = auth.uid());

-- Desvio assinalado acima: a RLS aqui e do Cluster 2, nao do Cluster 6.
-- Sem politicas de proposito - fechada a todos menos ao service_role.
ALTER TABLE cancelamentos_especiais ENABLE ROW LEVEL SECURITY;

-- A RLS nao desfaz um GRANT. Sem estes REVOKE, a chave publica continuava a
-- chegar as duas tabelas.
REVOKE SELECT ON cantina                 FROM anon;
REVOKE SELECT ON cancelamentos_especiais FROM anon;

-- --------------------------------------------------------------- PASSO 4b ---
-- Quatro politicas permissivas sobrepostas que davam a QUALQUER autenticado o
-- historico de pagamentos de toda a gente, e o direito de inventar pagamentos.
-- As com ambito ("Aluno vê seus meses liquidados", "Cantina vê todos meses
-- liquidados") cobrem tudo o que e legitimo. As escritas vem so da
-- liquidar_mes_divida, que e SECURITY DEFINER desde a 001 e ja confirma que
-- quem chama e da cantina - por isso nao faz falta politica de INSERT nenhuma.
DROP POLICY IF EXISTS "Allow insert via RPC"           ON meses_liquidados;
DROP POLICY IF EXISTS "Insert via RPC"                 ON meses_liquidados;
DROP POLICY IF EXISTS "Allow select for authenticated" ON meses_liquidados;
DROP POLICY IF EXISTS "Select for authenticated"       ON meses_liquidados;

COMMIT;

-- =============================================================================
-- VERIFICACAO DOS PASSOS 4 e 4b (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) RLS ligada nas duas tabelas que faltavam. Esperado: as nove a true.
--
--   SELECT relname, relrowsecurity
--   FROM   pg_class
--   WHERE  relnamespace = 'public'::regnamespace AND relkind = 'r'
--   ORDER  BY relname;
--
-- 2) O anon ja nao le as duas tabelas. Esperado: ZERO linhas.
--
--   SELECT table_name, privilege_type
--   FROM   information_schema.role_table_grants
--   WHERE  table_schema = 'public' AND grantee = 'anon'
--     AND  table_name IN ('cantina','cancelamentos_especiais');
--
-- 3) meses_liquidados fica com DUAS politicas, ambas com ambito. Se aparecer
--    alguma com auth.role() = 'authenticated', um DROP nao apanhou o nome.
--
--   SELECT policyname, cmd, qual
--   FROM   pg_policies
--   WHERE  schemaname = 'public' AND tablename = 'meses_liquidados'
--   ORDER  BY policyname;
--
--   Esperado (2 linhas):
--     Aluno vê seus meses liquidados     SELECT  (aluno_id = auth.uid())
--     Cantina vê todos meses liquidados  SELECT  (EXISTS ... FROM cantina ...)
--
-- 4) A cantina fica com UMA politica.
--
--   SELECT policyname, cmd, qual FROM pg_policies
--   WHERE schemaname = 'public' AND tablename = 'cantina';
--
--   Esperado (1 linha): Cantina vê o seu registo | SELECT | (id = auth.uid())
--
-- 5) O LOGIN. Esta e a verificacao que nao se faz por SQL: abrir a app e entrar
--    com as DUAS contas, aluno e cantina. O ponto 1 das notas acima diz porque
--    deve funcionar, mas isso e raciocinio - convem ver. A suite tambem cobre
--    (ui/watchdog.spec.ts testa os dois logins).
--
-- Depois destes passos, na suite:
--   - "an anonymous caller cannot read the staff table"            passa a verde
--   - "an anonymous caller cannot read cancelamentos_especiais"    passa a verde
--   - "a student cannot fabricate a payment record"                passa a verde
--   Fica 1 vermelho, a espera do PASSO 5 (notificacoes).
-- =============================================================================


-- =============================================================================
-- PASSO 5 - Apertar as notificacoes
-- =============================================================================
-- O buraco: notificacoes tem uma politica de INSERT com WITH CHECK (true) para
-- o role authenticated. Ou seja, QUALQUER aluno com sessao iniciada pode criar
-- uma notificacao para QUALQUER outro aluno - com o titulo e a mensagem que
-- quiser, e a aparecer no ecra do outro exatamente como se fosse da cantina.
-- Nao e leitura de dados alheios, e escrever na voz da cantina.
--
-- As duas politicas com ambito que os alunos precisam ja estao certas e NAO se
-- mexem:
--   "Alunos podem ler suas notificações"       SELECT  (aluno_id = auth.uid())
--   "Alunos podem atualizar suas notificações" UPDATE  (aluno_id = auth.uid())
--
-- PORQUE E QUE A POLITICA DE INSERT E SUBSTITUIDA E NAO SO APAGADA:
-- o cantina.js linha 707 chama a RPC notificar_menu_alterado, e essa funcao NAO
-- e SECURITY DEFINER - corre como quem a chama, ou seja, como o utilizador da
-- cantina. Sem politica de INSERT nenhuma, alterar um prato deixava de notificar
-- os alunos, em silencio. A politica nova da a cantina o que ela precisa e tira
-- ao aluno o que ele nunca devia ter tido.
--
-- UMA HIPOTESE QUE SE CONFIRMOU FALSA, registada para nao se voltar a levantar:
-- a politica "Permitir atualização via função RPC" tem WITH CHECK (true) e
-- nenhum USING, o que parecia deixar um aluno reatribuir uma notificacao sua a
-- outro aluno - o mesmo buraco por outra porta. NAO deixa: testado, da 42501.
-- Sem clausula USING aquela politica nao autoriza linha nenhuma, por isso o
-- WITH CHECK dela nunca chega a entrar na conta. Cai aqui por ser peso morto e
-- por confundir quem a le, nao por tapar nada.
--
-- SIMULADO ANTES DE ESCREVER (sessoes reais de PostgREST reproduzidas com
-- SET LOCAL ROLE + request.jwt.claims, tudo dentro de transacoes revertidas):
--   cantina insere notificacao ................ PERMITIDO  (a RPC continua a dar)
--   aluno insere para outro aluno ............. RECUSADO 42501
--   aluno marca a SUA como lida ............... PERMITIDO  (sem regressao)
--   aluno marca a de OUTRO como lida .......... 0 linhas
-- A terceira era a que interessava: nenhum teste da suite cobre "o aluno
-- consegue marcar a sua como lida", por isso um erro ao tirar a politica de
-- UPDATE passaria despercebido. Foi por isso que se simulou em vez de deduzir.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "Permitir inserção via função RPC"    ON notificacoes;
DROP POLICY IF EXISTS "Permitir atualização via função RPC" ON notificacoes;

DROP POLICY IF EXISTS "Cantina cria notificacoes" ON notificacoes;
CREATE POLICY "Cantina cria notificacoes" ON notificacoes
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()));

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 5 (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) Ficam TRES politicas, todas com ambito. Nenhuma com true nem com
--    auth.role() = 'authenticated'.
--
--   SELECT policyname, cmd, qual, with_check
--   FROM   pg_policies
--   WHERE  schemaname = 'public' AND tablename = 'notificacoes'
--   ORDER  BY cmd, policyname;
--
--   Esperado (3 linhas):
--     Cantina cria notificacoes                INSERT  -                      (EXISTS ... cantina ...)
--     Alunos podem ler suas notificações       SELECT  (aluno_id = auth.uid())  -
--     Alunos podem atualizar suas notificações UPDATE  (aluno_id = auth.uid()) (aluno_id = auth.uid())
--
-- 2) A suite e a prova a serio, e cobre os dois lados:
--      "a student cannot fabricate a notification for another student"  -> passa a verde
--      "a student cannot mark another student's notification as read"   -> tem de CONTINUAR verde
--
-- 3) O QUE A SUITE NAO COBRE, e por isso convem ver a olho uma vez: que a
--    cantina continua a notificar ao alterar um prato. Entrar como cantina,
--    "Menus Criados", escolher um dia com almoco, "Alterar" o prato, e depois
--    entrar como aluno e confirmar que a notificacao aparece. Se nao aparecer, a
--    politica de INSERT nova nao esta a apanhar a RPC notificar_menu_alterado.
--    (Testado por simulacao antes de escrever este passo, mas simulacao nao e a
--    aplicacao a correr.)
--
-- NAO TOCADO DE PROPOSITO, e nao e esquecimento:
--   apagar_notificacoes_aluno e apagar_notificacoes_antigas nao sao SECURITY
--   DEFINER e nao existe politica de DELETE em notificacoes - logo ja hoje
--   falham. Nenhuma das duas e chamada por JS nenhum. E um caminho morto que ja
--   la estava; arranja-se com o trabalho das notificacoes (decisao aberta 3),
--   nao a socapa dentro de um passo de seguranca.
--
-- Depois deste passo a suite fica com tier C todo verde, e o Cluster 2 fica
-- completo. FALTA A CORRIDA DEPOIS DAS 09:00 UTC: o teste do prazo do jantar
-- (PASSO 2) salta enquanto for antes disso, por isso ainda nao ha prova verde do
-- prazo do lado do servidor. Ver estado-atual.md, ponto 14.
-- =============================================================================
