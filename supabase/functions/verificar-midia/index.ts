/**
 * Edge Function: verificar-midia
 *
 * Valida foto/vídeo enviado pelo usuário no fluxo de verificação de perfil.
 *
 * Entrada (POST JSON):
 *   {
 *     "userId":   "uuid",
 *     "slotId":   1 | 2 | 3,
 *     "mediaType": "photo" | "video",
 *     "mediaUrl": "https://<supabase-storage>/.../arquivo.jpg"
 *   }
 *
 * Saída (JSON):
 *   {
 *     "approved":   boolean,
 *     "confidence": number (0..1),
 *     "reasons":    string[],    // motivos se rejeitado
 *     "slotId":     number,
 *     "verifiedAt": "ISO-8601 timestamp"
 *   }
 *
 * Regras que a validação precisa cobrir (ver landing/CLAUDE.md):
 *   ✓ Rosto visível
 *   ✓ Cenário esportivo (parque, pista, academia)
 *   ✓ Vestimenta de corrida
 *   ✗ Sem nudez / conteúdo inapropriado
 *   ✗ Sem foto gerada por IA
 *
 * Integração pendente (TODO):
 *   Plugar provedor de Vision AI em `analyzeMedia()`. Candidatos:
 *     - Claude Vision (Anthropic) — `claude-opus-4-7` c/ imagem base64
 *     - OpenAI Vision — `gpt-4o`
 *     - Google Cloud Vision — labelDetection + safeSearchDetection
 *     - AWS Rekognition — DetectModerationLabels + DetectLabels
 *
 * Secrets esperadas no ambiente Supabase (setar via dashboard ou CLI):
 *   - ANTHROPIC_API_KEY   (ou OPENAI_API_KEY, etc.)
 *   - SUPABASE_URL
 *   - SUPABASE_SERVICE_ROLE_KEY
 */

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2.49.8';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Max-Age': '86400',
};

interface VerifyRequest {
  userId: string;
  slotId: 1 | 2 | 3;
  mediaType: 'photo' | 'video';
  mediaUrl: string;
}

interface VerifyResponse {
  approved: boolean;
  confidence: number;
  reasons: string[];
  slotId: number;
  verifiedAt: string;
}

/**
 * Análise do conteúdo da mídia.
 *
 * Implementação atual: MOCK — aprova 80% dos uploads com confidence 0.85.
 * Substituir pelo provedor de Vision AI de escolha antes de produção.
 */
async function analyzeMedia(mediaUrl: string, mediaType: 'photo' | 'video'): Promise<{
  approved: boolean;
  confidence: number;
  reasons: string[];
}> {
  // ────────────── TODO: substituir por vision real ──────────────
  // Exemplo com Claude Vision:
  //
  //   const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  //   const imageData = await fetch(mediaUrl).then(r => r.arrayBuffer());
  //   const base64 = btoa(String.fromCharCode(...new Uint8Array(imageData)));
  //   const response = await fetch('https://api.anthropic.com/v1/messages', {
  //     method: 'POST',
  //     headers: {
  //       'x-api-key': apiKey!,
  //       'anthropic-version': '2023-06-01',
  //       'content-type': 'application/json',
  //     },
  //     body: JSON.stringify({
  //       model: 'claude-opus-4-7',
  //       max_tokens: 512,
  //       messages: [{
  //         role: 'user',
  //         content: [
  //           { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: base64 } },
  //           { type: 'text', text: `Analise esta imagem e responda em JSON:
  //             { "pessoa_visivel": bool, "cenario_esportivo": bool, "vestimenta_corrida": bool,
  //               "conteudo_inapropriado": bool, "parece_gerado_por_ia": bool, "confianca": 0..1 }` },
  //         ],
  //       }],
  //     }),
  //   });
  //   const parsed = JSON.parse(/* extract JSON from message */);
  //   const approved = parsed.pessoa_visivel && parsed.cenario_esportivo &&
  //                    !parsed.conteudo_inapropriado && !parsed.parece_gerado_por_ia;
  //   const reasons: string[] = [];
  //   if (!parsed.pessoa_visivel) reasons.push('Rosto não visível');
  //   if (!parsed.cenario_esportivo) reasons.push('Cenário não parece esportivo');
  //   if (parsed.conteudo_inapropriado) reasons.push('Conteúdo inapropriado detectado');
  //   if (parsed.parece_gerado_por_ia) reasons.push('Imagem parece gerada por IA');
  //   return { approved, confidence: parsed.confianca, reasons };
  // ─────────────────────────────────────────────────────────────

  // MOCK: por enquanto aprova 80% dos uploads
  await new Promise((r) => setTimeout(r, 600));
  const random = Math.random();
  if (random < 0.8) {
    return { approved: true, confidence: 0.85, reasons: [] };
  }
  const reasons = ['Rosto não detectado', 'Cenário indefinido'];
  return { approved: false, confidence: 0.72, reasons };
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Método não permitido' }), {
      status: 405,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    });
  }

  let body: VerifyRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'JSON inválido' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    });
  }

  const { userId, slotId, mediaType, mediaUrl } = body;
  if (!userId || !slotId || !mediaType || !mediaUrl) {
    return new Response(
      JSON.stringify({
        error: 'Campos obrigatórios: userId, slotId, mediaType, mediaUrl',
      }),
      { status: 400, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }
  if (slotId < 1 || slotId > 3) {
    return new Response(
      JSON.stringify({ error: 'slotId deve ser 1, 2 ou 3' }),
      { status: 400, headers: { ...CORS_HEADERS, 'content-type': 'application/json' } },
    );
  }

  // Análise
  const analysis = await analyzeMedia(mediaUrl, mediaType);

  const response: VerifyResponse = {
    approved: analysis.approved,
    confidence: analysis.confidence,
    reasons: analysis.reasons,
    slotId,
    verifiedAt: new Date().toISOString(),
  };

  // Grava trilha de auditoria (não bloqueia a resposta se falhar)
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (supabaseUrl && serviceRoleKey) {
      const admin = createClient(supabaseUrl, serviceRoleKey);
      await admin.from('audit_log').insert({
        usuario_id: userId,
        acao: 'verificar_midia',
        entidade: 'profile',
        detalhes: {
          slotId,
          mediaType,
          approved: analysis.approved,
          confidence: analysis.confidence,
          reasons: analysis.reasons,
        },
      });
    }
  } catch (err) {
    console.error('audit_log falhou (não bloqueante):', err);
  }

  return new Response(JSON.stringify(response), {
    status: 200,
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  });
});
