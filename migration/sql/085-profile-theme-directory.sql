-- Extend the existing public profile directory with SELF-ONLY theme preference.
-- Other people's theme preferences remain private.
CREATE OR REPLACE VIEW public.profile_directory AS
SELECT id,
    name,
        CASE
            WHEN id = auth.uid() OR is_coordinator() THEN email
            ELSE NULL::text
        END AS email,
    role,
    approved,
    photo_url,
        CASE
            WHEN is_coordinator() THEN notes
            ELSE NULL::text
        END AS notes,
    created_at,
        CASE
            WHEN id = auth.uid() OR is_coordinator() THEN notification_preferences
            ELSE NULL::jsonb
        END AS notification_preferences,
        CASE
            WHEN id = auth.uid() OR is_coordinator() THEN last_seen_at
            ELSE NULL::timestamp with time zone
        END AS last_seen_at,
        CASE
            WHEN id = auth.uid() OR is_developer() THEN coordination_group
            ELSE NULL::text
        END AS coordination_group,
    CASE WHEN id = auth.uid() THEN theme_preference ELSE NULL::text END AS theme_preference
   FROM profiles;
