# Coroinhas: migração isolada para Neon

Status em 06/11/2026: **NÃO APTO PARA TROCA DE PRODUÇÃO**. Lançamento previsto: 14/11/2026.

## Ambiente preservado

- Origem: Supabase `dsglwwwwdtjynipauvrp`. Apenas consultas de leitura nesta sessão.
- Destino original: Neon `noisy-hill-07078359`, banco `coroinhas`, branch `br-rapid-firefly-bcrdnvhq`. Não alterado.
- Homologação: `migration-coroinhas-20261106`, ID `br-rough-hill-bcj6lzt1`.
- Código base: `9187c6a17c3decd09dbeeb1569bb48cc89268495`.
- Código experimental: branch `migration/neon-20261106`; deploy automático desta branch desativado no vercel.json. Não fazer merge nem deploy sem autorização.
- Nenhuma senha, hash de senha, token de sessão ou chave privada exportada para os arquivos.

## Entregue e verificado

1. Inventário de 24 funções em public + 1 função privada, 33 políticas, 17 gatilhos de aplicação em public + criação de perfil em auth.users. Mais 7 gatilhos internos de Storage e 7 event triggers inventariados. Não copiar funções de plataforma indiscriminadamente.
2. Storage sem buckets/objetos, nenhuma Edge Function e nenhuma tabela publicada via Realtime no momento da consulta. Aplicativo usa refresh explícito, sem assinatura de canal encontrada.
3. As 33 políticas foram recriadas para `coroinhas_app`, papel NOLOGIN/NOBYPASSRLS. Não recebeu TRUNCATE, TRIGGER nem acesso ao schema privado. 20 funções públicas e 17 gatilhos públicos instalados; `auth.uid()` lê contexto transacional definido exclusivamente pelo backend.
4. Identidades preservadas por `migration_private.identity_map`, inicialmente Supabase UUID → profiles.id. Os 4 perfis atuais (1 desenvolvedor, 3 coordenadoras) continuam com seus IDs, papéis e aprovação. Isso NÃO significa contas de login importadas para Neon Auth.
5. Gateway experimental Next.js para o subconjunto PostgREST usado no app. Parâmetros de valor vinculados; tabelas/colunas/RPCs em lista permitida; getUser valida a identidade no Supabase; papel restrito e contexto por transação. Endpoint desativado por padrão e sempre bloqueado em VERCEL_ENV=production. Credencial do banco permanece no servidor. Ainda usa credencial do proprietário no servidor e SET LOCAL ROLE: antes de produção, provisionar login de serviço com privilégios mínimos e testar isolamento do pool.
6. Cadastro, recuperação e atualização de senha via cliente de homologação bloqueados para não modificar usuários da origem. Gestão de usuários (banir/excluir/mudar papel por RPC) deliberadamente indisponível nesta fase.
7. Push substituído por outbox com estado `suppressed`. Webhook antigo bloqueado no modo de migração. Nenhum envio real disparado. A inscrição push existente foi copiada diretamente entre bancos, sem gravar seu conteúdo em arquivo ou relatório.
8. Verificação final: 15 tabelas, **250 registros**, checksums iguais tabela a tabela. A cópia inicial tinha 249 e faltava 1 push_subscription. Sem registros de teste persistidos. Sequências de auditoria/login alinhadas; testes com rollback podem consumir números, sem perda de registros.
9. 11 testes automatizados TypeScript passaram; testes SQL transacionais passaram (anônimo, pendente, papéis, acesso a rascunho, notificações de terceiros, escalada de papel, confirmar/desmarcar, leitura, auditoria, outbox). Build Next.js e checagem TypeScript passaram. NÃO são testes completos E2E, concorrência nem recuperação de desastre.

## Diferenças de segurança e pontos de atenção

