-- Rollback de D-013 : rend l'exécution aux rôles public et anon (état antérieur).
grant execute on all functions in schema public to public, anon;
