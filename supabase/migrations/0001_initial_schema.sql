-- ============================================================================
-- MIGRATION 0001: Initial Schema
-- Vamos Correr v4.0.0 — Schema completo
-- ============================================================================

-- Extensões necessárias
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ============================================================================
-- 1. PROFILES - Perfil do usuário
-- ============================================================================
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  nome text not null,
  email text not null unique,
  telefone text,
  cpf text unique,
  avatar_url text,
  cidade text,
  estado text,
  bio text,
  peso numeric(5,2),
  altura numeric(5,2),
  idade integer,
  objetivo text,
  genero text check (genero in ('M','F','O','N')),
  nivel text default 'iniciante' check (nivel in ('iniciante','intermediario','avancado')),
  plano text default 'free' check (plano in ('free','pro','elite')),
  plano_expira_em timestamptz,
  run_coins integer default 500,
  total_km numeric(10,2) default 0,
  total_corridas integer default 0,
  streak_atual integer default 0,
  streak_maximo integer default 0,
  xp integer default 0,
  verificado boolean default false,
  tipo_verificacao text,
  admin boolean default false,
  banido boolean default false,
  ultimo_acesso timestamptz default now(),
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

create index if not exists profiles_plano_idx on public.profiles(plano);
create index if not exists profiles_nivel_idx on public.profiles(nivel);
create index if not exists profiles_total_km_idx on public.profiles(total_km desc);

-- ============================================================================
-- 2. CORRIDAS - Atividades de corrida
-- ============================================================================
create table if not exists public.corridas (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  tipo text default 'corrida' check (tipo in ('corrida','caminhada','trilha','esteira','longao','intervalado','regenerativo')),
  distancia_km numeric(10,3) not null check (distancia_km > 0),
  duracao_segundos integer not null check (duracao_segundos > 0),
  pace_medio text,
  velocidade_media numeric(5,2),
  calorias integer,
  elevacao_ganha_m numeric(8,2),
  elevacao_perdida_m numeric(8,2),
  percurso jsonb,
  splits jsonb,
  clima text,
  temperatura_c numeric(4,1),
  tenis_id uuid,
  mascote_id uuid,
  notas text,
  visibilidade text default 'publico' check (visibilidade in ('publico','amigos','privado')),
  likes_count integer default 0,
  comentarios_count integer default 0,
  criado_em timestamptz default now()
);

create index if not exists corridas_usuario_id_idx on public.corridas(usuario_id);
create index if not exists corridas_criado_em_idx on public.corridas(criado_em desc);
create index if not exists corridas_tipo_idx on public.corridas(tipo);
create index if not exists corridas_visibilidade_idx on public.corridas(visibilidade);

-- ============================================================================
-- 3. TENIS - Calçados do usuário
-- ============================================================================
create table if not exists public.tenis (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  marca text not null,
  modelo text not null,
  cor text,
  data_compra date,
  km_inicial numeric(10,2) default 0,
  km_atual numeric(10,2) default 0,
  km_alerta numeric(10,2) default 800,
  ativo boolean default false,
  foto_url text,
  criado_em timestamptz default now()
);

create index if not exists tenis_usuario_id_idx on public.tenis(usuario_id);

-- ============================================================================
-- 4. MASCOTES - Pets evolutivos
-- ============================================================================
create table if not exists public.mascotes (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  tipo text not null,
  nome text not null,
  nivel integer default 1,
  xp integer default 0,
  xp_para_proximo integer default 100,
  estagio integer default 1,
  ativo boolean default false,
  corridas_completas integer default 0,
  criado_em timestamptz default now()
);

create index if not exists mascotes_usuario_id_idx on public.mascotes(usuario_id);

-- ============================================================================
-- 5. CONQUISTAS - Achievements desbloqueados
-- ============================================================================
create table if not exists public.conquistas (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  conquista_id text not null,
  categoria text,
  xp_ganho integer default 0,
  desbloqueada_em timestamptz default now(),
  unique(usuario_id, conquista_id)
);

create index if not exists conquistas_usuario_id_idx on public.conquistas(usuario_id);

-- ============================================================================
-- 6. TRIBOS - Comunidades
-- ============================================================================
create table if not exists public.tribos (
  id uuid default gen_random_uuid() primary key,
  nome text not null,
  descricao text,
  imagem text,
  cor text,
  admin_id uuid references public.profiles on delete cascade not null,
  membros integer default 1,
  nivel integer default 1,
  privada boolean default false,
  regras text[],
  meta_diaria numeric(6,2) default 5,
  meta_semanal numeric(6,2) default 30,
  meta_mensal numeric(6,2) default 120,
  criado_em timestamptz default now()
);

create index if not exists tribos_admin_id_idx on public.tribos(admin_id);
create index if not exists tribos_privada_idx on public.tribos(privada);

-- ============================================================================
-- 7. TRIBO_MEMBROS - Relação many-to-many
-- ============================================================================
create table if not exists public.tribo_membros (
  tribo_id uuid references public.tribos on delete cascade not null,
  usuario_id uuid references public.profiles on delete cascade not null,
  papel text default 'membro' check (papel in ('admin','moderador','membro')),
  km_contribuidos numeric(10,2) default 0,
  ingresso_em timestamptz default now(),
  primary key (tribo_id, usuario_id)
);

create index if not exists tribo_membros_usuario_id_idx on public.tribo_membros(usuario_id);

