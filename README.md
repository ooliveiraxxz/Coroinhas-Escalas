# Coroinhas — Next.js 4.0

## Publicar via GitHub/Vercel
1. Remova do repositório antigo os arquivos da versão HTML (`index.html`, `config.js`, `supabase-client.js`) e qualquer SQL antigo público.
2. Envie TODO o conteúdo desta pasta **para a raiz do repositório** (incluindo `app/`, `components/`, `lib/`, `package.json`, `tsconfig.json`, `next.config.ts`). NÃO envie o ZIP como arquivo único.
3. Em Vercel > projeto > Settings > General: Framework Preset `Next.js`; Root Directory `./`. Deixe Build Command padrão.
4. Em Settings > Environment Variables adicione:
   NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (valores copiados de `.env.example`).
5. Redeploy em Deployments > Redeploy com cache desmarcado (se necessário).
6. Antes de cadastrar coordenador, cadastre usuário no site; depois execute o UPDATE abaixo no SQL Editor do Supabase:

```sql
UPDATE public.profiles SET role='coordenadora',approved=true
WHERE email='santanalucas220210@gmail.com';
```

Este pacote usa a estrutura do banco Coroinhas V2 existente; não criar outro Supabase nem refazer tabelas.

## Nota
A impressão do navegador é o mecanismo atual de PDF; push quando fechado requer implementação futura. Cadastro pode requerer confirmação de e-mail. Não foi possível rodar npm install/build neste ambiente por indisponibilidade do registro de pacotes, então valide o resultado em Deployments / Build Logs da Vercel.
