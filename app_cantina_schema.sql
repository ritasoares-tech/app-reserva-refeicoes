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

-- Criar reservas (exceto almoço automático)
create policy aluno_insert_reserva
on reservas
for insert
with check (
  auth.uid() = aluno_id
);

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
using (
  exists (select 1 from cantina c where c.id = auth.uid())
)
with check (true);

-- Acesso total à tabela reservas
create policy cantina_all_reservas
on reservas
for all
using (
  exists (select 1 from cantina c where c.id = auth.uid())
)
with check (true);

-- =====================================================
-- FUNÇÕES DE NEGÓCIO
-- =====================================================

-- -------------------------
-- Pode reservar dieta?
-- -------------------------
create or replace function pode_reservar_dieta(
  aluno uuid,
  dia date
)
returns boolean
language plpgsql
as $$
begin
  return exists (
    select 1
    from reservas
    where aluno_id = aluno
      and tipo = 'almoco'
      and data = dia
      and cancelada = true
  );
end;
$$;

-- -------------------------
-- Pode cancelar?
-- -------------------------
create or replace function pode_cancelar(
  tipo_menu text,
  data_menu date
)
returns boolean
language plpgsql
as $$
begin
  if tipo_menu = 'pequeno_almoco' then
    return now() < (data_menu + time '09:30');
  elsif tipo_menu = 'almoco' then
    return now() < (data_menu + time '09:00');
  elsif tipo_menu = 'jantar' then
    return now() < (data_menu + time '12:00');
  end if;
  return false;
end;
$$;

-- =====================================================
-- TRIGGERS
-- =====================================================

-- -------------------------
-- Validar cancelamento
-- -------------------------
create or replace function validar_cancelamento()
returns trigger
language plpgsql
as $$
begin
  if not pode_cancelar(old.tipo, old.data) then
    raise exception 'Cancelamento fora do prazo permitido';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_cancelamento on reservas;

create trigger trg_validar_cancelamento
before update on reservas
for each row
when (old.cancelada = false and new.cancelada = true)
execute function validar_cancelamento();

-- =====================================================
-- FIM DO SCHEMA
-- =====================================================
