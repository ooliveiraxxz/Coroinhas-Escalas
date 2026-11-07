# Homologação Work — 07/11/2026

**Parecer: NÃO APTO PARA SUBSTITUIÇÃO.** Produção permanece Supabase. Nenhum merge em main, troca de domínio, redefinição de senha real ou envio de push realizado.

## Escopo e referências

- Código inicial revisado: e98730246f872b5f6ea037ef79e7aa59a3bd3f0b, branch migration/neon-20261106.
- Correção inicial publicada: ae7ba1850828b9683ccac2773c47f39b293023d2.
- Neon exclusivo: noisy-hill-07078359 / br-rough-hill-bcj6lzt1 / coroinhas.
- Produção conferida via Vercel: dpl_GwdW15Pta5ESci61xgAwr1WovEmg, main 9187c6a17c3decd09dbeeb1569bb48cc89268495.
- Prévia ae7ba18: dpl_8FKQohXKGZ5WUCNCK9rQ2TUbJTBE, READY; tela de login e formulário de cadastro observados no navegador. Isso não equivale a login ou cadastro concluído.

## Correções novas

1. **Sincronizador não executava:** variável URL `target` sombreava a conexão e causava erro antes de comparar os dados. Corrigido; três testes de execução simulada inicialmente adicionados.
2. **Conflitos de sincronização:** aplicação agora exige `--reviewed-plan=arquivo.json` com fingerprints exatos da origem e destino. Divergências posteriores abortam antes de INSERT/ALTER. As tabelas do destino ficam bloqueadas durante validação/aplicação. Não há remoção automática. A revisão humana do plano continua obrigatória; este mecanismo não decide sozinho qual versão de um registro conflitante deve vencer.
3. **Push de teste:** preferências por categoria verificadas; inscrição, aprovação e preferências reconsultadas depois da reserva de tentativa. Timeout de envio de 10 segundos. Dispatcher continua desligado por padrão, restrito a lista explícita, VAPID de teste e autorização.
4. **Service Worker:** passa a usar identificador da notificação como tag. Antes usava uma única tag para todos os avisos. A tag permite substituir repetição do mesmo aviso sem substituir todos os avisos diferentes. Entrega exatamente uma vez não é garantida por Web Push; queda após entrega e antes de registrar sucesso ainda pode repetir tentativa.
5. **Pai responsável/pendente atribuído por API:** novo guard no banco impede inserir/reassociar funções a pais ou perfis não aprovados, tanto em assignments como fixed_rules. Duas atribuições históricas a coordenadoras permanecem intactas; coordenação/desenvolvedor aprovados continuam elegíveis, preservando compatibilidade existente. Alterações de presença sem troca do responsável continuam permitidas. SQL 014 aplicado apenas na homologação.

## Evidências aprovadas

| Verificação | Resultado | Limite |
|---|---|---|
| Instalação limpa `npm ci` | Aprovada | Aviso de peer dependency interno do Neon Auth; não houve falha |
| Testes Node/TypeScript | 38/38 aprovados | Incluem 10 regressões novas de sync/push; simulações não são E2E |
| TypeScript e build Next.js | Aprovados | Nenhuma prova de login por esse resultado |
| npm audit | Zero vulnerabilidades detectadas | Resultado pontual, dependências não alteradas depois |
| jsPDF | 4.2.1, geração PDF de fumaça aprovada | Não testa salvar/retornar no iPhone |
| security-tests.sql | Aprovada, 33 comandos incluindo BEGIN/ROLLBACK | Todos os dados fictícios revertidos |
| 011-critical-regression-tests.sql | Aprovada, 25 comandos incluindo transação | Aprovação de solicitação e privacidade |
| Sessões e bootstrap SQL | Aprovados | Cadastro pai pendente, expiração por papel/banimento e rejeição de sessão vencida; transação revertida, sem login HTTP |
| 015-server-assignment-tests.sql | Aprovado | Pai/pendente negados, coroinha aprovado aceito, reassociação negada, presença preservada; rollback |
| Estrutura após guard | 15 tabelas RLS, 33 políticas, 32 índices públicos, 22 funções públicas, 19 triggers | Dois triggers e uma função a mais que o handoff |
| Funções anteriores versionadas × banco | Corpos equivalentes nas 24 funções comparadas (incluindo auth/private), desconsiderando comentário traduzido em resolve_neon_identity | Não substitui restauração integral do schema |
| Fixtures/filas | Zero perfis fictícios persistidos; zero sessões ativas; zero jobs fora de suppressed | Nenhum push enviado |

## Dados e identidades

Última comparação desta sessão: **15/15 tabelas iguais, 251 registros públicos**, contagens e checksums por conteúdo iguais. A comparação foi feita com consultas somente leitura nos dois conectores; não é snapshot simultâneo durante congelamento de escritas. Não executado sync de produção.

| Tabela | Linhas em cada banco |
|---|---:|
| profiles | 4 |
| masses | 3 |
| assignments | 9 |
| requests | 3 |
| notifications | 14 |
| messages | 0 |
| guides | 5 |
| fixed_rules | 0 |
| site_updates | 7 |
| audit_log | 163 |
| banned_emails | 0 |
| login_events | 38 |
| push_subscriptions | 1 |
| screen_announcements | 2 |
| screen_announcement_dismissals | 2 |

Quatro perfis e quatro mapeamentos Neon, sem conflito de email; IDs originais preservados. **As quatro contas não possuem senha definida no Neon.** Portanto não estão homologadas para login. Ativação depende de recuperação segura por email com participação/autorização dos titulares; senhas antigas não foram importadas nem redefinidas.

