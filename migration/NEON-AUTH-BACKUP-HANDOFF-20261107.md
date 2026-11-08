# HANDOFF — execução complementar 07/11/2026 — autenticação e recuperação

**Tudo nesta atualização foi limitado à homologação e aos branches isolados do Neon.** Nenhum deploy de produção, troca de domínio, exclusão de registros oficiais ou escrita na origem Supabase.

## Implementação real
- **Neon Auth da branch** `br-rough-hill-bcj6lzt1`: `allow_localhost=false`; lista existente de 11 origens confiáveis preservada. Configuração conferida após atualização.
- **Login por link mágico** do Neon Auth ativado na branch: `enabled=true`, validade de **10 minutos**, `disable_sign_up=true`. Apenas contas Neon Auth existentes conseguem acessar por este método. Não houve disparo de e-mails a terceiros; o próprio usuário solicita o link.
- **Frontend:** `components/NeonLogin.tsx` ganhou botão `Entrar com link enviado por e-mail` para permitir que as quatro contas já importadas provem o controle do próprio endereço de e-mail, sem inventar/assumir senhas. A correspondência 4/4 de perfis mapeados permanece preservada, mas **cliques e sessão real dependem dos titulares**. O botão envia a solicitação somente quando acionado.
- **Bateria de integridade:** `migration/sql/034-referential-integrity-gates.sql` executada com sucesso nas branches de homologação e ensaio limpo. Não há vínculos órfãos de escala, usuário, requisição, push, notificação ou identidade; não há substituição apontando para missa diferente.
- **Permissões do gateway:** `coroinhas_gateway` é LOGIN sem SUPERUSER/BYPASSRLS e membro de `coroinhas_app`; `coroinhas_app` é NOLOGIN; `coroinhas_push_worker` continua NOLOGIN. O gateway não tem SELECT direto em `neon_auth.user`, `profiles` ou `audit_log`, e o worker não tem SELECT/UPDATE direto em suas tabelas privadas (acessa apenas funções autorizadas).
- **Config Vercel Preview:** `NEXT_PUBLIC_DATA_BACKEND`, `NEON_MIGRATION_ENABLED` e `NEON_AUTH_BASE_URL` conferidos. Vercel retorna os valores de `NEON_AUTH_COOKIE_SECRET` e `NEON_MIGRATION_DATABASE_URL` vazios por serem sensíveis mesmo com `decrypt=true`; portanto **não afirmar que as credenciais privadas foram verificadas**. Sua presença nominal foi confirmada.
- **Push:** segue com `migration_private.push_runtime.enabled=false`, nenhuma tentativa de envio registrada; não disparar sem destinatário de teste consentido e validação de VAPID.

## Backup/recovery desta execução — verificação
- Origem de ensaio: `br-odd-bread-bc1jxzsh`.
- Backup atualizado por branching do Neon: `br-lucky-pine-bcf4h6hn` — `coroinhas-verified-data-backup-20261107`.
- Restauração isolada por nova branch: `br-plain-hill-bcukew31` — `coroinhas-backup-restore-proof-20261107`.
- Checksum completo: **15/15** tabelas públicas e **252/252 linhas** entre origem, backup e restauração; mesmos 8 mapeamentos de identidade, 5 Neon Auth users da cópia, 33 políticas, 15 tabelas com RLS, 1 exclusão histórica arquivada e hash das funções do esquema `migration_private`.
- Trata-se de backup **Neon**, não de exportação completa/restauração do Supabase Auth/config/Storage. Snapshot oficial da origem e restore completo ainda dependem de acesso de backup que não foi fornecido ao executor.

## Reconciliação e limites
- O ensaio limpo tem 252 linhas físicas, incluindo 1 atualização já excluída na origem e preservada como conflito no arquivo privado. O inventário **lógico de 251 linhas e 15/15 checksums** coincide com o Supabase na comparação read-only anterior. Não excluir registro sem autorização e não declarar sync final atômico.
- A execução direta `node migration/sync.mjs` com conexão read-only do Supabase continua impossibilitada pela ausência dessa credencial no executor. Os testes via SQL dos conectores foram realizados e o script preserva o bloqueio de gravação para registro exclusivo.
- Titulares dos quatro perfis ainda precisam usar o link de acesso na homologação e confirmar os perfis. Depois, é possível configurar senha com código OTP por iniciativa do próprio titular.

## Para a validação final
1. Login real por link nas quatro contas antigas; conferir os UUIDs e papéis, logout, banimento, sessão e aprovação.
2. PDFs, escalas e permissões em navegador real; teste push apenas para dispositivo autorizado.
3. Snapshot completo/restauração de Supabase com acesso de backup apropriado, sincronização definitiva após congelar escritas e autorização do cutover.

**Não transformar este handoff em justificativa para publicar `main` ou desligar o Supabase.**

## Teste RLS por perfil — execução complementar

- `migration/sql/035-role-matrix-rollback-tests.sql` criado e executado com sucesso nas branches `br-rough-hill-bcj6lzt1` e `br-odd-bread-bc1jxzsh`.
- Testes efetivos com `SET LOCAL ROLE coroinhas_app`: pai responsável **não** solicita servir; coroinha ainda não aprovado **não** solicita servir; coroinha aprovado solicita servir em missa publicada e futura; missa não publicada é bloqueada; e-mail de outro perfil fica mascarado em `profile_directory`. Dados fictícios totalmente revertidos.
- Este teste complementa o `034` (integridade referencial) e as provas anteriores de privilégio de perfil; não é teste de navegador.
