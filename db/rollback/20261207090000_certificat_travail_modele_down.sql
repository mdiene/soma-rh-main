-- Retour : supprime le modèle du certificat de travail (le texte de secours du code reste utilisable).
delete from public.document_templates where code = 'certificat_travail';
