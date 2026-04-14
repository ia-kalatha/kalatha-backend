-- ============================================================================
-- SEED: Dados iniciais para desenvolvimento
-- Execute APÓS as migrations 0001-0003
-- ============================================================================

-- Buckets de storage (execute no dashboard Supabase → Storage)
-- insert into storage.buckets (id, name, public) values
--   ('avatars', 'avatars', true),
--   ('shoes', 'shoes', true),
--   ('activities', 'activities', true);

-- Treinadores iniciais (mock, para popular o marketplace)
insert into public.treinadores (id, nome, codigo, email, especialidade, bio, experiencia_anos, valor_mensal, rating, verificado, patrocinado, aceita_alunos)
values
  ('00000000-0000-0000-0000-000000000001', 'Carlos Silva', 'TR-SILVA', 'carlos@treino.com', 'Maratonas', 'Campeão SP 2024, treinador há 15 anos', 15, 350, 4.9, true, true, true),
  ('00000000-0000-0000-0000-000000000002', 'Ana Costa', 'TR-ANACOSTA', 'ana@trail.com', 'Trail Running', 'Especialista em trail e ultra distância', 10, 400, 4.9, true, true, true),
  ('00000000-0000-0000-0000-000000000003', 'João Oliveira', 'TR-JOAO', 'joao@speed.com', 'Velocidade', 'Ex-atleta olímpico, PhD em fisiologia', 20, 380, 4.8, true, false, true),
  ('00000000-0000-0000-0000-000000000004', 'Juliana Ferreira', 'TR-JULIANA', 'juli@running.com', 'Corrida Feminina', 'Especialista em atletas mulheres', 8, 360, 4.9, true, true, true),
  ('00000000-0000-0000-0000-000000000005', 'Ricardo Matos', 'TR-RICARDO', 'ricardo@run.com', 'Maratonas', 'PhD Fisiologia do Exercício', 12, 340, 4.8, true, false, true),
  ('00000000-0000-0000-0000-000000000006', 'Maria Santos', 'TR-MARIA', 'maria@trail.com', 'Trail Running', 'Top 10 em provas nacionais', 7, 320, 4.7, true, false, true),
  ('00000000-0000-0000-0000-000000000007', 'Pedro Almeida', 'TR-PEDRO', 'pedro@urban.com', 'Corrida Urbana', 'Especialista em corrida de rua', 5, 280, 4.6, true, false, true),
  ('00000000-0000-0000-0000-000000000008', 'Camila Rocha', 'TR-CAMILA', 'camila@speed.com', 'Velocidade', 'Coach CBAt certificada', 6, 300, 4.5, true, false, true)
on conflict (codigo) do nothing;

-- Tribos públicas de exemplo
-- NOTA: Requer pelo menos um usuário admin. Rodar após o primeiro signup.
-- insert into public.tribos (nome, descricao, imagem, cor, admin_id, privada, meta_diaria, meta_semanal, meta_mensal)
-- values
--   ('Corredores do Cerrado', 'Grupo de corredores de Brasília', '🏃', 'from-blue-500 to-cyan-500', '<ADMIN_UUID>', false, 5, 30, 120),
--   ('Maratona SP 2026', 'Preparação coletiva para a Maratona de SP', '🏅', 'from-purple-500 to-pink-500', '<ADMIN_UUID>', false, 8, 50, 200);
