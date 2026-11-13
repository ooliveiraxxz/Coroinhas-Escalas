-- Imagens opcionais para avisos na tela.
-- Executar uma única vez no banco coroinhas (Neon).
ALTER TABLE public.screen_announcements
  ADD COLUMN IF NOT EXISTS image_url text;

ALTER TABLE public.screen_announcements
  DROP CONSTRAINT IF EXISTS screen_announcements_body_check;

ALTER TABLE public.screen_announcements
  ADD CONSTRAINT screen_announcements_body_check
  CHECK (
    (length(btrim(body)) BETWEEN 1 AND 4000)
    OR (length(btrim(body)) = 0 AND image_url IS NOT NULL)
  );

-- URLs externas ou imagens JPEG compactadas geradas no navegador.
ALTER TABLE public.screen_announcements
  ADD CONSTRAINT screen_announcements_image_url_check
  CHECK (
    image_url IS NULL
    OR (length(image_url) <= 250000
        AND (image_url LIKE 'data:image/jpeg;base64,%'
             OR image_url LIKE 'https://%'))
  );
