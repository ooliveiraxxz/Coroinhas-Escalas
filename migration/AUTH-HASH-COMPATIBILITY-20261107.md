# Compatibilidade de hashes Supabase → Neon Auth gerenciado — 07/11/2026

## Resultado da investigação executada, sem acessar hashes em texto
- Supabase oficial `dsglwwwwdtjynipauvrp`: **4/4** usuários têm `auth.users.encrypted_password` em bcrypt MCF `$2a$`, comprimento 60. Consultas SQL retornaram **somente totais e tipos**, nunca valores individuais, emails ou salts.
- No próprio Supabase foi testado bcrypt **com senha fictícia criada para o teste**: verificação correta = true; senha errada = false. Não foi tentada nenhuma senha real.
- Neon Auth staging `br-rough-hill-bcj6lzt1`: 10 contas de credencial, 5 com hashes compatíveis com o padrão de `scrypt` (`32 hex:128 hex`), 0 bcrypt. Os 4 perfis originais têm mapeamento de identidade consistente, mas 0/4 senhas Neon ativas.
- Better Auth padrão usa **scrypt**. Better Auth auto-hospedado permite implementar um verificador bcrypt customizado, mas o Neon Auth gerenciado executa o servidor e **não suporta atualmente trazer manipuladores customizados de servidor**. Fonte: https://neon.com/blog/neon-auth-branchable-identity-in-your-database ; https://better-auth.com/docs/guides/supabase-migration-guide
- Atenção: a postagem antiga do Neon sobre importação de hashes Supabase foi publicada para a geração **Stack Auth** (2025), não para a instância **Better Auth gerenciada** atualmente usada. Não copiar a instrução antiga `password_hash` da Stack para `neon_auth.account`!

## Decisão operacional segura

**NÃO importar hashes bcrypt diretamente para `neon_auth.account.password` no ambiente gerenciado atual.** Uma string bcrypt não é um hash scrypt válido: a autenticação por senha poderá falhar. Não existe conversão bcrypt→scrypt que preserve a senha sem a senha original, e isso não é descriptografia.

### Caminho já implementado e ativado na homologação
1. Os quatro perfis e identidades correspondem no Neon. Nenhum novo usuário precisa ser criado.
2. Neon Auth tem login por link de e-mail ativado **somente para contas existentes**, validade de 10 minutos, sem cadastro por link, e o botão já está no `components/NeonLogin.tsx`.
3. Cada titular solicita seu link na homologação e comprova o próprio e-mail; o servidor de migração só resolve o perfil quando a identidade autenticada corresponde ao mapeamento.
4. Se desejarem voltar a usar senha, cada titular configura sua senha no próprio Neon Auth via OTP/redefinição. **Pode escolher a mesma senha que já conhece**, sem revelar ao operador nem ao ChatGPT. A senha passa a ser armazenada em scrypt.
5. O Supabase de origem fica intacto até migração definitiva explicitamente aprovada.

### Alternativa arquitetural, NÃO implementada
Hospedar um Better Auth próprio, com verificação bcrypt para hashes antigos e rehash scrypt quando a pessoa autenticar com a senha correta. Exige substituir parte da infraestrutura auth atual, validação de sessões/cookies, proteção de importação de hashes e nova bateria E2E. Não foi autorizada mudança de identidade gerenciada para self-hosted; **não recomendar como pequeno ajuste**.

## Evidência repetível
- `migration/sql/036-supabase-bcrypt-format-audit.sql`: consulta somente leitura na origem com bcrypt sintético.
- `migration/sql/037-neon-managed-hash-format-audit.sql`: consulta somente leitura na branch de homologação mostrando apenas contagens de formatos.
- `migration/sql/033-original-auth-activation-check.sql`: vínculos e estado de ativação sem exibir dados de identificação.

**Resultado: a compatibilidade direta de formato foi refutada. O fluxo alternativo de ativação está preparado, porém os quatro logins reais ainda precisam ser realizados por seus titulares.**
