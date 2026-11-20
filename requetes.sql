-- Séance 6 - Gestion d'une bibliothèque universitaire
-- Requêtes métier du jeu d'essai (PostgreSQL)
-- Les dates fixes du jeu d'essai sont au 19/11/2026.
-- Exécuter les requêtes dans la base contenant les données du livrable.
-- Requête 1 - Jointure 1 - Emprunts en cours (étudiant, titre, date prévue)
-- Résultat attendu : 7 emprunts actifs, avec les étudiants, les livres et les dates de retour prévues.
SELECT u.prenom || ' ' || u.nom AS etudiant,
l.titre,
e.code_barres,
m.date_retour_prevue
FROM emprunt m
JOIN utilisateur u ON u.id_utilisateur = m.id_utilisateur
JOIN exemplaire  e ON e.id_exemplaire  = m.id_exemplaire
JOIN livre       l ON l.id_livre       = e.id_livre
WHERE m.date_retour_effective IS NULL
ORDER BY m.date_retour_prevue;

-- Requête 2 - Jointure 2 - Catalogue : livres, auteurs et catégories
-- Résultat attendu : 11 lignes : les livres associés à leurs auteurs et catégories.
SELECT l.titre,
a.nom_auteur AS auteur,
c.libelle    AS categorie
FROM livre l
JOIN livre_auteur la ON la.id_livre     = l.id_livre
JOIN auteur       a  ON a.id_auteur     = la.id_auteur
JOIN categorie    c  ON c.id_categorie  = l.id_categorie
ORDER BY l.titre, a.nom_auteur;

-- Requête 3 - Jointure 3 (externe) - Livres jamais empruntés
-- Résultat attendu : 1 ligne : Statistique descriptive n'a aucun emprunt.
SELECT l.id_livre, l.titre, COUNT(m.id_emprunt) AS nb_emprunts
FROM livre l
LEFT JOIN exemplaire e ON e.id_livre      = l.id_livre
LEFT JOIN emprunt    m ON m.id_exemplaire = e.id_exemplaire
GROUP BY l.id_livre, l.titre
HAVING COUNT(m.id_emprunt) = 0
ORDER BY l.titre;

-- Requête 4 - Agrégation 1 - Exemplaires disponibles par livre
-- Résultat attendu : 10 lignes : nombre d'exemplaires et nombre d'exemplaires disponibles par livre.
SELECT l.titre,
COUNT(e.id_exemplaire) AS nb_exemplaires,
SUM(CASE WHEN e.id_exemplaire IS NOT NULL AND m.id_emprunt IS NULL THEN 1 ELSE 0 END) AS nb_disponibles
FROM livre l
LEFT JOIN exemplaire e ON e.id_livre = l.id_livre
LEFT JOIN emprunt    m ON m.id_exemplaire = e.id_exemplaire
AND m.date_retour_effective IS NULL
GROUP BY l.id_livre, l.titre
ORDER BY l.titre;

-- Requête 5 - Agrégation 2 - Emprunts par catégorie (au moins 2 emprunts)
-- Résultat attendu : 3 catégories : Informatique (6), Littérature (5), Mathématiques (2).
SELECT c.libelle AS categorie,
COUNT(*)  AS nb_emprunts
FROM emprunt m
JOIN exemplaire e ON e.id_exemplaire  = m.id_exemplaire
JOIN livre      l ON l.id_livre       = e.id_livre
JOIN categorie  c ON c.id_categorie   = l.id_categorie
GROUP BY c.libelle
HAVING COUNT(*) >= 2
ORDER BY nb_emprunts DESC, categorie;

-- Requête 6 - Sous-requête - Étudiants ayant au moins un emprunt en retard
-- Résultat attendu : 3 lignes : Awa Ba, Khady Gueye et Ibrahima Sy ont au moins un retard.
SELECT u.nom, u.prenom, u.email
FROM utilisateur u
WHERE u.id_utilisateur IN (
SELECT m.id_utilisateur
FROM emprunt m
WHERE m.date_retour_effective IS NULL
AND m.date_retour_prevue < '2026-11-19'
)
ORDER BY u.nom;

-- Requête 7 - Vue - État calculé d'un emprunt (En cours / En retard / Rendu)
-- Résultat attendu : 3 états : En cours (4), En retard (3), Rendu (8).
CREATE VIEW v_emprunt_etat AS
SELECT m.*,
CASE
WHEN m.date_retour_effective IS NOT NULL THEN 'Rendu'
WHEN m.date_retour_prevue < '2026-11-19'        THEN 'En retard'
ELSE 'En cours'
END AS etat
FROM emprunt m;
SELECT etat, COUNT(*) AS nb_emprunts
FROM v_emprunt_etat
GROUP BY etat
ORDER BY etat;

-- Requête 8 - Contrôle qualité - Données manquantes ou incohérentes
-- Résultat attendu : 2 anomalies : ISBN manquant pour Les Misérables et aucun exemplaire pour Statistique descriptive.
SELECT 'ISBN manquant' AS anomalie, l.titre AS element
FROM livre l
WHERE l.isbn IS NULL
UNION ALL
SELECT 'livre sans exemplaire', l.titre
FROM livre l
WHERE NOT EXISTS (SELECT 1 FROM exemplaire e WHERE e.id_livre = l.id_livre)
UNION ALL
SELECT 'livre sans auteur', l.titre
FROM livre l
WHERE NOT EXISTS (SELECT 1 FROM livre_auteur la WHERE la.id_livre = l.id_livre)
UNION ALL
SELECT 'retour avant emprunt', 'emprunt n° ' || m.id_emprunt
FROM emprunt m
WHERE m.date_retour_effective < m.date_emprunt
ORDER BY anomalie, element;

-- Scénario A : emprunt annulé
BEGIN;
SELECT id_exemplaire FROM exemplaire WHERE code_barres = 'BIB-0003' FOR UPDATE;
INSERT INTO emprunt VALUES (16, 7, 3, '2026-11-19', '2026-12-03', NULL);
SELECT COUNT(*) FROM emprunt WHERE date_retour_effective IS NULL; -- 8 dans la transaction
ROLLBACK;
SELECT COUNT(*) FROM emprunt WHERE date_retour_effective IS NULL; -- 7 après annulation

-- Scénario B : emprunt validé (à exécuter après le scénario A)
BEGIN;
SELECT id_exemplaire FROM exemplaire WHERE code_barres = 'BIB-0003' FOR UPDATE;
INSERT INTO emprunt VALUES (16, 7, 3, '2026-11-19', '2026-12-03', NULL);
COMMIT;
SELECT COUNT(*) FROM emprunt WHERE date_retour_effective IS NULL; -- 8 après validation

-- Scénario C : le doublon actif doit échouer, puis être annulé
BEGIN;
INSERT INTO emprunt VALUES (17, 4, 3, '2026-11-19', '2026-12-03', NULL);
-- Une erreur de clé unique est attendue pour l'index uq_emprunt_exemplaire_actif.
ROLLBACK;
SELECT COUNT(*) FROM emprunt WHERE date_retour_effective IS NULL; -- 8
