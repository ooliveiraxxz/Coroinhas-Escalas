# Política oficial de atualização — Escala São Bento

**Aprovada em 13/11/2026.** Esta política governa alterações futuras no aplicativo.

## Ambientes
- **Produção (oficial):** projeto Vercel `coroinhas-escalas`, branch GitHub `main`, banco Neon de produção. Exclusivamente para usuários reais. Não utilizar para testes fictícios.
- **Homologação (testes):** projeto Vercel `escala-sao-bento-homologacao`, branch `homologacao/permanente`. Destina-se a testar alterações **antes** do lançamento. Deve usar banco e autenticação exclusivos, com dados fictícios. Nunca utilizar as credenciais ou o banco oficial para testes de escrita.

## Processo obrigatório
1. Implementar alterações fora da `main`, com Pull Request.
2. Integrar a alteração na homologação e publicar uma URL de teste, com banco isolado devidamente configurado.
3. Testar instalação, login, permissões, funções afetadas, dados, acessibilidade, celulares e erros; registrar resultado.
4. Apresentar a URL e as mudanças ao responsável para avaliação.
5. **Somente após aprovação explícita do responsável para publicar aquela atualização específica**, realizar a migração de banco de produção (se necessária), o merge/deploy oficial e a verificação pós-lançamento.
6. Em caso de falha, não publicar. Preparar correção e nova prévia. Manter possibilidade de reversão.

## Regras de segurança
- Aprovar uma **política de trabalho** não equivale a aprovar o **lançamento de uma atualização**.
- Nunca compartilhar dados reais de usuários, sessões, senhas ou tokens com a homologação.
- Não transferir backups, contas ou dados sensíveis da produção para testes sem autorização específica.
- Evitar qualquer ligação da homologação ao banco de produção; antes de criar usuários e efetuar gravações, confirmar isolação de DB/Auth.
- Não executar migrações destrutivas ou mudar configurações de produção sem consentimento específico e verificação prévia.
- Mesmo depois de build `READY`, testes funcionais e aprovação continuam necessários.
- Os avisos pop-up com imagem na PR #4 permanecem pendentes de aprovação de lançamento e de migração correspondente.

## Situação em 13/11/2026
O projeto de homologação na Vercel e a branch permanente existem. Há uma **prévia visual isolada de pop-ups**, em `/homologacao`, que não publica avisos no banco. A **homologação funcional completa ainda não está pronta**: a criação de uma nova branch Neon foi bloqueada pelo limite de branches; as branches de ensaio existentes não têm a integração Neon Auth ativa. Não conectar essa estrutura ao banco oficial para contornar a pendência. É necessário solucionar autenticação e banco de testes antes de usá-la para testar escalas, login, notificações e outras operações reais.

## Diretriz de publicação
`Desenvolver → Prévia no ambiente isolado → Testes → Aprovação explícita → Produção → Verificação`