- Origem permite coordenadora alterar role por UPDATE de profiles via policy + protect_profile. Na homologação, role só pode mudar com desenvolvedor; coordenadora não altera aprovação de perfis especiais. Identidade/email imutáveis nesta fase.
- RLS original permite perfis aprovados ler outros perfis aprovados, incluindo campos como email/notes em SELECT *. Ainda preservado para compatibilidade; revisar projeção de dados pessoais antes de exposição da API.
- Avisos individuais: política de dismiss exige aviso ativo mas não valida destinatário. Revisar esta autorização antes de cutover; não considerar o inventário como aprovação automática de todas as regras originais.
- `respond_assignment` atual permite confirmar antes do dia da missa e só desmarcar antes do início. Comportamento preservado; diverge de requisitos históricos. Validar regra desejada antes de modificá-la.
- Funções SECURITY DEFINER exigem manutenção cuidadosa dos checks e grants. get_push_targets, on_signup, developer_manage_user, rls_auto_enable e webhook pg_net não foram transportados literalmente.
- Advisories da origem: 2 tabelas com RLS sem policy (banned_emails/login_events, usadas por funções); get_push_targets e notify_pending_approval sinalizadas por execução anon; proteção de senhas vazadas desativada. Nenhuma correção aplicada à produção.

## Plano de autenticação

A documentação atual de Managed Better Auth informa incompatibilidade de importação de senhas Supabase e `updateUser({password})` não suportado no adaptador. Não renomear a biblioteca e assumir preservação de login.

Fonte: https://neon.com/docs/auth/migrate/from-supabase (consultada em 06/11/2026).

Caminho de menor risco para a data de lançamento: manter o site atual no Supabase enquanto a homologação continua. A API experimental usa Supabase Auth como ponte temporária apenas; não é independência completa do Supabase.

Para a substituição definitiva:

1. Habilitar Neon Auth somente em ambiente isolado e implementar cadastro, login, sair, restauração de sessão, verificação de email e recuperação de senha próprios.
2. Manter profiles.id e todas as FKs. Mapear o subject Neon para o UUID existente em identity_map; não usar emails fornecidos pelo navegador para conceder acesso.
3. Para cada conta existente, exigir prova de controle via sessão Supabase válida + autenticação Neon verificada, ou fluxo administrativo de identidade equivalente. Um email coincidente sozinho nunca vincula conta nem transfere papel.
4. O papel vem exclusivamente de profiles, nunca de metadata editável. Cadastro novo começa pendente; somente coroinha/pai podem ser solicitados pelo próprio usuário.
5. Testar reset, email duplicado, sessões vencidas, banimento e exclusão sem cascatas destrutivas antes de habilitar gestão de usuários. Não apagar auth.users da origem.
6. Só definir ativação final após comprovar as quatro contas preservadas e os fluxos com fixtures de todos os papéis. Não enviar convites ou resets reais nesta etapa.

## Notificações

- Notificações internas por mensagens, solicitações e desistências funcionam por triggers/funções transportados.
- Outbox preserva intenção de envio sem chamar produção.
- Falta worker idempotente, retentativas, expiração de inscrições, preferências e teste autorizado com destinatário de homologação.
- Preservar VAPID privado em segredo quando autorizado configurar, sem mudar o domínio de origem das inscrições arbitrariamente. Testar no iPhone/PWA; uma inscrição copiada não garante entrega em outro domínio.

## Sincronização e rollback

`node migration/sync.mjs` exige variáveis privadas SOURCE_READONLY_DATABASE_URL, NEON_MIGRATION_DATABASE_URL e MIGRATION_SOURCE_PROJECT=dsglwwwwdtjynipauvrp. Script preparado, **ainda não executado de ponta a ponta com duas conexões diretas**. A sincronização desta sessão usou os conectores para copiar apenas o registro faltante e comparar checksums.

O script lê uma transação REPEATABLE READ READ ONLY da origem, exige marcador da branch isolada, recusa divergências por exclusão e usa upsert por PK. Desabilita somente triggers USER no destino dentro da transação para não duplicar notificações/auditoria; mantém constraints. Compara checksums antes de commit. Não copia auth.users, segredos privados nem tabelas internas. Novos/excluídos usuários exigem reconciliação de identidade à parte.

Antes de uma eventual troca autorizada: nova cópia consistente, inventário de arquivos/auth, reconciliar exclusões sem apagar automaticamente, pausar escrita por janela combinada, última sincronização, testes e aprovação. Após aceitar escritas no Neon, retornar ao Supabase exige reconciliação reversa; mudar URL sozinho pode perder alterações. Nenhum rollback destrutivo automatizado foi criado.

