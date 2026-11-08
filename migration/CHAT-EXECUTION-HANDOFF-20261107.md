# Entrega atualizada — continuidade técnica pelo Chat — 07/11/2026

**Escopo:** somente GitHub `migration/neon-20261106`, Neon staging `br-rough-hill-bcj6lzt1`, Neon clean rehearsal `br-odd-bread-bc1jxzsh` e preview Vercel. A origem Supabase `dsglwwwwdtjynipauvrp` foi acessada somente em leitura. Nenhuma alteração em `main`, domínio ou banco de produção.

## O que foi feito nesta execução

1. **Reconciliação lógica 15/15:** a atualização `e1570b88-6c02-4bd7-b9dc-0fcee9c26a87` consta na auditoria da origem como excluída (evento ID 168), não existe mais em `public.site_updates` no Supabase, e está preservada no arquivo privado `migration_private.site_update_conflict_archive` da branch de ensaio. O SQL read-only `031-readonly-archived-delete-reconciliation.sql` confirmou `correct_branch=true`, `archived_deletion_verified=true`, 7 atualizações físicas e 6 ativas; o checksum lógico `site_updates` coincide com a origem. Ao comparar 15 tabelas com a origem e excluir **somente** essa atualização historicamente removida, foram 15/15 checksums iguais e 251 registros lógicos em cada banco. O dado físico permanece preservado. Isso não é sincronização atômica final nem autoriza remoções.
2. **Sync auditável:** `migration/sync.mjs` agora verifica em leitura a origem da exclusão pelo audit_log da fonte, ausência do registro ativo, snapshot arquivado idêntico e audit_log do destino. Expõe separadamente `dataChecksMatch` (igualdade física, ainda **false**), `logicalDataChecksMatch` (com tombstone auditada, true) e `requiresConflictReview` (true). O modo `--apply` **NÃO** foi liberado: continua recusando registros exclusivos no destino. Teste automatizado em `tests/neon-sync.test.ts`.
3. **Bug de API:** `app/api/migration/data/[...path]/route.ts` recusa Content-Length excessivo ou inválido antes de autenticação/leitura do corpo; cobertura em `tests/neon-route.test.ts`.
4. **RLS transacional:** `032-negative-profile-access-tests.sql` foi executado nas duas branches e passou; protege contra promoção própria, alteração do e-mail e exclusão de perfil, preservando edição legítima do nome. Todas as fixtures foram revertidas.
5. **Neon Auth:** `033-original-auth-activation-check.sql` executado: 4/4 perfis aprovados, mapeados, com emails iguais e IDs únicos; 0/4 senhas ativas e 0/4 emails verificados. Nenhuma senha, token, e-mail pessoal nem UUID individual foi incluído na saída. A ativação individual via OTP/recuperação ainda depende dos titulares.
6. **Vercel:** foram confirmadas as cinco configurações específicas de preview necessárias à integração (sem consultar valores secretos): `NEXT_PUBLIC_DATA_BACKEND`, `NEON_MIGRATION_ENABLED`, `NEON_AUTH_BASE_URL`, `NEON_AUTH_COOKIE_SECRET`, `NEON_MIGRATION_DATABASE_URL`. O worker push permanece desligado e o role `coroinhas_push_worker` permanece `NOLOGIN`.
7. **CI:** GitHub Actions run `42428722731` validou a revisão `a3b47716731976cf71518524aac509590f13da83`: **52 testes aprovados, 0 falhas, TypeScript e build verdes**.

## Backup e restauração — delimitação das evidências

- O teste anterior de backup de branch Neon `br-jolly-block-bcbzq63o` para clone de recuperação `br-solitary-art-bc6ez2ns` comprovou **15/15 hashes e 252/252 linhas** naquele snapshot da cópia limpa.
- Supabase oficial tem 4 identidades Auth, 4 usuários Auth, 4 sessões, 0 buckets Storage e 0 objetos Storage, conforme inventário somente leitura.
- **Não existe evidência de exportação e restauração INTEGRAL do Supabase Auth/config/storage/políticas**; a ferramenta Supabase conectada dispõe de SQL e inventário, não da operação de backup lógico/restauração completa da origem. Não reportar esta condição como resolvida.

## Bloqueios restantes, sem maquiagem

- Ativação e login real de 4 titulares antigos; sem definir suas senhas arbitrariamente.
- Testes no browser, permissões/funcionalidades por papel, iPhone/PWA, PDFs e entrega consentida de notificações push.
- Credenciais privadas de origem PostgreSQL com acesso read-only para executar `migration/sync.mjs` ponta a ponta. Comparações **via conectores SQL** foram concluídas e 15/15 hashes lógicos coincidem no instante da consulta, mas não equivalem à execução de sincronizador TCP.
- Backup/restauração integral da origem com acesso administrativo apropriado.
- Revisão e aprovação expressa da decisão sobre o histórico excluído e corte com congelamento de escritas.
- Push cron, VAPID e contas de serviço só podem ser ativados após validação e autorização final. Nenhum push real enviado.

**Decisão: produção permanece no Supabase. A revisão de homologação não substitui validação E2E nem comprovação completa de backup da origem.**
