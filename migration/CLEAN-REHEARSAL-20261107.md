# Ensaio limpo Neon — execução real e evidências — 07/11/2026

**Origem oficial NÃO alterada:** Supabase `dsglwwwwdtjynipauvrp`, Vercel de produção, GitHub `main`.
**Cópia isolada exclusivamente de ensaio:** Neon `noisy-hill-07078359` / `br-odd-bread-bc1jxzsh` (nome `coroinhas-clean-sync-rehearsal-20261107`). Clonada da branch histórica `br-ancient-dust-bcespekt`, não de um backup lógico completo da origem.

## 1. O que foi executado nesta branch isolada

1. Criada uma nova branch a partir de uma cópia anterior com 251 linhas, sem as 100 linhas extras da homologação principal.
2. Marcador `migration_private.environment.branch_id` atualizado para a branch **real** `br-odd-bread-bc1jxzsh`, prevenindo que o script confunda a branch original e o ensaio.
3. Origem Supabase e clone comparados por contagem e checksum das **15 tabelas**, em leitura; diferenças iniciais: `profiles.last_seen_at`, `audit_log` com 1 linha nova só na origem, e `site_updates` com 1 linha extra na cópia.
4. O único novo registro de `audit_log` foi copiado para a **branch de ensaio apenas**, conservando ID e demais campos, com `OVERRIDING SYSTEM VALUE`. Sequência de identidade reposicionada para não colidir.
5. Os valores de `profiles.last_seen_at` foram reconciliados com a origem na branch de ensaio, sem replicar notificações ou auditoria artificial.
6. Segunda comparação **leitura somente**, após o ensaio: 14/15 tabelas têm **checksums idênticos**; Supabase **251**, clone **252** linhas. A única diferença restante é `site_updates` (6 na origem, 7 na cópia). Não houve remoção e não há motivo para presumir que a linha extra seja fixture: a origem registrou evento posterior de exclusão da atualização.
7. Quatro perfis reais, quatro mapeamentos Neon, 1 desenvolvedor, 3 coordenadoras, 15 tabelas com RLS, 33 políticas, 0 inscrições push órfãs, total de 5 contas Neon Auth na cópia. SQL `023-isolated-clean-rehearsal-readiness.sql` executado e retornou `structural_readiness=true`.

A comparação não é um snapshot atômico cruzando os dois provedores: alterações que chegarem ao Supabase devem ser reconsultadas e sincronizadas de novo.

## 2. O que foi corrigido no sincronizador

`migration/sync.mjs` agora suporta `MIGRATION_TARGET_BRANCH_ID` com **allowlist restrita**:
- `br-rough-hill-bcj6lzt1` — homologação original, com dados de teste; não apta para apply.
- `br-odd-bread-bc1jxzsh` — ensaio limpo, com 1 divergência de exclusão na origem; também **não apta para apply** até conciliação.

O script exige marcador de branch correspondente, projeto de origem exato e parâmetros privados de Postgres; `--apply` continua exigindo plano revisado e bloqueia registros exclusivos do destino. `tests/neon-sync.test.ts` testa branch autorizada e rejeita outras. Nunca apontar o script para produção.

**Comando de auditoria SOMENTE LEITURA**, para executor com conexões privadas autorizadas (não incluir senhas no comando nem em logs):

```bash
MIGRATION_TARGET_BRANCH_ID=br-odd-bread-bc1jxzsh \
MIGRATION_SOURCE_PROJECT=dsglwwwwdtjynipauvrp \
node migration/sync.mjs
```

As variáveis `SOURCE_READONLY_DATABASE_URL` e `NEON_MIGRATION_ADMIN_DATABASE_URL` precisam ser configuradas previamente como segredos de ambiente restritos à origem em leitura e à branch isolada. Não usar estas URLs no frontend ou nos arquivos versionados. Esse comando **não foi executado pela conexão direta**, que permanece pendente; o ensaio de 14/15 foi feito pelas ferramentas conectadas de banco.

## 3. Pendência exata de reconciliação de dados

- A linha exclusiva de `site_updates` na cópia tem um **registro de exclusão posterior na auditoria oficial da origem**. Não apagar automaticamente: confirmar política de preservação/arquivamento e estabelecer plano aprovado para o destino final.
- `last_seen_at` é volátil: atualizar novamente na janela final e comparar a origem após congelar escritas.
- Validar `audit_log` e novas alterações antes do corte. Nunca inferir prontidão por contagem líquida apenas.

## 4. Portões que permanecem obrigatórios

- Titulares dos quatro usuários antigos ainda devem ativar e comprovar seu login Neon Auth; preservar os UUIDs, sem senha gerada pelo operador.
- Browser E2E real e permissões completas de todos os papéis, PDFs mobile/PWA.
- Entrega push com dispositivo de teste consentido; agendamento, credencial limitada, VAPID e ativação de produção continuam deliberadamente desativados.
- Backup restaurável da origem Supabase incluindo dados/identidades/configurações e ensaio completo de recuperação.
- Ensaio direto `sync.mjs` com duas conexões separadas e plano revisado, resolução da linha exclusiva, janela de congelamento, nova igualdade de 15/15 e rollback.
- Autorização expressa para cutover. **Não fazer merge em `main` ou alterar Vercel produção.**

**Status: engenharia de sincronização mais preparada; ainda NÃO apto para troca definitiva.**