-- ============================================================================
-- 8. DESAFIOS - 1v1 com apostas
-- ============================================================================
create table if not exists public.desafios (
  id uuid default gen_random_uuid() primary key,
  criador_id uuid references public.profiles on delete cascade not null,
  desafiado_id uuid references public.profiles on delete cascade not null,
  tipo text not null check (tipo in ('distancia','tempo','pace')),
  meta numeric(10,2) not null,
  aposta integer default 0,
  prazo timestamptz not null,
  status text default 'pendente' check (status in ('pendente','aceito','recusado','finalizado','cancelado')),
  vencedor_id uuid references public.profiles,
  criador_progresso numeric(10,2) default 0,
  desafiado_progresso numeric(10,2) default 0,
  criado_em timestamptz default now(),
  finalizado_em timestamptz
);

create index if not exists desafios_criador_idx on public.desafios(criador_id);
create index if not exists desafios_desafiado_idx on public.desafios(desafiado_id);
create index if not exists desafios_status_idx on public.desafios(status);

-- ============================================================================
-- 9. COMPETICOES - Eventos de corrida
-- ============================================================================
create table if not exists public.competicoes (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  nome text not null,
  data_evento date not null,
  local text,
  distancia_km numeric(10,2),
  tipo text,
  objetivo text,
  notas text,
  status text default 'planejado' check (status in ('planejado','inscrito','concluido','cancelado')),
  tempo_final text,
  posicao_geral integer,
  posicao_categoria integer,
  participantes_total integer,
  corrida_id uuid references public.corridas on delete set null,
  criado_em timestamptz default now()
);

create index if not exists competicoes_usuario_id_idx on public.competicoes(usuario_id);
create index if not exists competicoes_status_idx on public.competicoes(status);

-- ============================================================================
-- 10. TRANSACOES_RUNCOINS - Histórico de moedas
-- ============================================================================
create table if not exists public.transacoes_runcoins (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  tipo text not null check (tipo in ('credit','debit')),
  valor integer not null,
  motivo text not null,
  saldo_apos integer not null,
  referencia_id uuid,
  referencia_tipo text,
  criado_em timestamptz default now()
);

create index if not exists transacoes_usuario_idx on public.transacoes_runcoins(usuario_id, criado_em desc);

-- ============================================================================
-- 11. TREINADORES - Perfis de treinadores
-- ============================================================================
create table if not exists public.treinadores (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade unique,
  nome text not null,
  codigo text unique not null,
  email text not null,
  telefone text,
  cref text,
  especialidade text not null,
  bio text,
  foto_url text,
  certificacoes text[],
  experiencia_anos integer,
  valor_mensal numeric(8,2),
  rating numeric(2,1) default 5.0,
  total_alunos integer default 0,
  aceita_alunos boolean default true,
  verificado boolean default false,
  patrocinado boolean default false,
  criado_em timestamptz default now()
);

create index if not exists treinadores_codigo_idx on public.treinadores(codigo);
create index if not exists treinadores_especialidade_idx on public.treinadores(especialidade);

-- ============================================================================
-- 12. CONTRATOS - Usuário x Treinador
-- ============================================================================
create table if not exists public.contratos (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  treinador_id uuid references public.treinadores on delete cascade not null,
  data_inicio date not null,
  duracao_semanas integer not null,
  valor_mensal numeric(8,2) not null,
  status text default 'pendente' check (status in ('pendente','ativo','cancelado','finalizado')),
  termos text,
  criado_em timestamptz default now(),
  finalizado_em timestamptz,
  unique(usuario_id, treinador_id)
);

-- ============================================================================
-- 13. METAS - Objetivos do usuário
-- ============================================================================
create table if not exists public.metas (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  nome text not null,
  tipo text not null check (tipo in ('distancia','tempo','frequencia','pace','peso')),
  valor_alvo numeric(10,2) not null,
  valor_atual numeric(10,2) default 0,
  prazo date,
  status text default 'ativo' check (status in ('ativo','concluido','abandonado')),
  premium boolean default false,
  criado_em timestamptz default now(),
  concluido_em timestamptz
);

create index if not exists metas_usuario_idx on public.metas(usuario_id, status);

-- ============================================================================
-- 14. NOTIFICACOES - Central de notificações
-- ============================================================================
create table if not exists public.notificacoes (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  tipo text not null,
  titulo text not null,
  mensagem text not null,
  lida boolean default false,
  dados jsonb,
  criado_em timestamptz default now()
);

create index if not exists notificacoes_usuario_idx on public.notificacoes(usuario_id, lida, criado_em desc);

-- ============================================================================
-- 15. PUSH_TOKENS - Registro de dispositivos
-- ============================================================================
create table if not exists public.push_tokens (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete cascade not null,
  token text not null unique,
  plataforma text check (plataforma in ('ios','android','web')),
  device_info jsonb,
  ativo boolean default true,
  ultimo_uso timestamptz default now(),
  criado_em timestamptz default now()
);

-- ============================================================================
-- 16. AUDIT_LOG - Log de auditoria (LGPD)
-- ============================================================================
create table if not exists public.audit_log (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid references public.profiles on delete set null,
  acao text not null,
  recurso text,
  recurso_id text,
  dados_antes jsonb,
  dados_depois jsonb,
  ip_address text,
  user_agent text,
  criado_em timestamptz default now()
);

create index if not exists audit_log_usuario_idx on public.audit_log(usuario_id, criado_em desc);
create index if not exists audit_log_acao_idx on public.audit_log(acao);
