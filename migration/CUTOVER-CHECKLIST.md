# Plano de substituição Supabase → Neon — NÃO EXECUTADO

**Status:** bloqueado, sem autorização para produção. Data-base: 07/11/2026.
**Origem oficial:** Supabase `dsglwwwwdtjynipauvrp`.
**Destino de ensaio:** Neon `noisy-hill-07078359` / `br-rough-hill-bcj6lzt1`.
**Código de ensaio:** GitHub `migration/neon-20261106`.
**Código oficial:** GitHub `main`; não modificar antes da autorização.

## Portões obrigatórios (todos devem passar)

- [x] Revisão de GitHub CI: `npm ci`, `npm test`, `npx tsc --noEmit`, `npm run build` na revisão `ea4de3e7049d` (52/52 testes); repetir no SHA da publicação final.
- [x] Preview isolado READY no commit `4c2830bc537e`; os commits posteriores até `ea4de3e7049d` alteraram somente SQL/documentação; `main` e produção preservados.
- [ ] Neon Auth testado com conta nova, conta pendente, aprovação, bloqueio, logout, revogação e recuperação segura de senha.
- [ ] Todos os quatro usuários antigos (1 desenvolvedor, 3 coordenadoras) conseguem autenticar e conservar os **mesmos profile UUIDs**.
- [x] Homologação mantém 10 usuários Neon Auth com contas de teste. Somente 4 contas originais reais mapeadas; os perfis fictícios não serão promovidos nem migrados automaticamente para produção.
- [ ] Testes de acesso indevido (IDOR), RLS e permissões por coroinha, pai, coordenadora e desenvolvedor.
- [ ] Testes de criação/edição/exclusão lógica de escalas, confirmação no dia, desmarcação, justificativa, presença e substituição.
- [ ] Relatórios, PDFs no iPhone e Android, avisos, mensagens e auditoria testados.
- [ ] Push em domínio de homologação, com inscrição **nova** e destinatário que consentiu em receber teste; nenhuma entrega de homologação aos usuários reais.
- [x] Privilégios mínimos do gateway conferidos: sem BYPASSRLS, papel sem privilégios de owner e com tabelas privadas negadas; segredos privados exclusivamente no servidor.
- [x] Auditoria referencial `034` aprovada nas duas branches isoladas: nenhum vínculo órfão nas relações críticas. Conferidos 15/15 hashes lógicos entre origem e branch limpa; o conflito histórico permanece arquivado com revisão explícita. A sequência PK foi validada no ensaio anterior.
- [ ] Ensaio do sync validado em modo somente leitura (`node migration/sync.mjs`), diferenças explicadas.
- [ ] Backup lógico/snapshot verificável da origem, registro de revisão e plano de recuperação antes de qualquer escrita.
- [ ] Aprovação explícita do responsável para interromper escritas e executar o cutover.

## Preparação ANTES da janela de troca

1. Registre commits/versões e URLs exatas de origem e destino; nenhuma substituição de domínio sem confirmação.
2. Confirme backup restaurável, tamanho, checksums e prazo de retenção. Mantenha origem operante.
3. Valide todas as contas já ativadas e suas vinculações com prova de identidade. Hashes/senhas não são migrados automaticamente.
4. Execute auditoria read-only; ajuste diferenças no ensaio, sem excluir ou sobrescrever silenciosamente registros exclusivos.
5. Configure URLs, Neon Auth, cookies, gateway limitado e push na configuração do ambiente isolado; não copie chaves de produção no repositório.
6. Congele mudanças relevantes no código; registre os testes e seu commit. Confirme aprovação específica antes de efetuar a troca.

## Janela de substituição — somente se AUTORIZADA

1. Comunique manutenção aos usuários e **interrompa novas escritas** no Supabase; não basta trocar URL enquanto usuários escrevem.
2. Capture snapshot final e inventários de referência; registre o último identificador de login/auditoria.
3. Rode sincronização final auditada para destino preparado, compare **checksums de todas as tabelas** e verifique sessões/perfis.
4. Confirme RLS, credenciais restritas, autenticação, funções e notificações isoladas no destino.
5. Publique apenas a revisão aprovada e altere somente as variáveis/direcionamento autorizado da Vercel.
6. Faça smoke tests no domínio oficial: login de cada papel, permissão de pendentes, criação de escala, PDF, mensagens e relatórios.
7. Libere gradualmente escritas; monitore erros, auditoria, duplicações e entrega de notificações.

## Critérios de ABORTAR

- Falha de build, sessão, autorização, comparação de dados ou novo cadastro.
- Perda de identificadores ou vínculos dos quatro usuários originais.
- Mais de uma origem recebendo escritas sem conciliação controlada.
- Dependência não resolvida de armazenamento, push ou funções críticas.
- Falta de backup verificável ou autorização específica para a mudança.

## Plano de reversão — cuidados

- **Antes de liberar escritas no Neon:** retornar à implantação antiga do Supabase pode ser feito sem reconciliação de novos dados, desde que não tenham ocorrido escritas no destino.
- **Depois de liberar escritas no Neon:** NÃO aponte simplesmente de volta ao Supabase; isso causaria perda das alterações feitas no Neon. Interrompa escritas novamente, extraia um delta auditável do Neon e reconcilie com a origem antes do retorno.
- Preserve logs, backups, identidades e histórico. Não execute `DROP`, `TRUNCATE`, limpeza de contas nem cascatas destrutivas como técnica de rollback.

