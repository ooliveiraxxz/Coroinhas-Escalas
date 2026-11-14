# Escalas São Bento — Homologação Isolada

**Data:** 14/11/2026
**URL:** https://escala-sao-bento-homologacao.vercel.app
**Vercel:** `escala-sao-bento-homologacao` (projeto separado do oficial).
**GitHub:** `teste/quero-servir-funcao-automatica-20261114` (base em `main`, sem commits pendentes do oficial na comparação).
**Neon QA:** `falling-dawn-14662789`, branch `br-silent-firefly-be780j5s`, banco `coroinhas`.
**Neon oficial:** `noisy-hill-07078359` — consultado somente em modo de leitura.

## Estrutura e isolamento
- Reprodução das 31 tabelas públicas, 105 funções públicas, 37 políticas de acesso, 30 gatilhos, 72 índices e view `profile_directory`; QA mantém objetos de teste adicionais.
- `permission_catalog` (27 linhas), `automation_catalog` (9 linhas) e `guides` (5 linhas) copiados como configuração pública, sem dados pessoais.
- Neon Auth exclusivo; conta gateway restrita `coroinhas_qa_gateway` sem superuser e sem BYPASSRLS; autorização SQL por `coroinhas_app`.
- Autenticação independente; chave de cookie própria. Push externo desabilitado em QA.
- Credenciais e cadastros reais NÃO foram copiados; os usuários e missas existentes em QA são fictícios.

## Testes concluídos com navegador real
- Login/cadastro de coroinha e aprovação: aprovado.
- Painel de coroinha, missas mensais e escolhas de função: aprovado.
- Inscrição automática em missa fictícia `Sem candidato`, função `Altar`: concluída sem aprovação da coordenação; status SQL `escalado` e escala visível no início.
- Desenvolvedor: login, métricas, gerenciamento de usuários e controles de permissões: abertura aprovada.
- Coordenadora: login, cadastro de escala (formulário), listagem de coroinhas, missas, PDFs e notificações: abertura aprovada, sem gravações para essas operações.
- Cerimoniário: login, tema preto/cinza/branco, escalas mensais, Quero servir: aprovado.
- Pai/responsável: login, painel próprio, opção de vínculo de coroinha e consulta de escalas: aprovado.
- Corrigidos privilégios de `migration_private.resolve_neon_identity` e SELECT em `public.profile_directory` após testes reproduzirem falhas 403. Confirmado login aprovado após correção.
- Cinco perfis fictícios antigos tiveram `coordination_group` preenchido pelo tipo, e coluna alinhada como NOT NULL ao original.

## Diferenças intencionais e pendências
- Dados, contas e segredos são próprios do ambiente QA; não são nem devem ser iguais aos registros oficiais.
- Código QA contém além do código da main a mudança experimental no `Quero servir`, o gateway QA e diagnósticos de erros de backend. Nada disso foi aplicado ao oficial.
- Não foi concluída auditoria de TODOS os botões, envio de push real, anexos, concorrência nem todos os fluxos de coordenação e desenvolvedor; só os caminhos descritos acima foram efetivamente testados.
- A homologação usa config QA e permite experimentar sem afetar produção. Atualizações de código para publicação oficial dependem de autorização EXPRESSA.
