# Entrega técnica da migração — conclusão do escopo do Chat

Data: 07/11/2026. **Produção NÃO alterada.** Nenhuma substituição de banco foi realizada.
Código de homologação: `migration/neon-20261106`.
Neon de homologação: `noisy-hill-07078359` / `br-rough-hill-bcj6lzt1`.
Origem oficial: Supabase `dsglwwwwdtjynipauvrp`.

## Oito tarefas assumidas pelo Chat

| Tarefa | Trabalho comprovado | Situação |
| --- | --- | --- |
| 1. APIs Neon | Revisado adaptador PostgREST; fail-closed em parâmetros duplicados e incorretos; RPCs/tabelas usadas pela interface cobertas por testes | Revisão estática e testes unitários concluídos |
| 2. Filtros, operações e upsert | Conflicts são permitidos somente em chave primária/UNIQUE existente; sem SQL concatenado com valores do usuário; casos de filtros, RPCs e operações testados | Concluído na camada estática |
| 3. Sessões, bloqueio e alterações de papéis | Banimento marca perfil não aprovado e conta Neon bloqueada; sessões ativas expiradas sem excluir histórico. Mudança de papel também expira sessões. Testes transacionais fictícios aprovados e revertidos | Concluído no banco |
| 4. Notificações push | Filas mantidas `suppressed` em homologação; ledger privado de tentativas com chave composta única instalado; dispatcher de teste com `--send-test` e múltiplas barreiras (allowlist explícita, opt-in, VAPID teste, branch isolada) criado, desligado por padrão. Teste SQL de idempotência aprovado | Preparação técnica concluída; entrega real intencionalmente NÃO testada |
| 5. jsPDF | `jsPDF@4.2.1` corrigido nos manifests; teste PDF de fumaça adicionado; auditoria npm sem vulnerabilidades detectadas | CI aprovado |
| 6. Sincronização | Script offline somente leitura por padrão, requer credenciais privadas exclusivamente de homologação e confirmação para escrever. `last_seen_at` reconciliado com precisão de microssegundos no Neon de homologação e sem duplicar auditoria | Checksums 15/15 no instante da comparação; sync de corte final NÃO executado |
| 7. Auditoria final | 15 tabelas públicas, 33 políticas RLS, 32 índices, 17 gatilhos; 4 perfis/4 vínculos, 5 contas auth e 1 conta de teste não vinculada; sem inscrições push órfãs ou fixtures persistidas | Checagens estáticas/SQL aprovadas |
| 8. Documentação para Work | README atualizado; este handoff e checklist de cutover/reversão. CI de segurança sem segredos e sem deploy | Concluído |

## Evidências verificadas

- CI GitHub Actions `Neon migration validation (isolated)`: run [42389858169](https://github.com/ooliveiraxxz/Coroinhas-Escalas/actions/runs/42389858169): **28/28 testes TypeScript/Node aprovados**, checagem TypeScript e build Next.js aprovados, `npm audit` relatou **0 vulnerabilidades**.
- SQL `migration/sql/security-tests.sql`: 31 instruções aprovadas em transação com rollback, repetidas depois das correções.
- Testes isolados de proibição/aceitação de substituição, e-mails e papéis, revogação por banimento e alteração de papel, máscara de campos privados, gatilhos de mensagem/auditoria, supressão de push e unicidade do ledger de entrega foram executados em transações com rollback.
- Comparação direta dos dados públicos: **15/15 tabelas com checksums idênticos**, no instante da consulta. A diferença volátil de `profiles.last_seen_at` foi reconciliada preservando a precisão de microssegundos e sem registrar eventos artificiais na auditoria. Isso NÃO garante igualdade futura sem nova sincronização.
- Readiness SQL `migration/sql/009-readonly-cutover-readiness.sql`: `static_checks_ok=true`, o que não equivale a passar por testes reais.
- Variáveis de homologação da Vercel são restritas à branch de preview. Produção permanece na branch `main` e usa Supabase.

## Arquivos principais da entrega

- `lib/neon/query.ts`, `tests/neon-query.test.ts`
- `app/api/migration/data/[...path]/route.ts`, `lib/auth/server.ts`, `tests/neon-route.test.ts`
- `migration/sql/012-revoke-banned-neon-sessions.sql`
- `migration/sql/013-push-delivery-ledger.sql`, `migration/push-test-dispatch.mjs`, `migration/push-readiness.mjs`
- `migration/sync.mjs` e `migration/environment.example`
- `tests/jspdf-smoke.test.ts`
- `.github/workflows/neon-migration-validation.yml`, `migration/CUTOVER-CHECKLIST.md`

## Ainda não homologado (fora da capacidade da revisão isolada)

1. Login real, cadastro, recuperação de senha, ativação das quatro contas preservadas, recarga de sessões e aprovação/bloqueio em navegadores.
2. E2E completo das funções por papel: coroinha, pai, coordenadora e desenvolvedor; escalas, presença, PDF, notificações, relatórios, auditoria e suporte.
3. Nova implantação de preview na Vercel com o commit final da migração, testes em iOS/Android/PWA.
4. Entrega de push para um dispositivo de teste autorizado. O dispatcher está desativado por padrão e não envia aos usuários reais; o worker de produção ainda requer configuração, autorização e homologação separadas.
5. Execução de ensaio de sincronização com duas conexões privadas, snapshot de backup, janela de manutenção, sincronização após congelar escritas e comprovação de rollback com dados alterados no destino.
6. Investigação formal da quinta identidade de teste `migration-probe-20261106@example.invalid`, preservada e sem vínculo.
7. Atualização da branch principal e publicação de produção **somente** mediante autorização explícita do responsável.

**Decisão:** trabalho SQL/código/auditoria realizável diretamente no Chat entregue; **Neon NÃO APTO para substituição oficial até os testes acima**. Não publicar nem realizar cutover automaticamente.
