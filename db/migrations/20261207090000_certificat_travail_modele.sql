-- L7-04 : modèle du certificat de travail (document de sortie), modifiable par la RH comme les attestations.
-- Mentions factuelles seulement (identité, emploi, dates d'entrée et de sortie). Les mentions imposées par le Code du travail 2026
-- n'ont pas été lues : le texte est à faire valider par la RH ou le juriste avant usage (Paramètres > Modèles de documents).
-- Retour : db/rollback/20261207090000_certificat_travail_modele_down.sql
insert into public.document_templates (code, title, body) values
('certificat_travail', 'Certificat de travail',
 E'Nous soussignés, {{societe}}, certifions que {{civilite}} {{prenom}} {{nom}}{{naissance}}, matricule {{matricule}}, a été {{employe}} au sein de notre société{{fonction}} du {{date_embauche}} au {{date_sortie}}.\n\nLe présent certificat est délivré à l''intéressé{{e}}, à l''occasion de son départ de l''entreprise, pour servir et valoir ce que de droit.')
on conflict (code) do nothing;
