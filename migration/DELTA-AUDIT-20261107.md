# Auditoria incremental: Supabase oficial x Neon de homologação
Data: 07/11/2026. Ambas consultas foram SOMENTE LEITURA. Resultados não são um snapshot simultâneo; a produção pode receber novas escritas.

## Comparação de PK e conteúdo
- 15 tabelas públicas auditadas, com chaves primárias reais (incluindo chave composta de dismissals).
- Origem Supabase: **251** linhas; destino Neon: **350**.
- **100 linhas apenas no Neon** (não excluir automaticamente; investigar fixtures/dependências).
- **1 linha apenas no Supabase** (novo registro de `audit_log`; preservar e importar somente na sincronização planejada).
- **1 linha com PK em ambos mas valores diferentes:** um dos quatro perfis originais, exclusivamente o campo volátil `last_seen_at`.
- Todos os demais registros compartilhados têm hashes de conteúdo iguais neste momento.

| Tabela | Supabase | Neon | Apenas Neon | Apenas Supabase | Conteúdo divergente |
|---|---:|---:|---:|---:|---:|
| profiles | 4 | 8 | 4 | 0 | 1 (somente last_seen_at) |
| masses | 3 | 5 | 2 | 0 | 0 |
| assignments | 9 | 12 | 3 | 0 | 0 |
| requests | 3 | 4 | 1 | 0 | 0 |
| notifications | 14 | 41 | 27 | 0 | 0 |
| messages | 0 | 1 | 1 | 0 | 0 |
| guides | 5 | 5 | 0 | 0 | 0 |
| fixed_rules | 0 | 0 | 0 | 0 | 0 |
| site_updates | 6 | 7 | 1 | 0 | 0 |
| audit_log | 164 | 223 | 60 | 1 | 0 |
| banned_emails | 0 | 1 | 1 | 0 | 0 |
| login_events | 38 | 38 | 0 | 0 | 0 |
| push_subscriptions | 1 | 1 | 0 | 0 | 0 |
| screen_announcements | 2 | 2 | 0 | 0 | 0 |
| screen_announcement_dismissals | 2 | 2 | 0 | 0 | 0 |

## Implicações para sincronização final
- Não executar `--apply` no destino misturado: ele tem registros adicionais de teste. O sincronizador foi projetado para recusar conflitos/exclusões silenciosas.
- Uma cópia isolada limpa da origem, ou limpeza exclusivamente de fixtures comprovadas em branch de ensaio após backup, é necessária antes do sync final.
- A sincronização deve trazer o audit_log novo e reconciliar `last_seen_at` segundo a fonte autoritativa, preservando a ordem das alterações.
- Obter snapshot consistente após congelamento de escritas; repetir integralmente comparação de hashes por tabela e identidade.
- Não usar a quantidade líquida +99 para apagar 99 registros indiscriminadamente: há **100 exclusivos do destino e 1 exclusivo da origem**.

## Outros resultados desta execução
- Push SQL 020 instalado e desativado; SQL 021 e 022 aprovados (0022 é transação revertida).
- CI `42424027358` aprovado na revisão `9502c1f2e2c0ca3e4fb5b9501cc9eafe74251ade`.
- Preview READY `dpl_D2XBheuFS5rSxd5ZtbBu4t795wPE`: https://coroinhas-escalas-4rf2b2htj-ooliveiraxxz.vercel.app
- Produção `main`, Supabase oficial e domínio não alterados.