## Pendências que impedem produção

- Substituição de Auth e gestão de usuários.
- Testes reais de browser/mobile/PWA: login, cadastro, aprovações, escalas, edição/exclusão, presença, servir/substituir, PDFs, avisos, suporte, perfis e logout.
- Testes de concorrência/IDOR de todas as RPCs, sessão/revogação, contexto no pool e política de avisos individuais.
- Worker push, email transacional e entrega autorizada em ambiente separado.
- Executar/validar o script de sincronização completo; preparar reconciliação pós-cutover.
- Provisionar credencial de backend mínima; revisar limites/paginação para crescimento além de 1000 registros.

Recomendação de prazo (não é agendamento): revisão de viabilidade em 11/11 e congelamento de mudanças arriscadas em 12/11. Se qualquer bloqueio persistir, lançar em 14/11 com o site atual estável e continuar a migração depois.

## Executar verificações

```sh
node --import tsx --test tests/*.test.ts
npx tsc --noEmit
npm run build
```

`migration/sql/001-isolated-security.sql` é uma migração de execução única, somente na branch indicada. Não reaplicar na mesma branch. `security-tests.sql` usa BEGIN/ROLLBACK e fixtures; não usar em produção. O inventário em audit/ contém definições, metadados e checksums, sem conteúdo de usuários ou credenciais.


## Continuação — 07/11/2026 (modo Chat)

- **Homologação somente:** não houve alteração nas branches principais, deploy de produção nem mudança no Supabase original.
- Configuração Neon Auth alterada para cadastro sem OTP de confirmação de e-mail, conforme regra de aprovação manual. Recuperação de senha continua exigindo prova de controle do e-mail. Sem e-mail verificado não significa aprovação automática.
- `components/NeonLogin.tsx` ajustado para cadastro sem etapa de verificação. `migration/sql/004-optional-email-verification.sql` contém a atualização aplicada a `resolve_neon_identity`. A função continua validando sessão, banimento e vínculo administrativo de identidades.
- Política de dismissals reforçada em `migration/sql/005-restrict-announcement-dismissals.sql`: somente aviso ativo e destinado ao usuário aprovado poderá ser marcado como visto.
- `migration/sql/006-readonly-security-smoke.sql` executado e aprovado: 15 tabelas com RLS, role de gateway sem bypass, vínculos de identidade consistentes e políticas dos avisos presentes.
- Testes SQL de leitura: papel sem identidade vê zero perfis/escalas/avisos; coordenadora vê dados permitidos e zero auditorias; coordenadora não pode executar ação exclusiva de desenvolvedor.
- `lib/neon/database.ts` recusa URL com usuário de banco diferente de `coroinhas_gateway`, host fora do Neon ou banco diferente de `coroinhas`. Testes de unidade adicionados em `tests/neon-database.test.ts` **ainda não executados** em build/CI.
- Um evento de login novo foi copiado para a homologação (somente append com PK preservada). Origem e destino têm 38 registros de `login_events`, último ID 39 na verificação. A sequência foi alinhada.
- Checksum de conteúdo: 14/15 tabelas coincidem no instante de consulta. A única divergência é `profiles.last_seen_at`, informação volátil de último acesso. IDs, e-mails, nomes, papéis, aprovações e demais campos de perfis coincidem. Reconciliar antes do cutover.
- Neon Auth: 5 identidades, 4 mapeadas a perfis preservados, 1 não mapeada; 0 sessões ativas na verificação. Não apagar a identidade adicional sem confirmação de origem.
- **Ainda não validado:** novo build TypeScript/Next após estes commits, registro/login/recuperação reais, verificação de comportamento de conta pendente, autenticação dos 4 perfis, integração completa, notificações push, testes E2E de navegador, sincronização final e implantação de homologação.
- **Bloqueio de lançamento com Neon:** continua **NÃO APTO PARA PRODUÇÃO** enquanto esses testes não passarem. Lançamento em 14/11 deve usar Supabase se não houver validação completa e autorização explícita.

