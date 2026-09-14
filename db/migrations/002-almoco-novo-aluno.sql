-- =============================================================================
-- 002 - Almoco automatico tambem para alunos novos
-- =============================================================================
-- DEPENDE DA 001 (precisa da restricao unica reservas_aluno_data_tipo_key para
-- o ON CONFLICT). Correr sempre depois.
--
-- O QUE RESOLVE
--   O almoco e automatico, mas so era criado num sentido: quando nasce um menu,
--   para os alunos que ja existiam. Um aluno inscrito depois de o menu estar
--   criado nunca chegava a ter reserva desse almoco - e como o ecra do aluno
--   mostra "Reservado automaticamente" sem consultar nada, ninguem dava por isso
--   ate o aluno aparecer na cantina e nao estar na lista.
--
--   Isto fecha o outro sentido: quando nasce um aluno, cria as reservas dos
--   almocos que ainda contam para ele.
--
--   Os alunos sao inseridos a mao, sem interface. Um trigger apanha todos os
--   caminhos - SQL Editor, importacao, script - que e a razao de ser um trigger
--   e nao codigo na aplicacao.
--
-- REGRA (definida pelo Pedro)
--   Almocos futuros, mais o de hoje se ainda nao passaram as 9h.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Verificar que a 001 ja correu
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'reservas_aluno_data_tipo_key'
      AND conrelid = 'reservas'::regclass
  ) THEN
    RAISE EXCEPTION
      'Falta a restricao reservas_aluno_data_tipo_key. Correr a migracao 001 primeiro.';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Criar as reservas de almoco quando entra um aluno novo
-- -----------------------------------------------------------------------------
-- ATENCAO AO FUSO HORARIO. O Postgres do Supabase corre em UTC; a escola esta em
-- Portugal continental (WET/WEST, UTC+0 no inverno e UTC+1 no verao). Comparar
-- com CURRENT_DATE ou CURRENT_TIME diretamente estaria errado metade do ano:
--   - no verao, "antes das 9h" em UTC e na verdade antes das 10h em Lisboa, e um
--     aluno inscrito as 9h30 recebia o almoco de hoje sem dever receber;
--   - a seguir a meia-noite em Lisboa, CURRENT_DATE em UTC ainda e o dia anterior,
--     por isso "hoje" nao era hoje.
-- Por isso tudo e convertido para Europe/Lisbon antes de comparar. A conversao
-- trata das mudancas de hora sozinha.
CREATE OR REPLACE FUNCTION public.criar_reservas_almoco_novo_aluno()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_local timestamp := now() AT TIME ZONE 'Europe/Lisbon';
  v_hoje  date      := v_local::date;
  v_hora  time      := v_local::time;
BEGIN
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

CREATE TRIGGER trg_criar_reservas_almoco_novo_aluno
  AFTER INSERT ON alunos
  FOR EACH ROW EXECUTE FUNCTION criar_reservas_almoco_novo_aluno();

COMMIT;

-- =============================================================================
-- NOTAS
-- =============================================================================
-- INSERCOES EM LOTE. O trigger e FOR EACH ROW, por isso inserir 149 alunos de uma
-- vez corre-o 149 vezes. A esta escala nao ha problema nenhum, e e o que se quer:
-- um lote de alunos novos fica com os almocos todos. Mas quer dizer que correr o
-- seed de testes depois desta migracao ja cria reservas, ao contrario de antes.
--
-- ASSIMETRIA CONHECIDA, DE PROPOSITO. Se a cantina criar um menu de almoco para
-- hoje as 15h, o trigger dos menus da esse almoco a toda a gente, mesmo passadas
-- as 9h - a cantina decidiu servir e sabe o que esta a fazer. Ja um aluno inscrito
-- as 15h nao apanha o almoco de hoje, porque a hora de almoco ja passou. As duas
-- regras sao diferentes porque as situacoes sao diferentes; nao e um esquecimento.
--
-- Ha uma regra da escola, fora da aplicacao, que confirma isto: a cantina tem de
-- publicar os almocos da semana seguinte ate a quinta-feira anterior. Ou seja, o
-- normal e os menus existirem com uma semana de antecedencia, e um menu criado
-- para o proprio dia e uma excecao que a cantina esta a abrir de proposito - faz
-- sentido nao lhe aplicar limite de horas. Nao se enforca essa regra em codigo:
-- e um prazo de organizacao, nao uma regra da aplicacao. Ver estado-atual.md.
--
-- Essa mesma regra e o que torna esta migracao necessaria e nao apenas simpatica:
-- havendo sempre menus publicados para a semana seguinte, qualquer aluno inscrito
-- a meio da semana caia no buraco - ficava sem os almocos todos ate ao fim da
-- semana seguinte. Nao e um caso raro, e o caso normal de um aluno novo.
--
-- O QUE ISTO **NAO** RESOLVE. O cartao do almoco em aluno.js (_cartoesReservaDia)
-- continua a escrever "Reservado automaticamente" sem consultar a base de dados.
-- Depois desta migracao isso passa a ser verdade para alunos novos, mas continua a
-- mentir quando a reserva existe e esta CANCELADA - pelo proprio aluno, ou pela
-- cantina depois do Cluster 6. Ver Cluster 3 em internal-solutions.md.
--
-- VERIFICACAO
--   -- 1. contar almocos que ainda contam
--   -- SELECT count(*) FROM menus
--   --   WHERE tipo='almoco' AND data >= (now() AT TIME ZONE 'Europe/Lisbon')::date;
--   --
--   -- 2. inserir um aluno de teste e confirmar que ficou com esse numero de reservas
--   -- INSERT INTO alunos (id, nome, email)
--   --   VALUES (gen_random_uuid(), 'Teste Trigger', 'teste-trigger@example.org');
--   -- SELECT count(*) FROM reservas r JOIN alunos a ON a.id = r.aluno_id
--   --   WHERE a.email = 'teste-trigger@example.org';
--   --
--   -- 3. limpar
--   -- DELETE FROM alunos WHERE email = 'teste-trigger@example.org';  -- reservas caem por CASCADE
--   --
--   -- 4. confirmar a hora que o Postgres esta mesmo a usar
--   -- SELECT now() AS utc, now() AT TIME ZONE 'Europe/Lisbon' AS lisboa;
-- =============================================================================
