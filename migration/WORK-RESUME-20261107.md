# Continuação da homologação — 07/11/2026

**Status: NÃO LIBERADO PARA MIGRAÇÃO.** Este registro complementa e atualiza WORK-VALIDATION-20261107.md. Produção/main/domínio e dados do Supabase não foram alterados.

## Alterações desta rodada

- Versionada em SQL 017 a política requests_insert que já estava aplicada na homologação, mas não constava no último commit. Não foi reaplicada: o teste 018 executou contra a regra existente.
- Nova regressão SQL 018: pai aprovado e coroinha pendente não solicitam servir; coroinha aprovado solicita; pedido em nome de terceiro é rejeitado. Transação finalizada com ROLLBACK.
- Corrigido diagnóstico do sincronizador: modo somente leitura agora informa contagens por tabela de registros exclusivos do destino e sinaliza requiresConflictReview. Antes abortava sem emitir o plano quando encontrava fixtures. Modo de aplicação continua recusando conflitos antes de qualquer alteração de dados.
- Novo teste automatizado comprova que o relatório não modifica bancos nem expõe a credencial fictícia de teste.

## Validação executada

| Verificação | Resultado |
|---|---|
| npm ci | Aprovado, com aviso de peer dependency já existente |
| npm test | 39/39 aprovados |
| npx tsc --noEmit | Aprovado |
| npm run build | Aprovado |
| npm audit --omit=dev --audit-level=critical | Zero vulnerabilidades |
| security-tests.sql | Aprovado no Neon isolado, ROLLBACK |
| 011-critical-regression-tests.sql | Aprovado no Neon isolado, ROLLBACK |
| 015-server-assignment-tests.sql | Aprovado no Neon isolado, ROLLBACK |
| 016-auth-session-tests.sql | Aprovado no Neon isolado, ROLLBACK |
| 018-request-role-tests.sql | Aprovado no Neon isolado, ROLLBACK |
| 009-readonly-cutover-readiness.sql | static_checks_ok=true |
| Navegador na prévia 60c0e25 | Login, cadastro com dois papéis e recuperação renderizados; nenhum login autenticado nesta rodada |

As regressões SQL não equivalem a testes completos de navegador. Foram executadas pela conexão de ferramenta, com contexto de usuário e papel restrito onde previsto. Não comprovam isolamento concorrente de conexões HTTP.

## Estado real encontrado e preservado

- Homologação: 15 tabelas públicas com RLS, 33 políticas; 8 perfis (4 originais + 4 fixtures), 8 vínculos Neon, 9 identidades de autenticação, 1 identidade sem vínculo e 4 sessões ativas.
- Nenhum email divergente entre identidade e perfil; nenhuma inscrição push órfã; gateway sem superuser/bypassrls; zero jobs de push fora de suppressed.
- Os quatro usuários reais continuam sem senha no Neon (zero contas reais com password definido). As quatro contas com senha são fixtures.
- Homologação contém 350 registros públicos; Supabase contém 251. As diferenças e fixtures anteriores não foram apagadas.
- A comparação por coluna dos quatro perfis originais confirmou identidade, nome, email, papel, aprovação, preferências, foto, notas e criação preservados. A diferença para a origem está em last_seen_at.
- As verificações com ROLLBACK não devem alterar conteúdo persistido, mas sequências podem consumir números.

## Recuperação existente

Confirmada a branch restore-rehearsal-coroinhas-20261107 (br-ancient-dust-bcespekt), filha do backup br-hidden-haze-bcuoq602, no LSN 0/1DD8208.
A leitura de suas 15 tabelas foi bem-sucedida: 251 registros. Comparação atual com Supabase: 14/15 checksums iguais; profiles difere apenas em last_seen_at.
Isso confirma leitura da cópia histórica, não comprova restauração integral da origem Supabase, de Auth/configuração ou todos os fluxos da aplicação.

## Bloqueios para o próximo passo

1. Ativar e testar login dos quatro titulares reais, com participação dos titulares e recuperação segura; nenhuma senha ou reset real alterado/enviado.
2. E2E autenticado no navegador para todos os papéis, recuperação e cookies/revogação; PDF em iPhone/Android.
3. Push real em inscrição de teste consentida; dispatcher/ativação de produção ainda pendentes. Nenhum envio realizado.
4. Conexão direta ao Postgres Neon falhou no executor com EAI_AGAIN. O conector SQL funciona; isso não torna o ensaio do CLI com duas conexões aprovado. A conexão somente leitura da origem também não foi disponibilizada ao CLI.
5. Reconciliar fixtures/diferenças por plano revisado antes da sincronização final. Não apagar automaticamente registros exclusivos.
6. Backup restaurável da origem Supabase e ensaio integral de recuperação; a cópia Neon histórica não substitui esse requisito.
7. Autorização expressa para o corte somente após aprovação dos portões.

## Referências

- Branch de código: migration/neon-20261106; base desta rodada: 9a3c9d359800d16b220a4896b292599d69abb93a.
- Neon autorizado: noisy-hill-07078359 / br-rough-hill-bcj6lzt1 / coroinhas.
- Prévia conferida: https://coroinhas-escalas-lyjyyl4hf-ooliveiraxxz.vercel.app/
- Nenhum novo deployment é necessário para estas alterações de scripts/testes/documentação; código da aplicação permanece 60c0e25.

