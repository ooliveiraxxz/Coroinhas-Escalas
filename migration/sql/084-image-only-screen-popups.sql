-- Permite pop-up com imagem, título ou mensagem isolados, ou combinados.
-- Mantém os limites de 160 caracteres no título, 4000 na mensagem
-- e proíbe pop-ups completamente vazios.
BEGIN;
ALTER TABLE public.screen_announcements
 DROP CONSTRAINT screen_announcements_title_check,
 DROP CONSTRAINT screen_announcements_body_check;
ALTER TABLE public.screen_announcements
 ADD CONSTRAINT screen_announcements_title_check
 CHECK (
   length(btrim(title)) <= 160
   AND (length(btrim(title)) >= 1 OR length(btrim(body)) >= 1 OR image_url IS NOT NULL)
 ),
 ADD CONSTRAINT screen_announcements_body_check
 CHECK (
   length(btrim(body)) <= 4000
   AND (length(btrim(body)) >= 1 OR length(btrim(title)) >= 1 OR image_url IS NOT NULL)
 );
COMMIT;
