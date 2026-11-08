# CHECKPOINT CHAT → WORK — 07/11/2026 (nova verificação direta)

## Escopo e segurança
- Repositório: ooliveiraxxz/Coroinhas-Escalas.
- Branch de homologação: migration/neon-20261106, HEAD observado antes deste documento: 39b8a8973ab1f351ed94b122da85f8a7214a7e42.
- Produção: main. NÃO promover nem alterar domínios/segredos de produção antes de gates e autorização específicos.
- Supabase fonte: dsglwwwwdtjynipauvrp, somente leitura nesta execução.
- Neon staging: noisy-hill-07078359 / br-rough-hill-bcj6lzt1 / database coroinhas.
- Neon clean rehearsal: br-odd-bread-bc1jxzsh.

## Verificação efetivamente executada nesta conversa
1. GitHub: branch existente; comparação com main: 117 commits à frente, 0 atrás; head 39b8a89 antes da criação do documento.
2. Supabase SQL live, sem escrita: 15 tabelas public; profiles 4, audit_log 164, site_updates 6, notifications 14.
3. Neon staging SQL live, sem escrita: 16 tabelas public, sendo profile_directory adicional e intencional; profiles 8, audit_log 223, site_updates 7, notifications 41. Portanto staging está com fixtures/deltas e NÃO é cópia física idêntica da origem; não limpar sem revisão e backup.
4. Neon clean rehearsal SQL live: profiles 4, audit_log 164, site_updates 7, notifications 14; pg_policies public=33. Divergência física site_updates preserva remoção histórica arquivada; consultar CHAT-EXECUTION-HANDOFF e SQL 031.
5. Neon staging security gate SQL executado: on_staging=true; 33 policies public; 15 tabelas RLS; 4 perfis originais; 4 vinculados; 0 senhas credential definidas para originais; push enabled=false; push attempts=0; assignments órfãos=0; identity maps órfãos=0; push worker rolcanlogin=false; gateway rolbypassrls=false.
6. Neon Auth Better Auth gerenciado ativo. Revisar AUTH-HASH-COMPATIBILITY-20261107: não é seguro importar bcrypt Supabase diretamente para scrypt Better Auth. Magic link de ativação é o fluxo implementado e ainda exige teste real dos titulares.
7. Vercel: projeto prj_lgQXYScz7B7VS44nV4KPblczb0lB; preview READY observado para commit anterior 4c2830b; variáveis de preview por branch presentes (NAMES somente): NEXT_PUBLIC_DATA_BACKEND, NEON_MIGRATION_ENABLED, NEON_AUTH_BASE_URL, NEON_AUTH_COOKIE_SECRET, NEON_MIGRATION_DATABASE_URL. Último commit de documentação pode não possuir deployment próprio.
8. Nenhum envio de push, reset de senha, exclusão de usuário, mudança de configuração de produção, alteração SQL ou sync foi executado nesta verificação. Não tratar leitura como teste E2E.

## Execução restante no Work — exigências para concluir de verdade
A. Inspecionar HEAD mais recente; baixar código e rodar npm ci, test, tsc e build no exato SHA final. Inspecionar logs CI e previews atuais.
B. E2E real protegido, com contas sintéticas isoladas: signup/pendência/aprovação/login/logout/reset, proteção cookies/CSRF/IDOR, quatro papéis, CRUD escalas, confirmações/desmarcações/presença, relatórios, audit logs, PDFs, mensagens, arquivos e permissões. Nunca inserir senhas em chat ou repo.
C. Ativação segura dos 4 titulares originais, com titular presente: 0/4 senha credential no Neon staging na verificação; magic link + nova senha pelo titular, manter UUID do perfil e comprovar login/revogação.
D. Testar PWA, PDF iOS/Android, push Web Push com dispositivo e inscrição nova consentidos; não enviar para subscriptions copiadas. Habilitar worker e cron só com revisão de credenciais e corte autorizado.
E. Obter conexão PostgreSQL READ ONLY privada do Supabase e conexão exclusiva segura de staging para ensaiar migration/sync.mjs (dry run, reviewed plan, test apply isolated, checksums). Não colocar owner password na Vercel. Resolver site_updates excluído sem remoção silenciosa e delta pós-congelamento.
F. Backup INTEGRAL e restaurável da fonte Supabase (DB incluindo Auth, configurações e eventuais objetos) com recuperação ensaiada e inventário de integridade. As branches backup Neon NÃO são equivalente.
G. Planejar congelamento de escritas, captura final, checksums, rollback com delta reverso, aprovação explícita, cutover e observação pós-corte. Sem aprovações/gates, manter produção Supabase.

## Referências existentes
- migration/CUTOVER-CHECKLIST.md
- migration/WORK-VALIDATION-20261107.md
- migration/CHAT-EXECUTION-HANDOFF-20261107.md
- migration/CHAT-CONTINUATION-20261107.md
- migration/AUTH-HASH-COMPATIBILITY-20261107.md
- migration/CHAT-PUSH-CUTOVER-HANDOFF-20261107.md

**Status: NÃO APTO A CUTOVER. Este checkpoint fornece evidências SQL atuais; não declara conclusão de tarefas não executadas.**

## Verificação adicional diretamente pelo Chat (posterior ao primeiro checkpoint)

- Criado SQL de regressão read-only `migration/sql/039-readonly-integrity-security-gates.sql`, commit `04e6cccdc2e1fc318c60584f0f0c6e6947f20553`.
- Executada a mesma consulta sobre Neon STAGING: `staging_integrity_security_pass=true`.
- Contagens: 0 vínculos órfãos para `assignments.mass_id`, `assignments.server_id`, `requests.user_id`, `push_subscriptions.user_id`, `migration_private.identity_map.profile_id`; 0 e-mails de perfil duplicados; 0 tabelas public base sem RLS; 0 papéis app/gateway com BYPASSRLS.
- A view `public.profile_directory` tem `security_invoker=true`, `coroinhas_app` pode consultá-la; não pode excluir diretamente `public.profiles` nem inserir diretamente em `public.audit_log`; fila push segue desativada.
- Executado também teste restrito de integridade sobre branch de cópia limpa `br-odd-bread-bc1jxzsh`: 0 órfãos em escalas/assinaturas push; 33 políticas public; 0 tabelas base sem RLS. O script 039 COMPLETO é exclusivo de staging, pois a cópia limpa não contém `migration_private.push_runtime`: não extrapolar aprovação da fila para a cópia limpa.
- Workflow Github Actions do commit anterior `0941c87` terminou com sucesso (run 42437520418); workflow do commit `04e6ccc` estava em andamento no instante da consulta (run 42437854384). Confirmar conclusão antes de promover SHA.
- Não houve escrita de dados em Supabase nem Neon; somente commit de testes/documentação em branch GitHub de homologação.
