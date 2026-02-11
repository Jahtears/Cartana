Conventions serveur (etat actuel)

1. Slot id canonique
- Format: `player:TYPE:index` (ex: `0:PILE:1`, `1:HAND:1`).
- Objet canonique: `SlotId { player, type, index }`.
- Source: `Serveur/domain/game/constants/slots.js`.

2. Types de slot
- Types supportes: `DECK`, `HAND`, `BENCH`, `TABLE`, `PILE`.
- `player=0`: slots partages (`PILE`, `TABLE`).
- `player=1|2`: slots joueurs (`DECK`, `HAND`, `BENCH`).
- Source: `Serveur/domain/game/constants/slots.js`.

3. Stockage des cartes
- `game.slots`: `Map<SlotId, string[]>`.
- Les stacks contiennent uniquement des `card_id`.
- Les cartes sont indexees dans `game.cardsById[card_id]`.
- Source: `Serveur/domain/game/builders/gameBuilder.js`, `Serveur/domain/game/helpers/cardHelpers.js`.

4. Convention de pile
- `index 0` = bottom.
- `index last` = top.
- `putTop` = `push`, `putBottom` = `unshift`, `drawTop` = `pop`.
- Source: `Serveur/domain/game/helpers/slotStackHelpers.js`.

5. Mapping client/serveur des slots
- Le client voit toujours son propre cote en `playerIndex=1`.
- Conversion: `mapSlotForClient` / `mapSlotFromClientToServer`.
- Parsing: `parseSlotId`.
- Source: `Serveur/domain/game/helpers/slotHelpers.js`.

6. Visibilite et drag des cartes
- Payload carte: `{ card_id, valeur, couleur, dos, dos_couleur, draggable, slot_id }`.
- Visibilite par slot et drag policy centralises dans les helpers de vue.
- Source:
  - `Serveur/domain/game/builders/gameBuilder.js` (`buildCardData`)
  - `Serveur/domain/game/helpers/slotViewHelpers.js`
  - `Serveur/domain/game/constants/slotView.js`

7. Regles d'exposition des stacks au client
- `HAND`: toutes les cartes (owner), cache pour adversaire.
- `PILE`: top uniquement.
- `DECK`: top uniquement.
- `TABLE`: top uniquement.
- `BENCH`: toutes.
- Source: `Serveur/domain/game/helpers/slotViewHelpers.js`, `Serveur/domain/session/index.js`.

8. Distribution initiale de partie
- `HAND`: 5 cartes/joueur (`1:HAND:1`, `2:HAND:1`).
- `DECK`: 26 cartes/joueur (`1:DECK:1`, `2:DECK:1`).
- `BENCH`: 4 slots vides/joueur.
- `PILE`: reste de `deckA` dans `0:PILE:1`.
- `TABLE`: `0:TABLE:1` vide initial.
- Source: `Serveur/domain/game/builders/gameBuilder.js`, `Serveur/domain/game/constants/turnFlow.js`.

9. Turn flow (source de verite)
- Clock et constantes de tour: `Serveur/domain/game/turnClock.js`.
- Flow de tour: `initTurnForGame`, `endTurnAfterBenchPlay`, `tryExpireTurn`.
- Messages turn UI: `TURN_FLOW_MESSAGES`.
- Source: `Serveur/domain/game/helpers/turnFlowHelpers.js`.

10. Emission reseau et snapshots
- Incremental flush: `table_sync` -> `slot_state` -> `turn_update` -> `messages`.
- Dedupe: signatures `slot_sig` / `turn_sig` dans `gameMeta`.
- Snapshot complet audience via notifier.
- Source:
  - `Serveur/net/broadcast.js`
  - `Serveur/domain/session/index.js`
  - `Serveur/app/context.js`

11. Architecture cible deja appliquee
- `constants/*`: constantes pures.
- `helpers/*`: logique reusable metier/gameplay.
- `builders/*`: creation et assembly d'etat initial.
- Entrees metier:
  - `Serveur/domain/game/Regles.js`
  - `Serveur/domain/game/slotValidators.js`
  - `Serveur/domain/game/MoveApplier.js`
  - `Serveur/domain/game/moveOrchestrator.js`

12. Statut legacy
- Les anciens fichiers `SlotManager.js`, `SlotHelper.js`, `slots.js`, `state.js`, `turn.js`, `pileManager.js` ne sont plus la source canonique.
- Toute nouvelle logique doit etre ajoutee uniquement dans `constants/`, `helpers/`, `builders/` ou les points d'entree metier ci-dessus.
