# Escalas São Bento — homologação isolada (14/11/2026)

## Identificação e isolamento
- Aplicativo oficial: projeto Vercel `coroinhas-escalas`, banco Neon `noisy-hill-07078359`. **Não escrever na produção sem autorização específica.**
- Homologação: projeto Vercel `escala-sao-bento-homologacao`.
- Banco independente: Neon `falling-dawn-14662789`, branch `br-silent-firefly-be780j5s`, database `coroinhas`.
- Neon Auth independente provisionado neste banco de testes.
- Não houve cópia de contas, credenciais, escalas, mensagens ou outros registros reais.

## Clonagem de estrutura executada apenas no banco de homologação
- 31 tabelas de aplicação equivalentes às do oficial, além da tabela própria `qa_test_results`.
- 105 funções públicas do oficial copiadas; permanece 1 função própria de QA.
- 37 políticas RLS copiadas e RLS habilitado nas tabelas.
- 30 gatilhos oficiais equivalentes, além de 1 gatilho próprio de QA.
- 72 índices oficiais equivalentes, além de índice próprio de QA.
- 1 visualização pública (`profile_directory`).
- Constraints de PK, UNIQUE, CHECK e FK, além dos grants de tabelas e funções.
- 6 tabelas do schema privado copiadas estruturalmente, sem dados.
- Função `auth.uid()` alinhada ao contexto `app.user_id`.
- A função privada `resolve_neon_identity` recebeu o branch ID isolado.

## Atualização — homologação publicada e login disponível
- Deploy de homologação Vercel pronto: https://escala-sao-bento-homologacao.vercel.app
- Projeto Neon QA: `falling-dawn-14662789`, banco `coroinhas`, branch `br-silent-firefly-be780j5s`.
- Gateway QA `coroinhas_qa_gateway` provisionado com acesso restrito ao banco QA, associado ao papel `coroinhas_app`; sem superuser ou bypass RLS.
- Variáveis de homologação configuradas, incluindo URL restrita do banco, Neon Auth independente, cookie secret, `NEON_MIGRATION_ENABLED=true`, `NEON_PRODUCTION_CUTOVER_ENABLED=true` apenas no projeto QA; envio de push externo desabilitado.
- SQL `093-direct-self-service-claim.sql` aplicado somente ao Neon QA. RPC `claim_service_slot` liberada na lista explícita de chamadas do backend de QA.
- Build do commit `24827e5` concluído em READY. Login/cadastro visualizado em navegador, API de perfis respondeu 401 sem sessão (controle esperado).
- A Vercel mantém a proteção de autenticação nas prévias; endereço principal de homologação pode ser aberto normalmente.
- Existem cinco perfis fictícios, 10 missas, 11 vagas no banco QA; **nenhuma conta Neon Auth criada** até a validação. Cadastro cria usuário pendente, sujeito a aprovação (igual ao original).
- Pendências: realizar cadastro/login real de teste e fluxo completo de coordenação, corrigir diferenças de perfis QA, validar notificações e todos os papéis. Não afirmar paridade funcional completa ainda.
- Banco oficial, produção Vercel e `main` não foram modificados.

## Pendências antes de liberar a homologação
1. **Gateway restrito:** o código exige usuário Postgres `coroinhas_gateway` com senha. A tentativa de configurar a senha foi bloqueada pelo serviço, e a alternativa de reset retornou que a função não aceita reset para papel sem senha. A variável `NEON_MIGRATION_DATABASE_URL` da Vercel de homologação foi deixada deliberadamente em um valor inválido, sem credencial proprietária.
2. **Cookie de autenticação:** `NEON_AUTH_COOKIE_SECRET` próprio da homologação já configurado na Vercel, armazenado como variável criptografada.
3. **Acesso:** `NEON_MIGRATION_ENABLED=false` deve permanecer até os testes de segurança e autenticação; não habilitar no projeto oficial.
4. **Diferença histórica de dados fictícios:** cinco perfis antigos em QA têm `coordination_group` nulo; não preencher automaticamente com o grupo errado.
5. **Paridade em runtime:** conferir regras de permissão, notificações, anexos, jobs, tela de login, variáveis de push e fluxo de inscrições.
6. **Nova funcionalidade:** branch de `Quero servir` implementada, mas SQL `093` ainda requer teste de integração no banco isolado.
7. **Dados:** usar usuários e missas exclusivamente fictícios.

## Regra de publicação
Nada da homologação entra na `main` ou nos serviços oficiais sem aprovação explícita e específica do responsável. Verificar banco, projeto e branch antes de qualquer operação.
