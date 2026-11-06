-- Retour proposé : journal des notifications. Les index partent avec la table.
drop function if exists public.process_notifications();
drop function if exists public.send_notification(uuid, text, text, text, jsonb);
drop table if exists public.notifications_log;
notify pgrst, 'reload schema';
