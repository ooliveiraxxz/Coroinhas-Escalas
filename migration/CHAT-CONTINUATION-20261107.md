# Execução técnica consolidada — 07/11/2026

> Escopo: GitHub `migration/neon-20261106`; Neon staging `br-rough-hill-bcj6lzt1` e ensaio limpo `br-odd-bread-bc1jxzsh`. Supabase `dsglwwwwdtjynipauvrp`, GitHub `main` e produção Vercel permaneceram sem alterações.

## Entregas executadas e verificadas

### RLS, permissões e correções
- `024-restrict-profile-writes.sql` **aplicado nos dois branches**: conta `coroinhas_app` só tem UPDATE direto de `name,photo_url,notification_preferences,notes,approved`. `role,email,created_at,last_seen_at` não são editáveis diretamente. O RPC `developer_manage_user` continua sendo o caminho autorizado para alterações de papel, enquanto `record_site_access` continua atualizando `last_seen_at` como SECURITY DEFINER. `protect_profile` agora também recusa alteração de `created_at`.
- `025-guard-service-requests.sql` **aplicado nos dois branches**: exige coroinha aprovado, missa publicada e futura, solicitação válida de servir/substituir, vaga desmarcada pertencente à missa e ausência de escala já ativa para o solicitante.
- `026-profile-and-requests-security-regression.sql` **executado e aprovado nos dois branches**. `027-requests-rls-rollback-tests.sql` **executado e aprovado na homologação original**: aceita solicitação válida, rejeita substituição sem vaga e reverte as fixtures.
- LogQL de erros da camada PostgreSQL consultado durante a rodada; sem resultados para filtro ERROR na janela consultada (não prova ausência de problemas).

### Neon Auth e contas preservadas
- Neon Auth da homologação tem **10 identidades**, 5 credenciais de senha de teste e **0 das 4 contas originais com senha definida** na verificação anterior. Além disso, 10/10 e-mails constavam como não verificados na inspeção; portanto **NÃO exigir verificação de e-mail imediatamente em todos os logins** sem plano de ativação.
- Corrigida a whitelist de origens confiáveis: adicionados os três previews recentes e o alias estável de homologação `https://coroinhas-escalas-git-migration-neon-20261106-ooliveiraxxz.vercel.app`.
- A ativação das quatro contas reais exige ação dos titulares em fluxo de senha/OTP e comprovação de sessão; nenhum reset, convite ou senha real foi alterado ou enviado.

### Reconciliador, backups e recuperação
- Origem Supabase inventariada em leitura: 4 usuários Auth, 4 identidades, 4 sessões; 0 buckets e 0 objetos no Storage. **Isso é inventário, não backup completo do Supabase.**
- Cópia limpa Neon `br-odd-bread-bc1jxzsh` tinha 14/15 checksums iguais após importar o único evento de auditoria e reconciliar `last_seen_at`; a tabela divergente é `site_updates`.
- Confirmado na fonte: a atualização `e1570b88-6c02-4bd7-b9dc-0fcee9c26a87` não existe mais, e seu evento DELETE oficial consta no audit_log. Na cópia Neon ela ainda existe. `028-preserve-source-deleted-update.sql` criou e populou o arquivo privado `migration_private.site_update_conflict_archive` com 1 registro e referência à auditoria de exclusão. **Nenhuma linha foi removida**: decisão atual `pending_review`. A divergência física permanece até uma autorização de exclusão ou outra estratégia aprovada.
- Backup Neon isolado `br-jolly-block-bcbzq63o` criado a partir da cópia limpa; branch de recuperação `br-solitary-art-bc6ez2ns` criada a partir desse backup e validada **15/15 tabelas com hashes idênticos** e **252/252 linhas**, quatro perfis, quatro vínculos Neon, cinco identidades de Auth e 33 políticas.
- O API Neon recusou snapshots de branches filhas (`not allowed to snapshot non-root branch`); foi utilizado backup/restauração via branches Neon. Isso não prova restauração completa de Supabase Auth/configurações.
- O sincronizador com dois endereços diretos ainda não pôde ser executado porque a credencial read-only da origem não está disponível nesse executor. Foi feita conciliação parcial via conectores SQL, com origem somente leitura.

### Worker push
- `migration/sql/020..022` e o worker Node/Vercel já estavam implementados. O runtime segue **desativado** e o papel `coroinhas_push_worker` segue `NOLOGIN`.
- A nova regressão `tests/neon-push-route.test.ts` garante que não há envio se preview ou produção sem cutover autorizado.
- `migration/environment.example` documenta flags, URLs e secrets necessários, sem preencher valores privados e sem mudar produção.
- Cron/VAPID e entrega real dependem de configuração e destinatário de teste consentido. Não executar disparos para as inscrições copiadas.

## Portões pendentes que NÃO devem ser marcados como completos
1. Acesso dos quatro titulares originais com novo método de autenticação.
2. Testes de navegador, mobile/PWA, PDFs, fluxo completo por papel e push real consentido.
3. Reconciliação definitiva de `site_updates` e eventual atualização posterior de `audit_log/last_seen_at`.
4. Sincronizador ponta-a-ponta com duas conexões privadas, plano revisto e fonte congelada.
5. **Backup completo e restaurável do Supabase oficial (incluindo Auth/config)** e ensaio de recuperação equivalente; ainda não comprovado.
6. Aprovação expressa para corte de produção e revalidação do SHA exato.

**Estado técnico: avanço confirmado, mas NÃO 100% e NÃO apto para substituir produção.**
