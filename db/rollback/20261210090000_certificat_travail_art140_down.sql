-- Retour : modèle du certificat de travail tel qu'en 20261207090000 (avec date de naissance et matricule), s'il n'a pas été modifié depuis.
update public.document_templates
   set body = E'Nous soussignés, {{societe}}, certifions que {{civilite}} {{prenom}} {{nom}}{{naissance}}, matricule {{matricule}}, a été {{employe}} au sein de notre société{{fonction}} du {{date_embauche}} au {{date_sortie}}.\n\nLe présent certificat est délivré à l''intéressé{{e}}, à l''occasion de son départ de l''entreprise, pour servir et valoir ce que de droit.'
 where code = 'certificat_travail' and version = 2;
