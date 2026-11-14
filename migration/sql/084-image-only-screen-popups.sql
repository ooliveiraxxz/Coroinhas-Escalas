-- Pop-ups podem conter apenas imagem, apenas mensagem ou apenas título.
-- Preserva limites existentes de caracteres e impede registros inteiramente vazios.
BEGIN;
ALTER TABLE public.screen_announcements
 DROP CONSTRAINT screen_announcements_title_check;
ALTER TABLE public.screen_announcements
 ADD CONSTRAINT screen_announcements_title_check
 CHECK (
   length(btrim(title)) <= 160
   AND (
     length(btrim(title)) >= 1
     OR length(btrim(body)) >= 1
     OR image_url IS NOT NULL
   )
 );
COMMIT;
