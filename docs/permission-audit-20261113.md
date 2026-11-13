# Auditoria do Gerenciamento de Permissões — 13/11/2026

**Escopo:** revisão estática de componentes, catálogo e políticas Neon, com verificações no ramo de homologação `br-dark-glitter-bc7e2ue1`. Os cinco perfis são Coroinha, Cerimoniário, Pai/Responsável, Coordenador(a) e Desenvolvedor. **Não houve login via navegador:** o perfil de automação não contém sessão autenticada.

## Resultado verificado
- Catálogo oficial: 25 permissões antes desta revisão.
- Acréscimos apenas em homologação: `view_messages` (consultar mensagens de coordenação) e `mark_messages_seen` (marcar como vistas).
- Padrão destes dois controles: Coordenador(a) e Desenvolvedor. Demais perfis: desabilitados por padrão, podendo receber delegação explícita.
- Separação de permissões refletida no menu e no botão de marcar como visto.
- Política `messages_read` e função `mark_coordinator_message_seen` adaptadas no banco de homologação; não foram aplicadas ao banco oficial.

## Matriz de funções por perfil (código e catálogo, não execução E2E)
| Perfil | Principais funções | Observação |
|---|---|---|
| Coroinha | visualizar/confirmar/desmarcar escalas, solicitar vaga, notificações, enquetes, sugestões, suporte | Algumas áreas gerais não têm toggles individuais |
| Cerimoniário | funções equivalentes às de coroinha em grupo próprio; tema específico | Verificar segregação dos dois grupos no navegador e no RLS |
| Pai/Responsável | acompanhar escalas do filho vinculado, criar/desvincular vínculo, notificações, suporte | `view_child_scales` existe, mas nem todas as rotas e ações usam guarda explícita no front |
| Coordenador(a) | criar/editar/excluir escalas, confirmar presenças/faltas, aprovar, relatórios, mensagens, enquetes, usuários do grupo | `approve_requests` não é equivalente a aprovar cadastros; observações de perfil e caixa de mensagens exigem controles separados |
| Desenvolvedor | gerenciamento de usuários, auditoria, painel, publicações, pop-ups e permissões | As próprias contas de desenvolvedor não são selecionáveis no PermissionCenter; operação administrativa permanece reservada ao papel |

## Lacunas a investigar (NÃO marcar como corrigidas)
1. Aprovação de cadastro na tela de coroinhas/cerimoniários usa `coord`; ainda não há `approve_profiles` independente, com RPC protegida.
2. Edição de observações internas de perfil também não possui um toggle independente; exige coluna/política ou RPC que não permita alterar papel/aprovação por acidente.
3. `view_scales`, `view_child_scales` e `read_notifications` precisam de auditoria E2E em cada tela e na camada de dados, pois não aparecem sempre como guardas diretas nos componentes.
4. O controle do Painel de Permissões está restrito ao papel Desenvolvedor, inclusive nas chamadas administrativas — opção delegável exigiria nova política de segurança.
5. Gestão de suporte e atualizações de preferências individuais não devem ser transformadas automaticamente em privilégios administrativos; requerem regras específicas.

## Verificações pendentes
- Entrar nos cinco perfis com credenciais fictícias autorizadas, inspecionar todos os botões e respostas do servidor e conferir o estado após revogação.
- Executar verificações de build/TypeScript/testes no último commit desta branch.
- Revisar alteração de banco em homologação com contas de teste antes de decidir publicação.