### Testes adicionais do mesmo dia

- `migration/sql/007-assignment-confirmation-rules.sql` foi aplicado apenas ao Neon de homologação. `respond_assignment` exige que a confirmação seja no dia civil da missa (America/Sao_Paulo), antes do início. Desmarcação pode ocorrer depois do horário quando a atribuição ainda estiver `escalado`/`confirmado`, exige justificativa e não dispara anúncio de substituição para eventos já iniciados. Presença `presente`/`faltou` permanece protegida.
- Interface de homologação em `components/System.tsx` alinhada: botão de confirmação apenas no dia; botão de desmarcar disponível enquanto o status permitir.
- Testes SQL transacionais de confirmação futura negada, confirmação no dia aceita, desmarcação passada aceita e ausência de notificação de vaga passada **passaram**. Os registros fictícios foram desfeitos por SAVEPOINT; consultas posteriores confirmaram zero fixtures persistidas.
- Testes SQL transacionais de aviso individual para destinatário errado (negado) e aviso geral (permitido) **passaram**, também com rollback integral.
- `migration/sql/security-tests.sql` atualizado para usar missa no dia atual na fixture, refletindo a regra nova. **A suíte completa do arquivo ainda precisa ser executada novamente.**
- Auditoria Vercel somente leitura: existe um deployment de homologação READY na branch experimental, porém baseado no commit `6355e2d`, **anterior** às correções recentes. Nenhum deploy novo foi efetuado; os testes de interface desse deployment não validam o HEAD atual.

**Antes de autorizar produção:** executar `npm ci && npm test && npx tsc --noEmit && npm run build` na branch atualizada, validar variáveis da homologação (gateway restrito), produzir novo preview somente com autorização, testar cadastro/login/resets/4 perfis, revisar a quinta identidade, push, E2E e sincronização final. Não executar cutover automaticamente.


## Auditoria adicional e correções — 07/11/2026

### Comparação renovada (consulta direta nos bancos)
- **15/15 tabelas públicas**, **98/98 colunas das tabelas**, **32/32 índices**, **33/33 políticas RLS**, **17/17 gatilhos** (um adaptado para fila push). 
- Checksum dos registros: **14 de 15 tabelas idênticas**; a única divergência detectada é `profiles.last_seen_at`, campo volátil de último acesso. A comparação é pontual, não substitui a sincronização final.
- 24 funções públicas na origem e 21 no Neon: `get_push_targets`, `on_signup` e `rls_auto_enable` não foram transportadas literalmente porque dependem do Supabase. Adaptadores para cadastro e push precisam ser homologados funcionalmente.
- Dois relacionamentos antes apontavam para `auth.users` (Supabase). O ID do perfil continua preservado por `migration_private.identity_map`; **não** apontar esses IDs diretamente para sujeitos Neon Auth.
- `push_subscriptions.user_id` agora tem FK validada para `public.profiles(id)` (RESTRICT, sem exclusão implícita). Script aplicado e versionado em `migration/sql/008-push-subscription-profile-fk.sql`. Zero inscrições órfãs.
- Nenhum bucket/objeto de Storage nem Edge Function encontrados na origem no momento da auditoria.
- Neon Auth continua com 5 contas, 4 vinculadas, 1 não vinculada, sem sessões ativas. A identidade adicional está **preservada, não aprovada e não excluída**. Os 4 vínculos existentes não apresentam conflito de e-mail.

### Testes e segurança
- Suíte SQL de segurança `migration/sql/security-tests.sql` **executada novamente** em transação isolada: **31 instruções de teste passaram**, com rollback integral. Consulta posterior mostrou **zero perfis fictícios** restantes.
- Rejeição de sessão inválida pela função de identidade testada em dois cenários: usuário vinculado e não vinculado. Ambos negados; nenhum novo perfil gerado.
- `coroinhas_app` e `coroinhas_gateway` não têm CREATE no schema público; gateway não tem bypass RLS nem superuser. Todos os 15 tables têm RLS e as funções SECURTY DEFINER conferidas possuem search_path fixo.
- `migration/sql/009-readonly-cutover-readiness.sql` executado: `static_checks_ok=true`, mas **não** equivale a aprovação de produção, não cobre login, build, push nem E2E.
- Variáveis de homologação `NEON_AUTH_BASE_URL`, `NEON_AUTH_COOKIE_SECRET`, `NEON_MIGRATION_DATABASE_URL`, `NEON_MIGRATION_ENABLED`, `NEXT_PUBLIC_DATA_BACKEND` existem **somente no preview da branch experimental** na Vercel, além das variáveis de produção do sistema atual. Valores sensíveis não foram inspecionados nem expostos.
- Texto de erro em `app/api/migration/session/route.ts` corrigido para não exigir OTP de verificação que está desativado.

