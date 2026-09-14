-- =============================================================================
-- 005 - Cancelamentos especiais (Cluster 6, passos 1 e 2)
-- =============================================================================
-- DEPENDE DA 001 (coluna ativa, cancelada apagada) e da 003 (a RLS desta tabela
-- ja esta LIGADA - ver o PASSO 2).
--
-- Isto e a metade SQL do Cluster 6. Os passos 3 e 4 (ecras do aluno e da
-- cantina) ficam para depois: dependem destas funcoes existirem e poderem ser
-- chamadas, e nao vale a pena escrever testes de browser contra RPCs que ainda
-- rebentam.
--
-- -----------------------------------------------------------------------------
-- O ESTADO EM QUE ISTO ESTAVA, medido em 2026-08-09 antes de escrever nada
-- -----------------------------------------------------------------------------
-- A funcionalidade esta MORTA HOJE, e por duas razoes independentes:
--
-- 1. Duas funcoes ainda leem a coluna `cancelada`, que a 001 apagou. O corpo de
--    uma funcao plpgsql so e analisado quando corre, por isso nada disto deu
--    erro na migracao - da erro na primeira chamada a serio. E exatamente para
--    isto que existe o cancelada-refs.md.
-- 2. Todas as funcoes correm com os direitos de quem chama, e a tabela tem RLS
--    ligada SEM POLITICAS desde a 003. Ou seja, mesmo sem o problema 1 nao viam
--    uma linha.
--
-- Nada disto e uma regressao: esta funcionalidade nunca esteve acessivel. O
-- solicitar_cancelamento_especial ainda usa currval() sobre uma sequencia que
-- nao existe, o que ja constava do diagnostico original.
--
-- -----------------------------------------------------------------------------
-- DOIS DESVIOS AO PLANO (internal-solutions.md Cluster 6 Passo 1)
-- -----------------------------------------------------------------------------
-- 1. O rejeitar_cancelamento_especial NAO PODE "FICAR COMO ESTA". O plano manda
--    so confirmar que nao le `cancelada` - e nao le. Mas faz UPDATE, e o PASSO 2
--    de propria vontade nao cria politica de UPDATE nenhuma, portanto tem de
--    passar a SECURITY DEFINER. E no momento em que passa, a falta de
--    verificacao de quem chama deixa QUALQUER ALUNO rejeitar o pedido de
--    qualquer outro. Leva as duas coisas: definer e verificacao de staff. Sem
--    isto, o Cluster 6 deixava a tabela pior do que a encontrou.
--
-- 2. O listar_solicitacoes_pendentes FICA COM OS DIREITOS DE QUEM CHAMA, de
--    propria vontade. E a parte elegante: com as duas politicas de SELECT do
--    PASSO 2, o ambito faz-se sozinho - a cantina ve todos os pedidos, o aluno
--    ve so os seus. Passa-la a SECURITY DEFINER estragava isso e obrigava a
--    escrever a verificacao a mao. NAO MEXER.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---

