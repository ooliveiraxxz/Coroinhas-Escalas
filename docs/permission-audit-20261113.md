# Revisão do catálogo de permissões — 13/11/2026

## Ajuste confirmado pelo responsável do sistema
A antiga tela **Mensagens** foi substituída pelo **Chat Rápido**. Portanto **não** adicionar as permissões `view_messages` e `mark_messages_seen`. Marcar como visto é uma operação normal de quem tem acesso à própria conversa ou notificação.

As propostas de interface, migração SQL e testes para as duas permissões obsoletas foram retiradas desta branch de QA. A branch oficial `main` nunca recebeu essas propostas.

**Atenção à homologação Neon:** duas chaves experimentais e uma política/funcão de mensagens antigas chegaram a ser aplicadas na branch isolada `br-dark-glitter-bc7e2ue1`. Reverter esses objetos experimentais na homologação antes de voltar a usar esta branch para testes de novas permissões; não propagar esse esquema ao banco oficial.

## Escopo correto da próxima auditoria
- Coroinha, Cerimoniário, Pai/Responsável, Coordenador(a), Desenvolvedor.
- Catalogar cada ação **ativa** desses perfis, suas regras de autorização no frontend e no Neon, e as opções exibidas em Permissões → Gerenciamento.
- Auditar o **Chat Rápido** atual: abertura, resposta, anexos, encerramento, arquivamento e acessos por destinatário. Não reintroduzir a antiga tela Mensagens.
- Verificar separadamente aprovações de cadastro, observações internas e as permissões de visualização (`view_scales`, `view_child_scales`).
- Não transformar ações básicas de leitura e marcação como visto em permissões administrativas.
- Não declarar testes E2E concluídos: ainda faltam sessões autenticadas dos cinco perfis no plugin de navegador.

## Estado
Revisão documental e código do menu original preservado; nenhuma mudança desta proposta publicada em produção.
