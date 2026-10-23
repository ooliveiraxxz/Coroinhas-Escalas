# Coroinhas — Next.js

Projeto mobile para coroinhas e coordenação. Next.js + React + TypeScript + Supabase.

## Publicação

1. No repositório GitHub `Coroinhas---Escalas`, exclua os arquivos antigos `index.html`, `config.js` e `supabase-client.js`. Coloque **todos os arquivos e pastas deste ZIP** na raiz do repositório (não faça upload da pasta que contém os arquivos como uma subpasta).
2. Na Vercel, em Project Settings > Build and Deployment, o framework deve ser **Next.js**, diretório-raiz `./`. Se estiver como Other, altere para Next.js e faça Redeploy.
3. A conexão com o Supabase já usa o URL e a chave pública existentes como padrão. Para mudar, defina `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` nas variáveis de ambiente da Vercel.
4. No Supabase, mantenha o SQL da V2 que você já executou. Se ainda não rodou, execute o SQL de atualização integral enviado diretamente na conversa (não tente executar o ZIP no SQL Editor).
5. Cadastre o usuário no site e depois altere `role` e `approved` no SQL Editor, conforme os comandos enviados.

## Limites do protótipo funcional

- Notificações ficam dentro do site; push no telefone fechado exige implantação posterior.
- PDF usa Imprimir / Salvar como PDF do navegador.
- Escala automática preenche vagas existentes quando regras e missa coincidem; a coordenadora pode revisar.
- Ainda requer testes integrados no Supabase e na Vercel; não considerar homologado para produção.