-- APAGAR AS VERSOES ANTIGAS PRIMEIRO. Isto NAO e limpeza opcional.
--
-- As assinaturas antigas recebem a identidade de quem chama como PARAMETRO:
--   solicitar_cancelamento_especial(p_aluno_id uuid, p_reserva_id uuid, ...)
--   aprovar_cancelamento_especial  (p_solicitacao_id uuid, p_cantina_id uuid, ...)
--   rejeitar_cancelamento_especial (p_solicitacao_id uuid, p_cantina_id uuid, ...)
-- ou seja, quem chama diz quem e. As novas usam auth.uid(), que ninguem pode
-- inventar - e por isso que as assinaturas mudam.
--
-- E porque mudam, um CREATE OR REPLACE NAO SUBSTITUI NADA: cria uma sobrecarga
-- nova ao lado da antiga. Ficavam as duas na base de dados, a antiga ainda
-- alcancavel pelo anon e a aceitar qualquer identidade que lhe passassem. Foi
-- apanhado a correr esta migracao em seco antes de a aplicar; sem esse ensaio
-- tinha entrado assim.
--
-- Os tipos abaixo sao os EXATOS. Um DROP FUNCTION com os tipos errados nao da
-- erro nenhum - nao apaga nada e a transacao passa a mesma (foi o D8 da 001).
-- A verificacao 1 la em baixo conta as funcoes precisamente por causa disto.
DROP FUNCTION IF EXISTS public.solicitar_cancelamento_especial(uuid, uuid, text, boolean, text);
DROP FUNCTION IF EXISTS public.aprovar_cancelamento_especial(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.rejeitar_cancelamento_especial(uuid, uuid, text);

-- Pedido do aluno. Reescrita: fora o currval() sobre uma sequencia inexistente,
-- fora a leitura da coluna `cancelada`, e passa a confirmar que a reserva e mesmo
-- do aluno que esta a pedir, que esta ativa e que e um almoco.
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

-- Decisao da cantina. 'outros' mantem a reserva de propria vontade: a refeicao
-- continua a ser servida (como lanche substituto) e continua a ser devida, por
-- isso nao ha alteracao de preco nem cancelamento. A substituicao fica registada
-- no proprio pedido. Isto esta decidido, nao e uma pergunta em aberto.
CREATE OR REPLACE FUNCTION public.aprovar_cancelamento_especial(
  p_solicitacao_id uuid,
  p_decisao text DEFAULT 'cancelar',
  p_observacoes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE s record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode aprovar';
  END IF;
  IF p_decisao NOT IN ('cancelar','dieta','outros') THEN
    RAISE EXCEPTION 'Decisao invalida: %. Usar cancelar, dieta ou outros.', p_decisao;
  END IF;

  SELECT * INTO s FROM cancelamentos_especiais
   WHERE id = p_solicitacao_id AND status = 'pendente';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente ou ja processado';
  END IF;

  IF    p_decisao = 'cancelar' THEN
    UPDATE reservas SET cancelamento_tipo = 'user' WHERE id = s.reserva_id;
  ELSIF p_decisao = 'dieta' THEN
    UPDATE reservas SET is_dieta = true WHERE id = s.reserva_id;
  END IF;

  UPDATE cancelamentos_especiais
     SET status = 'aprovado',
         cantina_responsavel = auth.uid(),
         motivo = COALESCE(p_observacoes, motivo),
         atualizado_em = now()
   WHERE id = p_solicitacao_id;
END; $fn$;

-- Desvio 1: definer + verificacao de staff. Antes nao tinha nem uma nem outra.
CREATE OR REPLACE FUNCTION public.rejeitar_cancelamento_especial(
  p_solicitacao_id uuid,
  p_observacoes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina pode rejeitar';
  END IF;

  UPDATE cancelamentos_especiais
     SET status = 'rejeitado',
         cantina_responsavel = auth.uid(),
         motivo = COALESCE(p_observacoes, motivo),
         atualizado_em = now()
   WHERE id = p_solicitacao_id AND status = 'pendente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido inexistente ou ja processado';
  END IF;
END; $fn$;

-- Accao direta da cantina, para quando o aluno telefona em vez de usar o botao.
-- Deixa rasto no mesmo sitio, ja como 'aprovado', para o historico nao ter
-- buracos de coisas que aconteceram fora da app.
CREATE OR REPLACE FUNCTION public.cantina_alterar_reserva(
  p_reserva_id uuid,
  p_decisao text,
  p_nota text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Apenas a cantina';
  END IF;
  IF p_decisao NOT IN ('cancelar','dieta','normal') THEN
    RAISE EXCEPTION 'Decisao invalida: %. Usar cancelar, dieta ou normal.', p_decisao;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM reservas WHERE id = p_reserva_id) THEN
    RAISE EXCEPTION 'Reserva inexistente';
  END IF;

  IF    p_decisao = 'cancelar' THEN
    UPDATE reservas SET cancelamento_tipo = 'user' WHERE id = p_reserva_id;
  ELSIF p_decisao = 'dieta' THEN
    UPDATE reservas SET is_dieta = true  WHERE id = p_reserva_id;
  ELSIF p_decisao = 'normal' THEN
    UPDATE reservas SET is_dieta = false WHERE id = p_reserva_id;
  END IF;

  INSERT INTO cancelamentos_especiais
    (aluno_id, reserva_id, motivo, status, cantina_responsavel)
  SELECT r.aluno_id, r.id, COALESCE(p_nota, 'Alteracao direta pela cantina'),
         'aprovado', auth.uid()
  FROM reservas r WHERE r.id = p_reserva_id;
END; $fn$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- A RLS desta tabela JA ESTA LIGADA - foi ligada na 003 PASSO 4, no Cluster 2,
-- e nao aqui como o plano previa. O que faltava eram as politicas. O ALTER fica
-- na mesma por ser idempotente e para o ficheiro se aguentar sozinho.
ALTER TABLE cancelamentos_especiais ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Aluno vê os seus pedidos"    ON cancelamentos_especiais;
CREATE POLICY "Aluno vê os seus pedidos" ON cancelamentos_especiais
  FOR SELECT TO authenticated USING (aluno_id = auth.uid());

DROP POLICY IF EXISTS "Cantina vê todos os pedidos" ON cancelamentos_especiais;
CREATE POLICY "Cantina vê todos os pedidos" ON cancelamentos_especiais
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM cantina WHERE id = auth.uid()));

-- Sem politicas de INSERT nem de UPDATE, de propria vontade: as escritas passam
-- todas pelas funcoes SECURITY DEFINER acima, que verificam quem chama.

-- ---------------------------------------------------------------- PASSO 3 ---
-- A licao da 004 PASSO 4, aplicada a nascenca em vez de a posteriori: uma funcao
-- nova nasce com EXECUTE para o PUBLIC, e o PUBLIC e uma concessao separada do
-- anon e do authenticated. Revogar so os roles nao fecha nada.
--
-- O anon nunca precisa de nenhuma destas: sem sessao nao ha auth.uid() e todas
-- rebentariam - mas rebentar com "Apenas a cantina" e pior do que nem sequer
-- estar la, porque confirma a quem sonda que a funcao existe.
REVOKE EXECUTE ON FUNCTION public.solicitar_cancelamento_especial(uuid, text, boolean, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.aprovar_cancelamento_especial(uuid, text, text)            FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rejeitar_cancelamento_especial(uuid, text)                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cantina_alterar_reserva(uuid, text, text)                  FROM PUBLIC, anon;

-- O authenticated fica com todas: o aluno precisa de pedir, a cantina precisa de
-- decidir, e as tres da cantina confirmam la dentro quem esta a chamar.
GRANT EXECUTE ON FUNCTION public.solicitar_cancelamento_especial(uuid, text, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.aprovar_cancelamento_especial(uuid, text, text)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.rejeitar_cancelamento_especial(uuid, text)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.cantina_alterar_reserva(uuid, text, text)                  TO authenticated;

COMMIT;

-- =============================================================================
-- VERIFICACAO (correr a seguir, fora da transacao)
-- =============================================================================
-- 1) As quatro funcoes existem e sao SECURITY DEFINER; a listar_ NAO e, e isso
--    e de propria vontade (desvio 2).
--
--   SELECT proname, prosecdef
--   FROM   pg_proc
--   WHERE  pronamespace = 'public'::regnamespace
--     AND  proname IN ('solicitar_cancelamento_especial','aprovar_cancelamento_especial',
--                      'rejeitar_cancelamento_especial','cantina_alterar_reserva',
--                      'listar_solicitacoes_pendentes')
--   ORDER  BY proname;
--
--   Esperado:
--     aprovar_cancelamento_especial    t
--     cantina_alterar_reserva          t
--     listar_solicitacoes_pendentes    f   <- tem de ser f
--     rejeitar_cancelamento_especial   t   <- era f antes desta migracao
--     solicitar_cancelamento_especial  t
--
-- 2) Ja nao ha nenhuma referencia a coluna apagada.
--
--   SELECT proname FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND prosrc ~ '\mcancelada\M'
--     AND proname LIKE '%cancelamento%';
--
--   Esperado: ZERO linhas.
--
--   ATENCAO: o prosrc inclui os COMENTARIOS do corpo da funcao. Na primeira
--   aplicacao desta migracao esta consulta devolveu solicitar_cancelamento_especial
--   e nao havia problema nenhum - era um comentario que explicava que a coluna ja
--   nao existe, e a mencionava pelo nome. Codigo nenhum a lia. O comentario foi
--   reescrito para a consulta voltar a ser um sim-ou-nao limpo, porque uma
--   verificacao de seguranca que falha por bem e uma verificacao que se aprende a
--   ignorar. Se isto voltar a acusar alguma coisa, ver PRIMEIRO se a linha e um
--   comentario - mas nao deixar assim.
--
-- 3) As duas politicas de SELECT, e nenhuma de escrita.
--
--   SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname='public' AND tablename='cancelamentos_especiais' ORDER BY policyname;
--
--   Esperado (2 linhas, ambas SELECT):
--     Aluno vê os seus pedidos      SELECT
--     Cantina vê todos os pedidos   SELECT
--
-- 4) O anon nao chega la, o authenticated chega.
--
--   SELECT p.proname,
--          has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth
--   FROM   pg_proc p
--   WHERE  p.pronamespace = 'public'::regnamespace
--     AND  p.proname IN ('solicitar_cancelamento_especial','aprovar_cancelamento_especial',
--                        'rejeitar_cancelamento_especial','cantina_alterar_reserva')
--   ORDER  BY p.proname;
--
--   Esperado: anon = f nas quatro, auth = t nas quatro.
--
-- 5) OS TESTES DESTE CLUSTER AINDA NAO ESTAO ESCRITOS. A suite continua verde
--    depois desta migracao, mas isso nao prova nada sobre ela - nao ha um unico
--    teste que lhe toque. Ficam por escrever, AOS PARES, porque e o par que tem
--    significado:
--      - positivos (tier B): a cantina consegue aprovar, rejeitar e listar; o
--        aluno consegue pedir. VERMELHOS antes desta migracao, verdes depois.
--        Sao estes que provam que ficou a funcionar.
--      - negativos (tier C): um aluno nao consegue aprovar, rejeitar, nem ver
--        pedidos de outros. Estes ja passam ANTES da migracao, mas pela razao
--        errada - a funcionalidade esta morta, tudo rebenta. Sozinhos nao provam
--        nada. O que interessa e que continuem verdes DEPOIS, quando ja existe
--        alguma coisa a proteger.
--
-- NAO TOCADAS, e nao e esquecimento:
--   contar_cancelamentos_usuario(uuid, int, int) e
--   verificar_status_cancelamentos(uuid) continuam com os direitos de quem chama
--   e a receber o aluno como parametro. So leem, e a partir do PASSO 2 a RLS
--   trata do ambito: quem passar o id de outro aluno recebe zero linhas, e um
--   anon nao tem auth.uid() nenhum, por isso tambem nao ve nada. Ficam para o
--   Cluster 7, com o resto da limpeza.
-- =============================================================================


