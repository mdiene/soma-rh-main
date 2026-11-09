-- Certificat de travail conforme à l'art. 140 du Code du travail 2026 (spécification docs/CODE_TRAVAIL_2026_SPECIFICATION_SOMA_RH.md, RUP-14, C26-13) :
-- il n'indique EXCLUSIVEMENT que la date d'entrée, la date de sortie, la nature et les dates des emplois successifs et la catégorie de la
-- convention collective. On retire donc la date de naissance et le matricule du modèle de départ, et on ajoute la catégorie.
-- Le modèle n'est remplacé que s'il n'a jamais été modifié par la RH (version 1). Les emplois successifs ne sont pas encore historisés :
-- seul l'emploi actuel est indiqué (à compléter par un historique des emplois).
-- Retour : db/rollback/20261210090000_certificat_travail_art140_down.sql
update public.document_templates
   set body = E'Nous soussignés, {{societe}}, certifions que {{civilite}} {{prenom}} {{nom}} a été {{employe}} au sein de notre société{{fonction}}{{categorie}}, du {{date_embauche}} au {{date_sortie}}.\n\nLe présent certificat est délivré à l''intéressé{{e}}, à l''occasion de son départ de l''entreprise, pour servir et valoir ce que de droit.'
 where code = 'certificat_travail' and version = 1;
