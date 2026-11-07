# Handoff atualizado — 07/11/2026 — execução direta pelo Chat

**Ambiente de homologação:** branch GitHub `migration/neon-20261106`, Neon `br-rough-hill-bcj6lzt1`, Vercel preview. **Nenhuma modificação em `main`, produção Vercel ou Supabase.**

## Entrega técnica desta rodada

1. **Portão de cutover seguro:** `lib/auth/server.ts` permite ativar Neon na Vercel de produção somente se:
   - `NEON_MIGRATION_ENABLED=true`
   - `NEXT_PUBLIC_DATA_BACKEND=neon-migration`
   - `NEON_PRODUCTION_CUTOVER_ENABLED=true`
   - `NEON_PRODUCTION_APPROVED_COMMIT` contém SHA de 40 caracteres, igual a `VERCEL_GIT_COMMIT_SHA`.
   Sem qualquer condição, produção fica bloqueada. Testes em `tests/neon-route.test.ts`. Essas variáveis **não foram ativadas**.
2. **Push Neon — código novo:** `lib/neon/push-dispatch.ts` (motor e tratamento de falhas), `app/api/push/neon-dispatch/route.ts` (endpoint protegido por `CRON_SECRET`, só produção aprovada), `tests/neon-push-worker.test.ts` (casos de sucesso, bloqueio, retry, cancelamento, lease e limite).
3. **Push Neon — SQL 020 aplicado na homologação:** `migration/sql/020-neon-push-worker-foundation.sql` cria `push_runtime`, funções `push_eligible`, `push_claim`, `push_finish`, ajusta o gatilho `queue_push_notice` para enfileirar `pending` só quando habilitado. Cria `coroinhas_push_worker` com **NOLOGIN / NOBYPASSRLS**, com acesso só a funções específicas, sem SELECT/UPDATE direto no ledger e runtime. Nenhum envio. Preferências, banidos, aprovação, inscrição nova, data de ativação e notices com menos de 24h são conferidos.
4. **Proteções SQL comprovadas:** `migration/sql/021-push-worker-guard-tests.sql` executado com sucesso. `push_runtime.enabled=false`; `push_claim(10)` retorna 0; usuário de gateway não consegue chamar o worker; conta técnica não tem login nem permissões de tabela.
5. **Chave pública VAPID configurável:** `components/System.tsx` utiliza `NEXT_PUBLIC_VAPID_PUBLIC_KEY` com fallback à chave pública legada; ao reativar notificações com consentimento atualiza `push_subscriptions.created_at` para deixar explícito o opt-in posterior ao cutover.

## Antes de habilitar push (somente após autorização de corte)

- Provisionar senha privada e habilitar LOGIN para `coroinhas_push_worker` pela operação segura de administração, nunca versionar senha nem usar credencial do owner na Vercel.
- Configurar `NEON_PUSH_DATABASE_URL` com usuário `coroinhas_push_worker`, `sslmode=require`, banco `coroinhas`, branch e endpoint aprovados.
- Configurar `CRON_SECRET`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` e `NEXT_PUBLIC_VAPID_PUBLIC_KEY` correspondente. Garantir mesmo par VAPID dos dispositivos reativados; se mudar a chave, pedir nova inscrição de teste.
- Configurar agendamento autenticado de `GET /api/push/neon-dispatch` pela Vercel Cron ou outro agendador adequado ao plano. Sem agendamento, o código não processa a fila automaticamente.
- Somente após backup, sincronização, aceite E2E, autorização expressa e release de produção: definir `migration_private.push_runtime.activated_at` para a data efetiva e `enabled=true`, com revisão do alvo e das inscrições.
- Ativar `NEON_PUSH_DISPATCH_ENABLED=true` em produção **após** as validações. Em homologação e no Supabase, tudo permanece desligado.
- Criar inscrição opt-in em dispositivo real de teste e comprovar entrega, cancelamento, retry, restauração e dados de relatório. Mensagens/senha e destinatários reais não entram nos logs.
- Existing imported subscriptions are deliberately excluded by the activation timestamp. Users must renew opt-in after cutover; do not silently reuse subscriptions copied from the old backend.

## Bloqueios não resolvidos por engenharia estática

- Os quatro usuários originais ainda não têm senha estabelecida no Neon; comprovar ativação pelos próprios titulares sem apropriação de conta.
- Testes E2E de navegação, dispositivos móveis, PDFs, cron e entrega push real.
- Teste integral do sincronizador com conexões privadas simultâneas; operação EAI_AGAIN no executor anterior.
- Reconciliação de 99 registros adicionais de homologação, sem exclusão automática.
- Backup restaurável e ensaio de recuperação do Supabase, congelamento de escritas e validação do cutover.
- Autorização expressa para alterar `main`, Vercel de produção, Neon em operação e Supabase.

**Não declarar 100% ou desligar Supabase enquanto faltar qualquer desses portões.**

## Homologação SQL adicional

- `migration/sql/022-push-worker-transaction-tests.sql` foi executado no Neon de homologação com **sucesso**.
- O teste ativou a fila somente dentro de uma subtransação revertida, criou temporariamente perfil, inscrição e aviso fictícios; comprovou enfileiramento `pending`, reserva única, confirmação `sent` e rejeição de reenvio. Ao sair, verificou que todas as fixtures e o estado habilitado foram revertidos.
- Isto confirma o processamento SQL transacional do worker; **não é uma comprovação de entrega web push em dispositivo**.
