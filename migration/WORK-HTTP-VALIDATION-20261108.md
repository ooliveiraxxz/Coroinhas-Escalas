# Homologação HTTP real — 08/11/2026

Código testado: `ca29537fdbfba0ad7504a6eaf0e04f0168c98e2f`.
Preview READY: `dpl_EM3Pz9GKxRhK5ELKy8bXasqfAiHN`.
URL: https://coroinhas-escalas-ap8smg0x3-ooliveiraxxz.vercel.app

## Evidências desta retomada

- Código recuperado do HEAD remoto; nenhum arquivo da aplicação alterado nesta retomada.
- Instalação do lockfile (`npm ci --ignore-scripts`), 53/53 testes, TypeScript e build aprovados. `npm audit --json`: zero vulnerabilidades em todas as severidades.
- Quatro cadastros fictícios pelo Neon Auth através da aplicação: cadastro e provisionamento HTTP 200. Todos inicialmente pendentes. Aprovação/preparação de papéis feita pelo conector somente em staging.
- Quatro logins com senha e sessões reais: coroinha, pai, coordenadora e desenvolvedor. Perfil aprovado e papel correto lidos pela API.
- `developer_usage_summary`: 403 para coroinha, pai e coordenadora; 200 para desenvolvedor. Após logout, dados negados com 401 nos quatro papéis.
- Coordenadora: criação/edição de escala não publicada, criação de atribuição fictícia, presença, falta, exclusão da atribuição e da escala, seguida de consulta vazia. Todas as operações HTTP 200.
- Desenvolvedor: mudança de papel de conta fictícia revogou sessão (403); novo login refletiu papel pai. Papel restaurado para coroinha. Banimento revogou sessão (403). Conta sintética mantida banida como evidência, sem apagar histórico.
- SQL 011, 015 e 016 executados em transações com ROLLBACK: aprovação de solicitação válida, rejeição de vaga obsoleta/usuário pendente, proteção contra atribuição de pai, presença e expiração/revogação. SQL 035 executado com reversão interna das fixtures: pai e pendente negados, coroinha aprovado permitido, escala não publicada negada, dados privados mascarados.
- SQL 039 pós-testes aprovado: nenhum órfão/duplicidade, todas as tabelas públicas base com RLS, gateway/app sem BYPASSRLS, view com security_invoker, sem DELETE direto de profiles nem INSERT direto de audit_log. Push permanece desativado.
- Supabase e branch limpa `br-odd-bread-bc1jxzsh`: 251 registros lógicos e 15/15 checksums iguais na nova leitura. O registro histórico excluído na origem continua preservado no destino/arquivo; não afirmar identidade física.

## Fixtures desta rodada

| Papel inicial aprovado | UUID do perfil | Estado ao concluir |
|---|---|---|
| Coroinha | 3a0a4c64-0b93-4b15-9411-6bfd74043ec2 | Banido pelo teste autorizado |
| Pai | e4ed1254-bd59-4304-b942-413dc45683b9 | Aprovado, logout |
| Coordenadora | ad822359-1898-4cac-b85b-98c0f656edf9 | Aprovado, logout |
| Desenvolvedor | d06d3242-660b-48f2-8e1e-b63f2cc463d8 | Aprovado, logout |

Todos usam endereços `resume-...@example.invalid`. Nenhuma senha, cookie ou segredo integra este relatório. Os perfis anteriores `work-role-...` continuam preservados; suas credenciais temporárias foram perdidas com a expiração do executor anterior. Não recuperar senhas reais nem inventar aprovação de testes perdidos.

## Limites que continuam abertos

1. Testes acima são HTTP real, não navegador autenticado. PDFs individuais/mensais, download, compartilhamento, navegação mobile/PWA e matriz completa de mensagens, suporte, orientações e relatórios ainda não estão integralmente comprovados na UI.
2. Recuperação/redefinição de senha com entrega e consumo do e-mail não concluída. Quatro titulares originais preservados: 0/4 com senha credential no Neon. Ativação por magic link existente exige participação dos titulares; não houve envio a eles nesta execução.
3. Sem assinatura/dispositivo de teste com consentimento para entrega push; nenhum push enviado. Worker implementado, runtime desativado.
4. Conexão PostgreSQL do Supabase indisponível no executor: DNS retorna EAI_AGAIN (-3); SOURCE_READONLY_DATABASE_URL não fornecida. Ensaio real do sincronizador e backup completo/restauração Supabase continuam não comprovados. Comparação por conectores não substitui essas etapas. Necessário provisionar conexão privada apropriada em ambiente autorizado com rede PostgreSQL e acesso ao backup/configurações da fonte.
5. Backup/restauração Neon anteriores documentados não substituem backup integral Supabase.
6. Produção e main preservadas; corte não autorizado. Status continua NÃO APTO PARA SUBSTITUIÇÃO até completar os gates obrigatórios.

## Saídas HTTP sanitizadas

```jsonl
{"role": "pai", "login": 200, "approved_profile": true, "visible_masses": 5, "developer_rpc": 403}
{"role": "coordenadora", "login": 200, "approved_profile": true, "visible_masses": 5, "developer_rpc": 403}
{"role": "coroinha", "login": 200, "approved_profile": true, "visible_masses": 5, "developer_rpc": 403}
{"role": "desenvolvedor", "login": 200, "approved_profile": true, "visible_masses": 5, "developer_rpc": 200}
{"role": "coordenadora", "logout_protection": 401}
{"role": "pai", "logout_protection": 401}
{"role": "coroinha", "logout_protection": 401}
{"role": "desenvolvedor", "logout_protection": 401}
{"test": "coordinator_login", "status": 200}
{"test": "coordinator_session", "status": 200}
{"test": "create_scale", "status": 200}
{"test": "edit_scale", "status": 200}
{"test": "create_assignment", "status": 200}
{"test": "record_presente", "status": 200}
{"test": "record_faltou", "status": 200}
{"test": "delete_test_assignment", "status": 200}
{"test": "delete_test_scale", "status": 200}
{"test": "verify_deleted", "status": 200}
{"test": "coordinator_logout", "status": 200}
{"test": "role_change_revokes_session", "status": 403}
{"test": "changed_role_after_login", "status": 200}
{"test": "ban_revokes_session", "status": 403}
```
