-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.alunos (
  criado_em timestamp with time zone DEFAULT now(),
  id uuid NOT NULL,
  nome text NOT NULL,
  email text NOT NULL UNIQUE,
  CONSTRAINT alunos_pkey PRIMARY KEY (id)
);
CREATE TABLE public.cantina (
  id uuid NOT NULL,
  nome text NOT NULL,
  email text NOT NULL UNIQUE,
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT cantina_pkey PRIMARY KEY (id)
);
CREATE TABLE public.menus (
  prato_anterior text,
  data_alteracao timestamp with time zone,
  motivo_alteracao text,
  data date NOT NULL,
  tipo text NOT NULL,
  prato text NOT NULL,
  preco numeric NOT NULL,
  criado_por uuid,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT menus_pkey PRIMARY KEY (id),
  CONSTRAINT menus_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.cantina(id)
);
CREATE TABLE public.reservas (
  aluno_id uuid NOT NULL,
  menu_id uuid NOT NULL,
  tipo text NOT NULL,
  data date NOT NULL,
  preco numeric NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  cancelada boolean DEFAULT false,
  automatico boolean DEFAULT false,
  is_dieta boolean DEFAULT false,
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT reservas_pkey PRIMARY KEY (id),
  CONSTRAINT reservas_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id),
  CONSTRAINT reservas_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.menus(id)
);
CREATE TABLE public.meses_em_divida (
  aluno_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  data date NOT NULL,
  total numeric NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT meses_em_divida_pkey PRIMARY KEY (id),
  CONSTRAINT meses_em_divida_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id)
);
CREATE TABLE public.meses_liquidados (
  aluno_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  valor_pago numeric NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  liquidado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT meses_liquidados_pkey PRIMARY KEY (id),
  CONSTRAINT meses_liquidados_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id)
);
CREATE TABLE public.relatorios_mensais (
  ano integer NOT NULL,
  mes integer NOT NULL,
  criado_por uuid,
  total_receita numeric,
  total_divida numeric,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT relatorios_mensais_pkey PRIMARY KEY (id),
  CONSTRAINT relatorios_mensais_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.cantina(id)
);
CREATE TABLE public.cancelamentos_especiais (
  aluno_id uuid NOT NULL,
  reserva_id uuid NOT NULL,
  motivo text,
  lanche_substituto text,
  cantina_responsavel uuid,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  data_cancelamento date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'pendente'::text,
  troca_por_lanche boolean DEFAULT false,
  criado_em timestamp with time zone DEFAULT now(),
  atualizado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT cancelamentos_especiais_pkey PRIMARY KEY (id),
  CONSTRAINT cancelamentos_especiais_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id),
  CONSTRAINT cancelamentos_especiais_reserva_id_fkey FOREIGN KEY (reserva_id) REFERENCES public.reservas(id),
  CONSTRAINT cancelamentos_especiais_cantina_responsavel_fkey FOREIGN KEY (cantina_responsavel) REFERENCES public.cantina(id)
);