-- Template de test RLS pour module M0
-- À ajuster par Claude selon le module cible
-- Vérifie que les politiques RLS sont correctement définies
-- et que les données personnelles sont protégées selon la règle du projet

-- 1. Vérifier que RLS est activé sur la table cible
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname = '<TABLE_NAME>';
-- Doit renvoyer relrowsecurity = true

-- 2. Vérifier la politique par défaut
SELECT polname, polcmd, polroles, polqual
FROM pg_policy
WHERE polrelid = '<TABLE_NAME>'::regclass
ORDER BY polcmd, polroles;

-- 3. Tester l'accès avec le rôle 'rh'
SET ROLE rh;
-- Doit permettre l'accès aux données RH autorisées

-- 4. Tester l'accès avec le rôle 'paie'
SET ROLE paie;
-- Doit permettre l'accès aux données de paie autorisées

-- 5. Tester l'accès avec le rôle 'admin' (tout permettre)
SET ROLE admin;
-- Doit permettre l'accès complet

-- 6. Tester l'accès avec le rôle 'salarié' (accès restreint)
SET ROLE salarié;
-- Doit restreindre l'accès aux seules données du salarié connecté

-- 7. Vérifier les politiques spécifiques
SELECT polname, polcmd, polroles, polqual
FROM pg_policy
WHERE polrelid = '<TABLE_NAME>'::regclass
AND polroles @> ARRAY['rh'::regrole, 'paie'::regrole]
ORDER BY polname;

-- 8. Test d'insertion (si applicable) - Doit être restreint
INSERT INTO <TABLE_NAME> (<COLUMNS>)
VALUES (<VALUES>)
ON CONFLICT DO NOTHING;
-- Doit être bloqué ou restreint selon la politique

-- 9. Test de mise à jour (si applicable) - Doit être restreint
UPDATE <TABLE_NAME>
SET <COLUMN> = <VALUE>
WHERE <CONDITION>;
-- Doit être restreint aux propres données du salarié

-- 10. Test de suppression (si applicable) - Doit être très restreint
DELETE FROM <TABLE_NAME>
WHERE <CONDITION>;
-- Doit être bloqué pour la plupart des rôles

-- 11. Vérifier qu'aucune donnée personnelle n'est exposée
-- Exécuter en tant que rôle public non authentifié
RESET ROLE;
SET ROLE public;
-- Doit être bloqué ou ne renvoyer aucune ligne sensible

-- 12. Comparaison avec la règle du projet :
--    - Toutes les nouvelles tables doivent avoir RLS activée
--    - Les politiques doivent utiliser has_role(array['rh'|'paie'])
--    - Index sur les clés étrangères doivent exister
--    - Tables exclues de RLS (si nécessaire) : notifications_log, audit_*, user_roles, auth.*

-- 13. Index sur les clés étrangères (obligatoire)
SELECT schemaname, tablename, attname, attnum
FROM pg_attribute
WHERE attrelid = '<TABLE_NAME>'::regclass
AND attnum > 0
AND NOT attisdropped
ORDER BY attname;
-- Vérifier qu'il y a un index sur chaque clé étrangère

-- Exemple de politique type à créer si manquante :
/*
CREATE POLICY rh_access ON <TABLE_NAME>
USING (has_role(array['rh'|'paie']));
*/

-- 14. Documentation du test
-- Consigner le résultat de chaque test ci-dessus
-- Noter les écarts par rapport à la règle du projet
-- Proposer les correctifs nécessaires