## Ferramentas preparadas

- `migration/sql/009-readonly-cutover-readiness.sql`: inventário estrutural de homologação (não prova E2E).
- `migration/sync.mjs`: **somente leitura por padrão**; modo de escrita exige `--apply --confirm-isolated-neon` e credencial administrativa exclusiva da branch experimental.
- `.github/workflows/neon-migration-validation.yml`: pipeline CI sem segredos, sem publicação.
- `migration/README.md`: histórico de verificações, diferenças e bloqueios.

**Decisão atual:** NÃO APTO PARA SUBSTITUIÇÃO FINAL.

## Atualização de engenharia — 07/11/2026

- [x] Portão de produção fail-closed no código: `NEON_PRODUCTION_CUTOVER_ENABLED=true` + `NEON_PRODUCTION_APPROVED_COMMIT` deve ser igual a `VERCEL_GIT_COMMIT_SHA`; nenhum flag ativado em produção.
- [x] Implementação do worker push Neon, endpoint protegido por CRON_SECRET, SQL 020 instalado, testes SQL 021/022 aprovados com rollback e testes automatizados de código aprovados.
- [x] Preview atualizado e CI aprovado em `9502c1f2`. Auditoria incremental de 15 tabelas e conteúdo em `migration/DELTA-AUDIT-20261107.md`.
- [x] Divergências antigas de 100 registros e `last_seen_at` foram isoladas/removidas do conjunto ativo por cópia limpa. Auditoria read-only de 15 tabelas em 07/11 confirmou **251/251 registros lógicos e 15/15 hashes iguais**; 1 `site_update` historicamente excluído na origem foi preservado no arquivo privado e continua fisicamente na cópia limpa. Não houve remoção em massa.
- [ ] Habilitar credencial de login dedicada `coroinhas_push_worker` e configurar agendador e VAPID *somente após corte aprovado*. O worker permanece NOLOGIN e runtime `enabled=false` até então.
- [ ] Testar envio opt-in em dispositivo real e repovoar assinatura após ativação; inscrições antigas copiadas ficam intencionalmente fora do envio.
- [ ] Validar os quatro logins originais (0/4 senhas Neon ativadas na auditoria de 07/11). **Implementado:** login por magic link de 10 minutos, só para contas existentes; exige ação do titular e teste de sessão real.
- [ ] Repetir CI no SHA exato da implantação final, executar E2E e ensaio real de sync + backup/restauração antes do cutover.

**Status permanece NÃO APTO para trocar produção sem concluir as pendências acima e receber autorização expressa.**

## Auditoria final técnica — 07/11/2026 (homologação)

- `migration/sql/038-staging-final-readiness-audit.sql`: executado com `staging_security_gates_pass=true`. Neon staging: 33 políticas, 15 tabelas com RLS, quatro perfis originais aprovados e vinculados, nenhum órfão nos dois tipos verificados, papel push NOLOGIN, gateway sem BYPASSRLS, 0 envio push.
- `migration/sql/034-referential-integrity-gates.sql` e `035-role-matrix-rollback-tests.sql`: executados com sucesso nas duas branches; pai e pendente não podem solicitar, coroinha aprovado pode em escala futura publicada, e-mails de terceiros mascarados.
- Supabase (fonte) vs branch Neon limpa: **15/15 checksums iguais em 251 linhas lógicas** na consulta de 07/11. A exclusão histórica no Neon permanece arquivada e protegida; **igualdade lógica não significa sincronização final atômica**.
- Backup/restore do **Neon**: branch limpa `br-odd-bread-bc1jxzsh` → backup `br-lucky-pine-bcf4h6hn` → restauração `br-plain-hill-bcukew31`: 15/15 hashes e 252/252 linhas físicas iguais; mesmas 33 políticas e identidades. **Não substitui backup completo do Supabase**.
- Auth hashes: Supabase 4 bcrypt `$2a$` (60 chars); Neon Auth gerenciado atualmente usa scrypt (161 chars). Não copiar hashes diretamente. Magic link e redefinição individual preparados; 0/4 provas de login reais.
- **Bloqueios não simuláveis:** exportação/restauração íntegra da origem Supabase (incluindo Auth); acesso PostgreSQL read-only da origem para sync por TCP; E2E real no browser; consentimento/teste push; ativação dos quatro titulares; aprovação explícita de cutover e congelamento de escritas.

## Retomada de 08/11/2026 — evidências HTTP

Código `ca29537f`: 53/53 testes, TypeScript, build e audit sem vulnerabilidades; preview READY. Quatro papéis autenticados pela API real, isolamento de função administrativa e logout validados. CRUD de escala fictícia, presença/falta e revogação por papel/banimento aprovados. Comparação renovada: 15/15 hashes lógicos, 251 registros. Ver [WORK-HTTP-VALIDATION-20261108.md](WORK-HTTP-VALIDATION-20261108.md).

Os itens amplos de Auth, interface, PDFs, push, sincronização e backup continuam abertos: a evidência parcial não equivale a aprovação integral. Nenhuma autorização de produção foi solicitada ou presumida.
