# Conventions serveur

---

## 1. Slot id canonique

- Format : `player:TYPE:index` (ex : `0:PILE:1`, `1:HAND:1`).
- Objet canonique : `SlotId { player, type, index }`.

---

## 2. Types de slot

- Types supportés : `DECK`, `HAND`, `BENCH`, `TABLE`, `PILE`.
- `player=0` : slots partagés (`PILE`, `TABLE`).
- `player=1|2` : slots joueurs (`DECK`, `HAND`, `BENCH`).

---

## 3. Stockage des cartes

- `game.slots` : `Map<SlotId, string[]>`.
- Les stacks contiennent uniquement des `card_id`. **Jamais de `null`.**
- **Exception `HAND` :** le stack est toujours de taille fixe 5. `""` représente une position libre.
- Les cartes sont indexées dans `game.cardsById[card_id]`.

---

## 4. Convention de pile (tous les slots)

Tous les slots — sauf `HAND` — utilisent la convention dense :

- `index 0` = bottom, `index last` = top.
- `putTop` = `push`, `putBottom` = `unshift`, `drawTop` = `pop`.
- `removeCardFromSlot` = `splice` à l'index trouvé.

> **Exception `HAND` :** le stack est de taille fixe 5. La position d'une carte en main est son index dans le stack. `""` marque une position libre. Les opérations dense (`push`, `pop`…) ne s'appliquent pas à `HAND`.

---

## 5. Mapping client/serveur des slots

- Le client voit toujours son propre côté en `playerIndex=1`.

---

## 6. Modèle canonique des cartes

Modèle interne serveur :

```
{ id, value, color, source }
```

| Champ    | Valeurs possibles                         |
|----------|-------------------------------------------|
| `id`     | UUID (`crypto.randomUUID()`)              |
| `value`  | `A 2 3 4 5 6 7 8 9 10 V D R`             |
| `color`  | `H C P S`                                 |
| `source` | `A` ou `B` (identifie le paquet physique) |

**Génération initiale :** 2 paquets physiques mélangés séparément : `sourceA` et `sourceB`, chacun contenant `13 valeurs × 4 couleurs = 52 cartes`.

---

## 7. Payload carte serveur → client

```
{
  card_id,
  slot_id,
  valeur,
  couleur,
  source,
  dos,
  draggable
}
```

**Règles :**

- `dos=true` dans `PILE` et dans `HAND` adverse.
- Si `dos=true`, alors `valeur=""` et `couleur=""`.
- Une position `HAND` avec `card_id=""` n'est pas émise au client.

---

## 8. Comportement des slots (visibilité, drag, drop)

| Slot    | Cartes visibles              | Draggable                          | Droppable    |
|---------|------------------------------|------------------------------------|--------------|
| `DECK`  | top + top-1 (en dos)         | top uniquement ¹                   | non          |
| `HAND`  | toutes (owner) / dos (adv.)  | toutes (owner) ¹                   | non          |
| `BENCH` | toutes                       | top uniquement ¹                   | cf. §12.2    |
| `TABLE` | top uniquement               | non                                | cf. §11.1    |
| `PILE`  | top uniquement               | non                                | non          |

¹ Soumis aux conditions d'ownership, statut spectateur et état de pause.

---

## 9. Distribution initiale de partie

| Slot         | Contenu                                      |
|--------------|----------------------------------------------|
| `1:HAND:1`   | 5 cartes depuis `sourceA`                    |
| `2:HAND:1`   | 5 cartes depuis `sourceA`                    |
| `1:DECK:1`   | 26 cartes depuis `sourceB`                   |
| `2:DECK:1`   | 26 cartes depuis `sourceB`                   |
| `1:BENCH:1-4`| 4 slots vides                                |
| `2:BENCH:1-4`| 4 slots vides                                |
| `0:PILE:1`   | reste de `sourceA` (42 cartes)               |
| `0:TABLE:1`  | vide                                         |

---

## 10. Mouvements autorisés

**Destinations interdites (tous `from`) :** `DECK`, `HAND`, `PILE`.

**Matrice `from → to` :**

| Source   | Destinations autorisées         | Notes                             |
|----------|---------------------------------|-----------------------------------|
| `HAND`   | `TABLE`, `BENCH`                | `BENCH` = fin de tour             |
| `DECK`   | `TABLE`                         |                                   |
| `BENCH`  | `TABLE`                         |                                   |
| `TABLE`  | _(serveur uniquement → `PILE`)_ | drag interdit côté client         |
| `PILE`   | _(serveur uniquement → `HAND`)_ | drag interdit côté client         |

**Contraintes transverses :**

- La carte doit être présente dans `from_slot_id`.
- Seul le joueur courant peut jouer.
- Aucun slot adverse autorisé en `from`/`to` (sauf slots partagés `player=0`).
- Les slots joueurs en `from` doivent appartenir à l'acteur.
- si from_slot_id = to_slot_id move interdit

---

## 11. Gestion de `TABLE`

### 11.1 Règle de validation

Une carte peut être posée sur un slot `TABLE` si et seulement si sa valeur fait partie des valeurs acceptées pour le `count` actuel du slot cible :

| `count` | Valeurs acceptées |
|---------|-------------------|
| 0       | `A`, `R`          |
| 1       | `2`, `R`          |
| 2       | `3`, `R`          |
| 3       | `4`, `R`          |
| 4       | `5`, `R`          |
| 5       | `6`, `R`          |
| 6       | `7`, `R`          |
| 7       | `8`, `R`          |
| 8       | `9`, `R`          |
| 9       | `10`, `R`         |
| 10      | `V`, `R`          |
| 11      | `D`               |
| ≥ 12    | aucune            |

Le slot `TABLE` cible doit exister.