### Segurança operacional e preparação
- `migration/sync.mjs` agora executa auditoria com **transação somente leitura por padrão**. A sincronização que escreve precisa de `--apply --confirm-isolated-neon` e variável privada `NEON_MIGRATION_ADMIN_DATABASE_URL` com conta `coroinhas_owner`. A execução de escrita **não foi realizada**. Ensaio em duas conexões também ainda não foi executado aqui.
- `.github/workflows/neon-migration-validation.yml` criado para checar sintaxe do sincronizador, instalar via `npm ci`, executar testes, TypeScript e build **sem segredos e sem deploy**. A execução/conclusão desse CI **ainda não foi confirmada** via ferramenta de status.
- `migration/CUTOVER-CHECKLIST.md` contém portões de segurança, janela de manutenção e condições de abortar/reverter. Documento somente; nenhuma troca ocorreu.

### Bloqueios para a substituição
1. Compilação e testes de aplicação no HEAD recente ainda sem resultado confirmado.
2. Ativação/autenticação real dos quatro perfis, teste de cadastro pendente, bloqueio, logout, recuperação e da quinta conta.
3. Novo preview correspondente ao HEAD, testes funcionais e E2E por papel, inclusive mobile, PDFs, presenças e mensagens.
4. Worker de push real e nova inscrição de dispositivo consentida; outbox segue `suppressed` e nenhuma entrega foi habilitada.
5. Script de sincronização deve ser ensaiado com URLs e credenciais privadas e revisão de diferenças antes de executar a escrita.
6. Backup, janela de congelamento, reconciliação final, autorização expressa e plano de reversão revisado.

**Decisão:** NÃO APTO PARA MIGRAÇÃO FINAL; Supabase permanece oficial.


### Verificação complementar da audiência de substituições

- `respond_assignment` envia avisos de substituição apenas para usuários aprovados com papéis `coroinha`, `coordenadora` ou `desenvolvedor`, excluindo `pai`. A alteração foi aplicada apenas na homologação e registrada em `migration/sql/007-assignment-confirmation-rules.sql`.
- Teste SQL com coroinha e pai fictícios: coordenadoras receberam os avisos, pai não recebeu e os dados foram revertidos; zero fixtures persistidas.
- O método `emailOtp.resetPassword` e a verificação por OTP na recuperação de senha foram conferidos na documentação atual do Neon. **Não houve envio de código real nem teste de entrega.** Neon recomenda provedor dedicado de SMTP para produção, enquanto o projeto ainda está configurado com provedor compartilhado de desenvolvimento.
- Vercel auditada novamente em modo leitura: a última homologação publicada permanece no commit antigo `6355e2d`; os commits recentes não estão implantados. A implantação de produção continua na branch `main`/Supabase.


## Execução complementar solicitada pelo usuário — 07/11/2026

