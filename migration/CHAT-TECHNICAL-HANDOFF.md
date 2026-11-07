# Conclusão da auditoria técnica via Chat — 07/11/2026

**Escopo:** apenas GitHub `migration/neon-20261106` e Neon `migration-coroinhas-20261106` (`br-rough-hill-bcj6lzt1`). Supabase `dsglwwwwdtjynipauvrp` consultado SOMENTE em leitura. `main` e implantação de produção NÃO alteradas.

## Resultados confirmados

1. **Identidade e sessão:** 5 contas no Neon Auth, 4 mapeadas para os 4 perfis originais, zero conflitos de e-mail e uma conta de sondagem sem perfil/sessão ativa. A função privada rejeita sessões inexistentes e contas bloqueadas.
2. **Revogação:** `public.developer_manage_user` foi reforçada para expirar sessões Neon Auth ativas em caso de banimento **e alteração de papel**, além de bloquear a conta e registrar o e-mail banido. Ambas as operações foram testadas com fixture realista de Neon Auth em transações revertidas (nenhum teste persistido). SQL: `migration/sql/012-revoke-neon-sessions-on-user-management.sql`.
3. **Estrutura:** 15 tabelas com RLS, 33 políticas, 32 índices, 17 gatilhos, 21 funções públicas adaptadas, nenhuma chave push órfã e fila push sem envios liberados. `migration/sql/009-readonly-cutover-readiness.sql` retornou `static_checks_ok=true`, o que **não** prova prontidão de lançamento.
4. **Dados:** comparação de conteúdo direta entre origem e destino: 251 linhas públicas em cada; checksums idênticos em 14/15 tabelas. Em `profiles`, 9 de 10 campos coincidem: única diferença é `last_seen_at`, volátil. Nenhuma perda de registro detectada nesta amostra temporal. A sincronização FINAL ainda depende de congelamento de escritas.
5. **Consultas e APIs:** compatibilidade avaliada contra os métodos realmente usados em `components/System.tsx` (SELECT, filtros de igualdade/nulo, ORDER, LIMIT, INSERT, PATCH, DELETE, upsert, RPC, `single` e `maybeSingle`). O compilador rejeita nomes de tabelas/colunas/RPCs fora de lista, operadores não suportados, parâmetros duplicados, filtros suspeitos e chaves de conflito sem constraint PK/UNIQUE. Os testes de regressão estão em `tests/neon-query.test.ts` e `tests/neon-app-compat.test.ts`; certos fluxos da biblioteca ainda exigem navegação E2E.
6. **Funções e gatilhos:** permissões de chamadas privilegiadas revisadas; notificações de sugestões para coordenadora, auditoria de mensagens, regras de escalas e aprovações válidas/inválidas testadas com rollback. SQL de proteção a substituições: `migration/sql/010-service-request-guards.sql`.
7. **Push:** integridade referencial restaurada de `push_subscriptions` para `profiles`. Fila registrada com `suppressed` e sem dispatch em homologação. Diagnóstico read-only `migration/push-readiness.mjs`; não envia notificações. O worker real, preferências de entrega e retentativas **não estão homologados** e ficam bloqueados até teste controlado em dispositivo e configuração segura.
8. **Sincronização:** `migration/sync.mjs` exige branch específica e dois endereços privados, recusa exclusão silenciosa, opera somente leitura por padrão e reserva escrita para execução manual separada com `--apply --confirm-isolated-neon`. Execução direta ponta-a-ponta ainda depende de credenciais privadas e aprovação de uma janela. Não incluir conexão administrativa no site/Vercel.
9. **Dependências e build:** jsPDF atualizado e travado na versão 4.2.1 **apenas na branch experimental**. CI da branch passou instalação, `npm audit` sem vulnerabilidades detectadas, **27 testes automatizados aprovados**, TypeScript e build Next.js. Execução documentada: [GitHub Actions 42389234642](https://github.com/ooliveiraxxz/Coroinhas-Escalas/actions/runs/42389234642).
10. **Vercel:** variáveis Neon estão presentes apenas para Preview da branch de migração; segredos não inspecionados. Deploy de homologação READY disponível ainda referencia o commit antigo `6355e2d`, **não** contém as últimas correções. Produção continua na `main` usando Supabase.
11. **Reversão e troca:** `migration/CUTOVER-CHECKLIST.md` documenta pré-requisitos, congelamento de escritas, backup e conciliação reversa (não trocar somente a URL após escrita no Neon).

## Pendências EXTERNAS / de execução operacional (não validadas aqui)

- Cadastro, login, recuperação, aprovação e logout reais com quatro usuários antigos e contas pendentes, incluindo ativação de senhas.
- Identificação/confirmação final da quinta conta de sondagem sem removê-la automaticamente.
- Testes completos de navegador e aparelhos (escalas, PDF, presença, mensagens, relatórios, configurações e papéis).
- Configuração de envio seguro de e-mail e push com consentimento; teste controlado de inscrição e entrega.
- Preview atualizado na Vercel e homologação funcional do commit exato.
- Ensaio do sincronizador com conexões privadas, backup restaurável, verificação de última alteração e execução final com aprovação explícita.
- Decisão humana de lançamento e eventual promoção para produção.

**Decisão: migração NÃO APTA para substituição definitiva.** As verificações de banco, código e testes automatizados que puderam ser executadas diretamente via Chat estão concluídas; isso não é aprovação E2E nem autorização para cutover. Não apagar a origem.