-- =============================================================================
-- PASSO 4 - listar_solicitacoes_pendentes: COUNT(*) devolve bigint
-- =============================================================================
-- ESCRITO DEPOIS DE OS PASSOS 1 A 3 JA ESTAREM APLICADOS, em transacao propria,
-- porque foi assim que aconteceu: o teste do tier B apanhou isto.
--
-- O plano dizia que esta funcao podia "ficar como esta", so confirmando que nao
-- lia a coluna apagada. E nao lia. Mas estava avariada por um terceiro motivo
-- que ninguem tinha visto:
--
--   42804: Returned type bigint does not match expected type integer in column 11
--
-- A coluna 11 e o COUNT(*) dos cancelamentos dos ultimos 30 dias. O COUNT(*)
-- devolve bigint, e o RETURNS TABLE declara integer.
--
-- PORQUE E QUE ISTO NUNCA DEU NAS VISTAS: o erro so acontece quando ha LINHAS
-- para devolver. Com a tabela vazia - que era o estado permanente, porque a
-- funcionalidade nunca esteve acessivel - a funcao devolve zero linhas e nunca
-- chega a comparar tipo nenhum. Passava por boa em qualquer verificacao que nao
-- criasse primeiro um pedido pendente. Foi preciso um teste que criasse dois
-- pedidos e os fosse buscar para isto aparecer.
--
-- A correcao e um cast. O corpo e o mesmo do original, linha por linha, com
-- ::int no COUNT - nao se aproveitou para reescrever mais nada, para o diff
-- dizer exatamente o que mudou.
--
-- Continua SEM SECURITY DEFINER, de propria vontade: as politicas do PASSO 2
-- fazem o ambito sozinhas (a cantina ve tudo, o aluno so o que e dele). Ver o
-- desvio 2 no cabecalho deste ficheiro.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.listar_solicitacoes_pendentes()
RETURNS TABLE(solicitacao_id uuid, aluno_id uuid, aluno_nome text, reserva_id uuid,
              data_reserva date, tipo_refeicao text, motivo text,
              troca_por_lanche boolean, lanche_substituto text,
              data_solicitacao date, cancelamentos_30_dias integer)
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN QUERY
    SELECT
        ce.id as solicitacao_id,
        ce.aluno_id,
        a.nome as aluno_nome,
        ce.reserva_id,
        r.data as data_reserva,
        r.tipo as tipo_refeicao,
        ce.motivo,
        ce.troca_por_lanche,
        ce.lanche_substituto,
        ce.data_cancelamento as data_solicitacao,
        (
            SELECT COUNT(*)::int          -- <- a unica alteracao
            FROM cancelamentos_especiais ce2
            JOIN reservas r2 ON ce2.reserva_id = r2.id
            WHERE ce2.aluno_id = ce.aluno_id
              AND ce2.data_cancelamento >= CURRENT_DATE - INTERVAL '30 days'
              AND ce2.status = 'aprovado'
              AND r2.tipo = 'almoco'
        ) as cancelamentos_30_dias
    FROM cancelamentos_especiais ce
    JOIN alunos a ON ce.aluno_id = a.id
    JOIN reservas r ON ce.reserva_id = r.id
    WHERE ce.status = 'pendente'
    ORDER BY ce.data_cancelamento DESC;
END; $fn$;

COMMIT;

-- =============================================================================
-- VERIFICACAO DO PASSO 4
-- =============================================================================
-- Nao ha consulta de catalogo que prove isto: a funcao ja existia e continua a
-- existir com a mesma assinatura. O que prova e chama-la COM LINHAS LA DENTRO,
-- que e precisamente o que nunca tinha sido feito.
--
--   BEGIN;
--     INSERT INTO cancelamentos_especiais (aluno_id, reserva_id, motivo, status)
--     SELECT r.aluno_id, r.id, 'Teste do cast', 'pendente'
--     FROM reservas r WHERE r.tipo = 'almoco' AND r.ativa LIMIT 1;
--
--     SELECT solicitacao_id, aluno_nome, cancelamentos_30_dias
--     FROM listar_solicitacoes_pendentes();
--   ROLLBACK;
--
--   Esperado: 1 linha, com cancelamentos_30_dias = 0.
--   Antes deste passo isto dava 42804 em vez de devolver a linha.
--
-- Na suite: "the canteen sees every pending request, the student only their own"
-- (tier B) passa a verde. E o teste que encontrou isto.
-- =============================================================================
