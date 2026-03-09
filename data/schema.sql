-- =====================================================
-- APP CANTINA — ESQUEMA COMPLETO
-- Autor: ---
-- Base de dados: Supabase (PostgreSQL)
-- =====================================================

-- =========================
-- EXTENSÕES
-- =========================
create extension if not exists "pgcrypto";

-- =========================
-- TABELA: alunos
-- =========================
create table if not exists alunos (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text unique not null,
  criado_em timestamptz default now()
);

-- =========================
-- TABELA: cantina
-- =========================
create table if not exists cantina (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text unique not null,
  criado_em timestamptz default now()
);

-- =========================
-- TABELA: menus
-- =========================
create table if not exists menus (
  id uuid primary key default gen_random_uuid(),
  data date not null,
  tipo text not null
    check (tipo in ('pequeno_almoco','almoco','jantar','dieta')),
  prato text,
  preco numeric not null check (preco >= 0),
  criado_em timestamptz default now(),

  unique (data, tipo)
);

-- =========================
-- TABELA: reservas
-- =========================
create table if not exists reservas (
  id uuid primary key default gen_random_uuid(),
  aluno_id uuid not null references alunos(id) on delete cascade,
  menu_id uuid not null references menus(id) on delete cascade,
  tipo text not null,
  data date not null,
  preco numeric not null,
  cancelada boolean default false,
  is_dieta boolean default false,
  criado_em timestamptz default now(),

  unique (aluno_id, menu_id)
);

-- =========================
-- ÍNDICES
-- =========================
create index if not exists idx_reservas_aluno on reservas(aluno_id);
create index if not exists idx_reservas_data on reservas(data);
create index if not exists idx_menus_data on menus(data);

-- =========================
-- ATIVAR RLS
-- =========================
alter table alunos enable row level security;
alter table cantina enable row level security;
alter table menus enable row level security;
alter table reservas enable row level security;

-- =====================================================
-- POLICIES RLS
-- =====================================================

-- -------------------------
-- ALUNO
-- -------------------------

-- Ver o próprio perfil
create policy aluno_select_self
on alunos
for select
using (auth.uid() = id);

-- Ver menus disponíveis
create policy aluno_select_menus
on menus
for select
using (true);

-- Ver apenas as suas reservas
create policy aluno_select_reservas
on reservas
for select
using (auth.uid() = aluno_id);

-- Criar reservas
create policy aluno_insert_reserva
on reservas
for insert
with check (auth.uid() = aluno_id);

-- Cancelar a própria reserva
create policy aluno_cancelar_reserva
on reservas
for update
using (auth.uid() = aluno_id)
with check (auth.uid() = aluno_id);

-- -------------------------
-- CANTINA
-- -------------------------

-- Acesso total à tabela menus
create policy cantina_all_menus
on menus
for all
using (exists (select 1 from cantina c where c.id = auth.uid()))
with check (true);

-- Acesso total à tabela reservas
create policy cantina_all_reservas
on reservas
for all
using (exists (select 1 from cantina c where c.id = auth.uid()))
with check (true);

-- =====================================================
-- FUNÇÕES DE NEGÓCIO
-- =====================================================

create or replace function aluno_tem_divida(p_aluno_id uuid)
returns boolean
language plpgsql
as $$
begin
  return exists (
    select 1 from reservas
    where aluno_id = p_aluno_id
      and cancelada = false
  );
end;
$$;

create or replace function relatorio_mensal(p_ano int, p_mes int)
returns table(nome text, total_refeicoes int, total_valor numeric)
language plpgsql
as $$
begin
  return query
  select 
    a.nome,
    count(r.id)::int,
    sum(r.preco)::numeric
  from reservas r
  join alunos a on r.aluno_id = a.id
  where extract(year from r.data) = p_ano
    and extract(month from r.data) = p_mes
    and r.cancelada = false
  group by a.id, a.nome
  order by a.nome;
end;
$$;

-- =====================================================
-- FIM DO SCHEMA
-- =====================================================

-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.alunos (
  id uuid NOT NULL,
  nome text NOT NULL,
  email text NOT NULL UNIQUE,
  criado_em timestamp with time zone DEFAULT now(),
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
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  data date NOT NULL,
  tipo text NOT NULL,
  prato text NOT NULL,
  preco numeric NOT NULL,
  criado_por uuid,
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT menus_pkey PRIMARY KEY (id),
  CONSTRAINT menus_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.cantina(id)
);
CREATE TABLE public.meses_em_divida (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  aluno_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  data date NOT NULL,
  total numeric NOT NULL,
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT meses_em_divida_pkey PRIMARY KEY (id),
  CONSTRAINT meses_em_divida_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id)
);
CREATE TABLE public.meses_liquidados (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  aluno_id uuid NOT NULL,
  ano integer NOT NULL,
  mes integer NOT NULL,
  valor_pago numeric NOT NULL,
  liquidado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT meses_liquidados_pkey PRIMARY KEY (id),
  CONSTRAINT meses_liquidados_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id)
);
CREATE TABLE public.relatorios_mensais (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ano integer NOT NULL,
  mes integer NOT NULL,
  criado_em timestamp with time zone DEFAULT now(),
  criado_por uuid,
  total_receita numeric,
  total_divida numeric,
  CONSTRAINT relatorios_mensais_pkey PRIMARY KEY (id),
  CONSTRAINT relatorios_mensais_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.cantina(id)
);
CREATE TABLE public.reservas (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  aluno_id uuid NOT NULL,
  menu_id uuid NOT NULL,
  tipo text NOT NULL,
  data date NOT NULL,
  preco numeric NOT NULL,
  cancelada boolean DEFAULT false,
  automatico boolean DEFAULT false,
  is_dieta boolean DEFAULT false,
  criado_em timestamp with time zone DEFAULT now(),
  CONSTRAINT reservas_pkey PRIMARY KEY (id),
  CONSTRAINT reservas_aluno_id_fkey FOREIGN KEY (aluno_id) REFERENCES public.alunos(id),
  CONSTRAINT reservas_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.menus(id)
);