A quinta identidade `migration-probe-20261106@example.invalid` foi criada nesta migração para verificar provisionamento do diretório Neon Auth. Tem registro de account, mas não tem senha, sessão ou vínculo permanente a perfil. Foi usada apenas em transação revertida para validação SQL. Permanece preservada; não é um usuário real nem uma conta administrativa operacional.

Configuração Auth conferida: cadastro/email-senha habilitados, sem confirmação obrigatória de email, revogação de sessões no reset habilitada. Remetente de email ainda compartilhado de desenvolvimento. Não foi testada entrega de reset. Nenhum convite/reset real enviado.

## Homologação e bloqueios concretos

O preview ae7ba18 abriu no navegador e exibiu as opções coroinha/pai responsável. Não foram inseridas credenciais reais. O conector de fetch protegido não conseguiu obter o endpoint (retornou erro de autenticação do deployment); isso não foi contabilizado como um teste 401 aprovado da aplicação. Tentativas locais de integração HTTP falharam na conexão de loopback do ambiente; nenhum resultado funcional foi inferido dessas falhas.

Permanecem **não executados/aprovados**:

- Cadastro/login/logout/recuperação HTTP e navegador, duplicidade/apropriação de contas, cookies/CSRF completos, isolamento do pool sob concorrência.
- Ativação e login dos quatro usuários antigos; aprovação e primeiro acesso de novos cadastros.
- E2E dos quatro papéis e todos os fluxos de escalas, presença/falta, servir/substituir, avisos, mensagens, relatórios, auditoria, orientações e preferências.
- PDF individual/mensal e salvar/voltar em iOS/Android; não há dispositivo físico disponível nesta execução.
- Push real com dispositivo consentido, nova assinatura e VAPID de teste. Nenhuma assinatura real foi usada para enviar.
- Worker Neon de produção: o dispatcher existente é apenas de teste; a rota antiga continua Supabase e bloqueada no modo de migração. Não ativar nem promover como solução de produção.
- Sincronização real com duas conexões privadas e restauração ensaiada. Há testes simulados e comparação pelos conectores, não um ensaio completo com Postgres real.
- Backup consistente/restaurável do Supabase. Acesso SQL por conector não fornece por si só um backup restaurável de Auth/configuração/arquivos.

## Backup e reversão

O Neon recusou `create_snapshot` para a branch secundária: `not allowed to snapshot non-root branch`. Foi criada uma cópia sem compute: **backup-pre-e2e-coroinhas-20261107**, ID **br-hidden-haze-bcuoq602**, parent LSN **0/1DD8208**. Ela preserva um ponto do destino antes dos novos testes/guard; não substitui backup da origem nem restauração comprovada. Nenhuma branch foi apagada.

Antes do corte: backup consistente da origem e inventário Auth/configuração, restauração isolada e integridade comprovadas, commit homologado fixado, janela combinada e congelamento de escritas. Interromper diante de falha de identidade, checksum, permissões, funcionalidade crítica ou backup.

Após aceitar escritas no Neon, retorno ao Supabase exige congelar novas escritas, exportar e revisar alterações por PK/tabela, reconciliar conflitos e identidades, preservar relações/auditoria, conferir contagens/checksums e testar antes de reabrir. Simplesmente restaurar o deployment antigo pode perder dados novos. Não há reconciliação reversa automatizada homologada.

## Próximo operador

1. Ativar contas fictícias e testar login/cadastro por canal seguro; não compartilhar senhas no chat/repositório.
2. Concluir E2E no preview atualizado e testar dispositivos/entrega consentida.
3. Fornecer ao executor, por configuração privada, conexão somente leitura da origem e conexão administrativa exclusiva do destino. Não colocar a conexão owner na Vercel.
4. Produzir plano com `node migration/sync.mjs > plano-revisao.json`, revisar diferenças e só então ensaiar `node migration/sync.mjs --apply --confirm-isolated-neon --reviewed-plan=plano-revisao.json` em ambiente isolado. O plano contém hashes e contagens, não dados de usuários.
5. Completar backup/restauração e plano de worker/ativação em produção. Só solicitar autorização de corte quando todos os portões forem aprovados.

**Nenhuma autorização de corte foi presumida. O lançamento deve permanecer no Supabase enquanto estes bloqueios existirem.**

## Conferência da prévia final

Código final de aplicação: **60c0e253293257ed90e21fc1fa69dec5f712f418**. Deployment de preview **dpl_BHwfVMka5qvs4YA4uaAvX8Cy11EJ**, build concluído na Vercel. URL: https://coroinhas-escalas-lyjyyl4hf-ooliveiraxxz.vercel.app/ . Origem adicionada à lista permitida do Neon Auth apenas na branch isolada.

No navegador, a tela de login carregou e o acesso direto não autenticado a `/api/migration/data/profiles` devolveu `Não autenticado.`, sem retornar perfis. Este é um teste real de rejeição anônima; não prova cookies autenticados, login ou revogação ponta a ponta.

O script SQL de bootstrap/expiração de sessões efetivamente executado com rollback está preservado em `migration/sql/016-auth-session-tests.sql`. A última consulta confirmou novamente zero fixtures, zero sessões ativas, quatro perfis e quatro vínculos; os 15 checksums públicos permaneceram iguais nos dois bancos. Nenhuma restauração de backup foi declarada aprovada.
