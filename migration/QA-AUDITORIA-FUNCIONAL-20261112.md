# Auditoria funcional — Escala São Bento — 12/11/2026

## Escopo e isolamento
- Referência: `main` no commit `6b27b33e5436aa6aa3c8be9cf22da2642731b41f`.
- Alterações exclusivamente na branch `qa/auditoria-funcional-20261112`.
- Banco sintético: projeto Neon `falling-dawn-14662789`, branch `br-silent-firefly-be780j5s`, banco `coroinhas`.
- O banco sintético foi criado vazio e possui um subconjunto de tabelas e funções de produção para testes específicos. **Não equivale ao ambiente completo da aplicação.**
- Produção Neon `noisy-hill-07078359` / `br-rough-hill-bcj6lzt1` utilizada **apenas em consultas de leitura**; `main` preservada.

## Correções preparadas na QA
1. `migration/sql/078-poll-closure-visibility.sql`: fecha a exposição de perguntas, opções e votos particulares após `closed_at`, preservando a visão administrativa.
2. `migration/sql/079-immediate-withdrawal-succession.sql`: preenchimento imediato de vaga desmarcada pelo primeiro pedido elegível, sem duplicar integrantes, respeitando grupo, disponibilidade, estado de automação, data e lock por missa.
3. `migration/sql/080-withdrawal-notification-guard.sql`: impede o aviso de vaga livre quando a substituição já ocorreu na mesma transação.
4. `app/api/push/neon-dispatch/route.ts`: adiciona `Cache-Control: no-store` a respostas de push desabilitado/não autorizado.
5. `tests/neon-route.test.ts`, `tests/neon-push-route.test.ts`: testes atualizados para validar a regra **atual** de ativação privada, sem pinagem obsoleta de SHA.
6. `.github/workflows/neon-migration-validation.yml`: QA incluída na validação automática, com `npm test`, TypeScript e build.

## Banco QA: testes e evidências
- Substituição FIFO: atribuição fictícia A→B, status `escalado`, solicitação B `aprovado`, notificação `automatic_approval` persistida.
- Candidato de grupo inadequado descartado; pedidos elegíveis ordenados por `created_at,id`.
- Sem candidato: status permanece `desmarcado`.
- Automação desabilitada: não troca o integrante; pedido continua `pendente`.
- Missa passada: não atribui substituto.
- Função original `run_pending_auto_approvals()`: missa em 2h aprovada; missa em 5h pendente; execução repetida retornou 0.
- `poll_list()`: coroinha sem opções e resultados após fechamento manual; coordenadora com opções, votos e nomes.
- `poll_vote()`: rejeitou voto pós-fechamento com SQLSTATE 22023; rejeitou perfil inadequado com SQLSTATE 42501; contagem permaneceu inalterada.
- Trigger de proteção de grupo: bloqueou cerimoniário em vaga de coroinha.
- `respond_assignment()`: bloqueou desistência feita por outra pessoa.
- Desmarcação via RPC com sucessor disponível: vaga preenchida, pedido aprovado, nenhuma notificação falsa de `Vaga para substituição`.
- Desmarcação via RPC sem sucessor: vaga aberta, notificações de substituição registradas.
- Regressão após inclusão de lock por missa: A→B permaneceu funcional, pedido persistiu `aprovado`.
- Concorrência real: duas atualizações simultâneas em posições da mesma missa e um único candidato; somente uma posição recebeu o candidato, a outra ficou desmarcada e houve apenas uma solicitação aprovada.

## GitHub CI e Vercel
- GitHub Actions no commit `815b6434f7e008220e9ffedd08f861c0a5c2ade9`: 63/63 testes `npm test` aprovados; TypeScript, build e auditoria de dependências aprovados.
- GitHub Actions no commit `bef91afc3d0eb43d5f9ac56eb79c4ab774b7cfe5`: CI **SUCCESS**, incluindo `npm test`, TypeScript e build.
- Vercel preview desse commit: **READY**. Os testes no banco isolado não foram executados pela preview; foram realizados diretamente via SQL.
- Experimento `*/5 * * * *` no Vercel: falhou — plano Hobby limita agendamentos a uma vez por dia. Configuração foi revertida para `0 12 * * *`; a preview voltou a READY.
- Produção: Neon schedule `Aprovar solicitações 3 horas antes` segue desativado. **A correção de agendamento recorrente não foi concluída**. Requer implementação/ativação de um agendador compatível em ocasião aprovada e verificação observável de execução.

## Limitações explícitas
- Testes no banco QA cobrem funções/rotinas e persistência, não o navegador completo dos cinco perfis nem a autenticação integrada Neon Auth.
- Não foram executados carga, acessibilidade mobile, captura de push real, PDF consolidado, simulação mensal e cross-browser completos.
- Mudanças de schema foram aplicadas somente ao Neon sintético. Não foram aplicadas ao Neon de produção.
- Nenhum merge ou promoção para produção foi realizado.

## Portão de produção
**Ainda não aprovada**: falta agendador compatível efetivamente ativo, integração E2E com Neon Auth e regressão funcional completa nos perfis e fluxos críticos.