### Código e autenticação
- `public.approve_service_request` corrigida no Neon isolado para rejeitar solicitações de usuários não aprovados/sem papel coroinha, missas já iniciadas e substituições de vagas que deixaram de estar desmarcadas. Script versionado em `migration/sql/010-service-request-guards.sql`.
- Três cenários testados via transação e SAVEPOINT: pedido antigo negado, usuário pendente negado, solicitação válida aprovada. Zero fixtures persistidas.
- Máscara de `public.profile_directory` testada usando papel fictício de coroinha: dados privados de outros usuários não foram expostos; a própria conta conseguiu consultar seus dados. Os perfis especiais continuam com visão administrativa autorizada.
- Teste de banimento via `developer_manage_user` com perfil fictício comprovou `approved=false` e inserção de e-mail bloqueado, integralmente revertido após o teste. **Não substitui teste E2E com sessão real do Neon Auth.**
- `migrationEnabled()` em `lib/auth/server.ts` passou a exigir simultaneamente `NEON_MIGRATION_ENABLED=true`, `NEXT_PUBLIC_DATA_BACKEND=neon-migration` e ambiente Vercel diferente de produção. O endpoint de dados reutiliza esta única guarda; teste automatizado da rota atualizado.
- Arquivo `migration/sql/011-critical-regression-tests.sql` criado para repetir, sempre com ROLLBACK, casos de aprovação e privacidade; sua lógica foi testada separadamente na homologação.

### Funções, gatilhos e notificações
- Inventário estático inspecionou 21 funções públicas. Funções sensíveis expostas pelo papel de aplicação possuem checagem de papel/identidade; funções de gatilho que não fazem essa verificação diretamente não têm autorização EXECUTE pública. **Análise estática não prova a ausência de vulnerabilidades em todas as funções.**
- Gatilho de mensagens testado: sugestão de coroinha fictício gerou notificação para coordenadora e registro da operação na auditoria. Transação revertida.
- Gatilho de push testado: notificação inserida foi registrada na outbox com `state=suppressed`, sem envio externo; teste revertido.
- `migration/push-readiness.mjs` criado: utilitário offline de contagens read-only de inscrições/filas e integridade. Nunca realiza envio. Acrescentada verificação de sintaxe ao CI. **Não há ainda worker de entrega push pronto para produção.**

### Sincronização e diagnóstico
- `migration/sync.mjs` reforçado: o modo padrão é auditoria `BEGIN READ ONLY`; gravação exige flags explícitas. Como o papel restrito do aplicativo não pode ler todas as linhas, a auditoria offline agora exige uma conexão administrativa separada da branch de homologação, jamais incluída nas variáveis da Vercel. Host, usuário, projeto de origem e banco de destino são validados. Variável privada documentada em `migration/environment.example`.
- O modo offline de sincronização **não foi executado de ponta a ponta**, pois precisa das duas credenciais de banco privadas. A comparação direta por conectores confirmou 15/15 tabelas com mesmo número de linhas e 14/15 com checksum idêntico (diferença no último acesso de perfis).
- Na verificação final: 15 tabelas, 33 RLS, 32 índices, 17 gatilhos, 4 perfis, 4 vínculos Neon de perfis, 5 identidades Neon Auth, zero inscrições push órfãs, zero push fora do estado suprimido e zero fixtures persistidas.
- Suíte SQL `migration/sql/security-tests.sql` executada novamente após as mudanças: **31 instruções aprovadas**, com rollback completo.
- Projeto Vercel e branch `main` não foram publicados ou modificados. Nenhum banco oficial foi alterado.

### Ainda bloqueado
- CI/build TypeScript/Next mais recente: pipeline configurado, conclusão não verificada.
- Login/cadastro/recuperação/logout reais e sessões revogadas no Neon Auth; a quinta conta de teste não foi excluída.
- Workflow push real, entrega de e-mail de recuperação e testes de dispositivos.
- E2E de escalas, presenças, solicitações, PDFs, mensagens, relatórios e interface.
- Preview atualizado e seu teste no navegador, sincronização final, backup/restauração e autorização explícita de cutover.

**Avaliação após esta execução: NÃO APTO para migração final.**


## Encerramento do escopo técnico do Chat — 07/11/2026

As verificações e correções diretamente executáveis pelo Chat estão documentadas em [CHAT-HANDOFF-20261107.md](./CHAT-HANDOFF-20261107.md). A última compilação testada aprovou 28/28 testes, TypeScript, build e auditoria npm sem vulnerabilidades detectadas. O snapshot de `last_seen_at` foi sincronizado na homologação com precisão integral; os 15 checksums de tabelas públicas coincidiram na conferência. Foi criado um ledger privado idempotente para push de teste, mas o envio real permanece desabilitado. O Neon **continua não apto para produção** até conclusão dos testes E2E e autorização expressa de substituição.