### 11.2 Cycle de vie des slots `TABLE`

**Invariant :** il existe toujours au moins un slot `TABLE` vide après chaque action serveur.

**Création :** un seul slot `0:TABLE:1` vide est créé au démarrage. Après chaque pose, le serveur garantit cet invariant : réutilise le premier slot vide existant, ou crée `0:TABLE:N+1`.

**Recyclage → `PILE` :** un slot `TABLE` est recyclé en fin de tour uniquement s'il contient exactement 12 cartes. Ses cartes sont mélangées puis insérées au bas de `PILE`. Le slot est ensuite supprimé.

**Nettoyage :** après recyclage, les slots `TABLE` vides en excès sont supprimés (un seul conservé).

---

## 12. Gestion des tours

### 12.1 Démarrage de partie

Le tour démarre dès que les 2 joueurs ont rejoint. Le starter est désigné en comparant le top de `DECK` de chaque joueur selon l'ordre : `A > R > D > V > 10 > … > 2`. En cas d'égalité, on compare top-1. En cas d'égalité, on compare top-1-1 ect.

Le tour initial est numéroté `1`, et le timer est fixé à `TURN_MS = 20 000 ms`.

### 12.2 Fin de tour (action joueur)

Un tour se termine uniquement sur un move valide vers `BENCH`. Un move vers `TABLE` ne termine pas le tour.

Séquence de fin de tour :
1.deplacement des 12 cartes du slots `TABLE` plein vers bot `PILE`.
2. Recyclage du slots `TABLE` vidé. 
3. Refill de la `HAND` du joueur suivant : chaque position `""` du stack est remplacée par le top de `PILE`, dans l'ordre index croissant.
4. Passage au joueur suivant, incrément du numéro de tour, reset du timer à `TURN_MS`.

### 12.3 Bonus de timer

Chaque move vers `TABLE` ajoute `+10 000 ms` au timer courant, plafonné à `TURN_MS`.

### 12.4 Expiration du timer

Le serveur vérifie les expirations toutes les `250 ms`. À l'expiration :
1. Tentative d'auto-play des `A` disponible en main vers `TABLE`.
2. Exécution de la séquence de fin de tour (cf. §12.2).
3. Notifications : `TURN_TIMEOUT` → joueur précédent, `TURN_START` → joueur suivant, puis snapshot.

### 12.5 Pause / reprise (présence)

- **Déconnexion** : timer mis en pause. Les `move_request` sont refusés avec `GAME_PAUSED`.
- **Reconnexion** : reprise uniquement quand aucun joueur n'est déconnecté.
- Un tour en pause n'expire pas.

---

## 13. Conditions de fin de jeu

### 13.1 Lecture côté joueur

- **Victoire** : `winner == username`.
- **Défaite** : `winner` défini et `winner != username`.
- **Match nul** : `winner == null`.

### 13.2 Déclencheurs de fin de jeu

| Cause | `winner` |
|-------|----------|----------|
| Deck de l'acteur vide après un move `DECK → TABLE` | acteur |
| Pile partagée vide en fin de tour|  `null` (nul) |
| 3 timeouts consécutifs d'un joueur | adversaire |
| le joueur quiite la partie avec le bouton | adversaire |
| le joueur quitte la partie en fermant la fenetre | adversaire |



---

## 14. Convention de nommage

### 14.1 Format cible

`domaine_action_objet`

- **domaine** : `slot`, `card`, `move`, `table`, `hand`, `turn`, `game_end`, `payload`
- **action** : `parse`, `format`, `get`, `build`, `validate`, `apply`, `ensure`, `recycle`, `init`, `end`, `expire`, `pause`, `resume`, `emit`, `count`, `refill`
- **objet** : nom métier (`id`, `type`, `state`, `snapshot`…)

Toute exception doit être documentée explicitement dans la section concernée.

### 14.2 Noms cibles par domaine

| Domaine    | Noms cibles                                                                       |
|------------|-----------------------------------------------------------------------------------|
| `slot`     | `slot_parse_id`, `slot_format_id`, `slot_map_client_server`                       |
| `card`     | `card_get_by_id`, `card_rank_turn`, `card_compare_turn`                           |
| `move`     | `move_validate`, `move_apply`                                                     |
| `table`    | `table_validate`, `table_get_allowed`, `table_ensure_empty`, `table_recycle`      |
| `hand`     | `hand_refill`                                                                     |
| `turn`     | `turn_init`, `turn_end`, `turn_expire`, `turn_pause`, `turn_resume`, `turn_count_timeout` |
| `game_end` | `game_end_resolve`, `game_end_snapshot`                                           |
| `payload`  | `payload_build_card`, `payload_build_slot`, `payload_build_snapshot`              |

> Le mapping vers les noms legacy est maintenu dans `MIGRATION.md`, pas ici.

---

## 15. Messages de jeu (`GameMessage.gd`)

### 15.1 Contrat

Payload standard : `{ message_code, details? }`

`GameMessage.gd` est l'unique point d'affichage pour `Game.tscn`.

### 15.2 Set de codes actif

| Catégorie     | Codes                                                                                                                                         |
|---------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| Générique     | `RULE_MOVE_DENIED`                                                                                                                            |
| Succès / tour | `RULE_OK`, `RULE_TURN_START_FIRST`, `RULE_TURN_START`, `RULE_TURN_TIMEOUT`                                                                   |
| Refus métier  | `RULE_DECK_TO_TABLE`, `RULE_NOT_YOUR_TURN`, `RULE_BENCH_TO_TABLE`, `RULE_ACE_DECK`, `RULE_ACE_HAND`, `RULE_TABLE_ALLOWED` ¹                  |

¹ `RULE_TABLE_ALLOWED` inclut `allowed_values` dans `details`.