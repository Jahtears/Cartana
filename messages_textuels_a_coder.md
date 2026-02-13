# Inventaire des phrases textuelles à coder

Périmètre: fichiers `.js` et `.gd` de `Serveur/` et `Client/` (hors `__tests__` et `node_modules`).
Objectif: lister les textes d'erreur, d'indication et de règles pour migration vers des codes de protocole.

## 0) Messages déjà codés (actuels)

### 0.1 Codes d'erreur/réponse déjà émis côté serveur

| Code actuel | Phrase(s) actuelle(s) observée(s) | Source(s) |
|---|---|---|
| `AUTH_REQUIRED` | `Non authentifié` | `Serveur/app/router.js` |
| `AUTH_BAD_PIN` | `PIN incorrect` | `Serveur/handlers/auth/login.js` |
| `ALREADY_CONNECTED` | `Utilisateur déjà connecté` | `Serveur/handlers/auth/login.js` |
| `BAD_REQUEST` | `Champ ${label} manquant`, `Slot ID invalide`, `Game ID manquant`, `Identifiant/PIN manquant` | `Serveur/net/guards.js`, `Serveur/domain/game/moveRequest.js`, `Serveur/handlers/game/readyForGame.js`, `Serveur/handlers/auth/login.js` |
| `NOT_FOUND` | `Partie introuvable`, `Carte introuvable` | `Serveur/net/guards.js`, `Serveur/domain/game/moveRequest.js` |
| `FORBIDDEN` | `Spectateur: action interdite`, `Tu n'es pas joueur dans cette partie`, `Tu n'es pas spectateur de cette partie`, `Tu n'es pas dans cette partie` | `Serveur/net/guards.js`, `Serveur/handlers/game/joinGame.js`, `Serveur/handlers/game/readyForGame.js`, `Serveur/handlers/game/gameEnd.js` |
| `BAD_STATE` | `Tu es déjà en partie`, `Tu es déjà joueur dans une partie` | `Serveur/net/guards.js`, `Serveur/handlers/game/joinGame.js`, `Serveur/handlers/game/spectateGame.js` |
| `GAME_END` | `Partie terminée` | `Serveur/net/transport.js`, `Serveur/net/guards.js` |
| `GAME_PAUSED` | `Partie en pause: adversaire déconnecté` | `Serveur/domain/game/moveRequest.js` |
| `TURN_TIMEOUT` | `Temps écoulé` | `Serveur/domain/game/moveRequest.js` |
| `BUSY` | `Le joueur a déjà une invitation en attente`, `Le joueur a déjà une invitation en cours`, `Tu as déjà une invitation en attente`, `Tu as déjà une invitation en cours` | `Serveur/handlers/lobby/invite.js` |
| `NO_INVITE` | `Aucune invitation correspondante` | `Serveur/handlers/lobby/invite.js` |
| `NOT_IMPLEMENTED` | `Type non géré`, `Type non géré: ${req.type}` | `Serveur/net/transport.js`, `Serveur/app/router.js` |
| `SERVER_ERROR` | `Erreur serveur` | `Serveur/net/transport.js`, `Serveur/app/router.js`, `Serveur/handlers/auth/login.js` |

### 0.2 Codes UI déjà codés (gameplay/affichage)

| Code actuel | Usage/phrase(s) actuelle(s) | Source(s) |
|---|---|---|
| `GAME_MESSAGE.TURN_START` | `À vous de commencer`, `À vous de jouer` | `Serveur/shared/constants.js`, `Serveur/domain/game/helpers/turnFlowHelpers.js`, `Client/game/helpers/GameMessage.gd` |
| `GAME_MESSAGE.MOVE_OK` | `Valider` | `Serveur/shared/constants.js`, `Client/game/Game.gd`, `Client/game/helpers/GameMessage.gd` |
| `GAME_MESSAGE.MOVE_DENIED` | `Déplacement refusé` (et rejets de move) | `Serveur/shared/constants.js`, `Client/game/Game.gd` |
| `GAME_MESSAGE.INFO` | Messages d'information (`Invitation envoyée`, `${actor} a refusé ton invitation`, etc.) | `Serveur/shared/constants.js`, `Serveur/handlers/lobby/invite.js`, `Client/ui/Lobby.gd` |
| `GAME_MESSAGE.WARN` | Messages d'état non bloquants (`Temps écoulé`, erreurs métier transformées en warning) | `Serveur/shared/constants.js`, `Serveur/app/context.js`, `Client/net/Protocol.gd` |
| `GAME_MESSAGE.ERROR` | Fallback erreur UI | `Serveur/shared/constants.js`, `Client/net/Protocol.gd` |

### 0.3 Raisons de fin déjà codées

| Code actuel | Valeur transport | Phrase client |
|---|---|---|
| `GAME_END_REASONS.ABANDON` | `abandon` | `Abandon` |
| `GAME_END_REASONS.DECK_EMPTY` | `deck_empty` | `Pioche vide` |

### 0.4 Vérification d'intégration vers les nouveaux codes

| Source (0) | Statut d'intégration | Remarque |
|---|---|---|
| `0.1 Codes d'erreur/réponse` | Intégré | Couvert dans `1.1` et `2` |
| `0.2 Codes UI gameplay` | Intégré | Couvert dans `1.2` et `2` (`TURN_START`, `MOVE_OK`, `MOVE_DENIED`, `INFO`, `WARN`, `ERROR`) |
| `0.3 Raisons de fin` | Intégré | Gardé en interne serveur, non envoyé au client |

## 1) Serveur - messages réseau et règles

### 1.1 Erreurs réseau (version réduite)

| Phrases regroupées | Code cible (réduit) | Code actuel | Type | Source(s) |
|---|---|---|---|---|
| `Erreur` | `MSG_POPUP_TECH_ERROR_GENERIC` | `UNKNOWN` | Erreur | `Serveur/net/transport.js` |
| `Champ ${label} manquant`, `Clé invalide: ${key}`, `Champ inattendu: ${k} (attendu: ${allowedKeys.join(", ")})`, `Game ID manquant` | `MSG_POPUP_TECH_BAD_REQUEST` | `BAD_REQUEST` | Erreur | `Serveur/net/guards.js`, `Serveur/handlers/game/readyForGame.js` |
| `Partie introuvable` | `MSG_POPUP_TECH_NOT_FOUND` | `NOT_FOUND` | Erreur | `Serveur/net/guards.js` |
| `Tu n'es pas joueur dans cette partie`, `Tu n'es pas spectateur de cette partie`, `Tu n'es pas dans cette partie`, `Spectateur: déplacement interdit`, `Spectateur: action interdite` | `MSG_POPUP_TECH_FORBIDDEN` | `FORBIDDEN` | Erreur | `Serveur/handlers/game/joinGame.js`, `Serveur/handlers/game/readyForGame.js`, `Serveur/handlers/game/gameEnd.js`, `Serveur/domain/game/moveRequest.js`, `Serveur/net/guards.js` |
| `Tu es déjà en partie`, `Le joueur est déjà en partie` | `MSG_POPUP_TECH_BAD_STATE` | `BAD_STATE` | Erreur | `Serveur/net/guards.js`, `Serveur/handlers/lobby/invite.js` |
| `Le joueur ${target} a déjà une invitation en attente`, `Le joueur ${target} a déjà une invitation en cours`, `Tu as déjà une invitation en attente`, `Tu as déjà une invitation en cours` | `MSG_POPUP_INVITE_BUSY` | `BUSY` | Erreur | `Serveur/handlers/lobby/invite.js` |
| `Type non géré`, `Type non géré: ${req.type}` | `MSG_POPUP_TECH_NOT_IMPLEMENTED` | `NOT_IMPLEMENTED` | Erreur | `Serveur/net/transport.js`, `Serveur/app/router.js` |
| `Erreur serveur` | `MSG_POPUP_TECH_INTERNAL_ERROR` | `SERVER_ERROR` | Erreur | `Serveur/net/transport.js`, `Serveur/app/router.js`, `Serveur/handlers/auth/login.js` |
| `Non authentifié` | `MSG_POPUP_AUTH_REQUIRED` | `AUTH_REQUIRED` | Erreur | `Serveur/app/router.js` |
| `Identifiant/PIN manquant` | `MSG_POPUP_AUTH_MISSING_CREDENTIALS` | `BAD_REQUEST` | Erreur | `Serveur/handlers/auth/login.js` |
| `Utilisateur déjà connecté` | `MSG_POPUP_AUTH_ALREADY_CONNECTED` | `ALREADY_CONNECTED` | Erreur | `Serveur/handlers/auth/login.js` |
| `PIN incorrect` | `MSG_POPUP_AUTH_BAD_PIN` | `AUTH_BAD_PIN` | Erreur | `Serveur/handlers/auth/login.js` |
| `Aucune invitation correspondante` | `MSG_POPUP_INVITE_NOT_FOUND` | `NO_INVITE` | Erreur | `Serveur/handlers/lobby/invite.js` |
| `Partie en pause: adversaire déconnecté` | `MSG_POPUP_GAME_PAUSED` | `GAME_PAUSED` | Erreur | `Serveur/domain/game/moveRequest.js` |
| `Partie terminée` | `MSG_POPUP_GAME_ENDED` | `GAME_END` | Erreur | `Serveur/net/guards.js`, `Serveur/net/transport.js` |
| `${actor} a refusé ton invitation` | `MSG_POPUP_INVITE_DECLINED` | `GAME_MESSAGE.INFO` | Message info | `Serveur/handlers/lobby/invite.js` |

### 1.2 Messages inline et règles de jeu

| Phrase | Code cible | Code actuel | Type | Source(s) |
|---|---|---|---|---|
| `Slot ID invalide` | `MSG_INLINE_MOVE_INVALID_SLOT` | `BAD_REQUEST` | Erreur inline | `Serveur/domain/game/moveRequest.js` |
| `Carte introuvable` | `MSG_INLINE_RULE_CARD_NOT_FOUND` | `NOT_FOUND` | Erreur règle | `Serveur/domain/game/moveOrchestrator.js` |
| `ApplyMove rejected` | `MSG_INLINE_MOVE_REJECTED` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/moveOrchestrator.js` |
| `Carte inconnue` | `MSG_INLINE_RULE_CARD_UNKNOWN` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/Regles.js` |
| `Carte absente du slot source` | `MSG_INLINE_RULE_SOURCE_SLOT_MISSING_CARD` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/Regles.js` |
| `Joueur inconnu pour cette partie` | `MSG_INLINE_RULE_UNKNOWN_PLAYER` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/Regles.js` |
| `Aucun validateur pour ce slot` | `MSG_INLINE_RULE_SLOT_VALIDATOR_MISSING` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/Regles.js` |
| `Slot Table introuvable` | `MSG_INLINE_RULE_TABLE_SLOT_NOT_FOUND` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/slotValidators.js` |
| `Carte du deck uniquement sur slot Table` | `MSG_INLINE_RULE_DECK_ONLY_TO_TABLE` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/Regles.js` |
| `Pas votre tour` | `MSG_INLINE_RULE_NOT_YOUR_TURN` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/Regles.js` |
| `Carte du banc uniquement sur slot Table` | `MSG_INLINE_RULE_BENCH_ONLY_TO_TABLE` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/Regles.js` |
| `Banc interdit tant qu'un As est sur le dessus du deck` | `MSG_INLINE_RULE_ACE_BLOCKS_BENCH_DECK_TOP` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/Regles.js` |
| `Banc interdit tant qu'un As est en main` | `MSG_INLINE_RULE_ACE_BLOCKS_BENCH_HAND` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/Regles.js` |
| `Carte interdite sur Table (attendu: ${acceptedStr})` | `MSG_INLINE_RULE_CARD_NOT_ALLOWED_ON_TABLE` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/slotValidators.js` |
| `Interdit de jouer sur un deck` | `MSG_INLINE_RULE_CANNOT_PLAY_ON_DECK` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/slotValidators.js` |
| `Interdit de jouer sur la main` | `MSG_INLINE_RULE_CANNOT_PLAY_ON_HAND` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/slotValidators.js` |
| `Interdit de jouer sur la pioche` | `MSG_INLINE_RULE_CANNOT_PLAY_ON_DRAWPILE` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Règle | `Serveur/domain/game/slotValidators.js` |
| `Slot adverse interdit` | `MSG_INLINE_RULE_OPPONENT_SLOT_FORBIDDEN` | `BAD_REQUEST` (`details.move_code=MOVE_DENIED`) | Erreur règle | `Serveur/domain/game/Regles.js` |
| `À vous de commencer` | `MSG_INLINE_TURN_START_FIRST` | `GAME_MESSAGE.TURN_START` | Message tour | `Serveur/domain/game/helpers/turnFlowHelpers.js` |
| `À vous de jouer` | `MSG_INLINE_TURN_START` | `GAME_MESSAGE.TURN_START` | Message tour | `Serveur/domain/game/helpers/turnFlowHelpers.js` |
| `Temps écoulé` | `MSG_INLINE_TURN_TIMEOUT` | `TURN_TIMEOUT` / `GAME_MESSAGE.WARN` | Erreur état | `Serveur/domain/game/moveRequest.js`, `Serveur/domain/game/helpers/turnFlowHelpers.js` |
| `Valider` | `MSG_INLINE_MOVE_OK` | `GAME_MESSAGE.MOVE_OK` | Message action | `Serveur/shared/constants.js`, `Client/game/Game.gd`, `Client/game/helpers/GameMessage.gd` |

## 2) Client - fallback et UI locale

| Phrase | Code cible | Code actuel | Type | Source(s) |
|---|---|---|---|---|
| `PIN incorrect` | `MSG_POPUP_AUTH_BAD_PIN` | `AUTH_BAD_PIN` | Fallback erreur | `Client/net/Protocol.gd` |
| `Utilisateur déjà connecté` | `MSG_POPUP_AUTH_ALREADY_CONNECTED` | `ALREADY_CONNECTED` | Fallback erreur | `Client/net/Protocol.gd` |
| `Identifiant ou PIN manquant` | `MSG_POPUP_AUTH_MISSING_CREDENTIALS` | `validation locale` | UI auth | `Client/ui/Login.gd` |

| `Erreur de connexion` | `MSG_POPUP_AUTH_CONNECTION_ERROR` | `fallback local (login)` | UI auth | `Client/ui/Login.gd` |
| `Authentification requise` | `MSG_POPUP_AUTH_REQUIRED` | `AUTH_REQUIRED` | Fallback erreur | `Client/net/Protocol.gd` |
| `Requête invalide` | `MSG_POPUP_TECH_BAD_REQUEST` | `BAD_REQUEST` | Fallback erreur | `Client/net/Protocol.gd` |
| `Ressource introuvable` | `MSG_POPUP_TECH_NOT_FOUND` | `NOT_FOUND` | Fallback erreur | `Client/net/Protocol.gd` |
| `Action interdite` | `MSG_POPUP_TECH_FORBIDDEN` | `FORBIDDEN` | Fallback erreur | `Client/net/Protocol.gd` |
| `Action impossible dans cet état` | `MSG_POPUP_TECH_BAD_STATE` | `BAD_STATE` | Fallback erreur | `Client/net/Protocol.gd` |
| `La partie est terminée` | `MSG_POPUP_GAME_ENDED` | `GAME_END` | Fallback erreur | `Client/net/Protocol.gd` |
| `La partie est en pause` | `MSG_POPUP_GAME_PAUSED` | `GAME_PAUSED` | Fallback erreur | `Client/net/Protocol.gd` |
| `Temps écoulé` | `MSG_INLINE_TURN_TIMEOUT` | `TURN_TIMEOUT` | Fallback erreur | `Client/net/Protocol.gd`, `Client/game/helpers/GameMessage.gd` |
| `Invitation introuvable` | `MSG_POPUP_INVITE_NOT_FOUND` | `NO_INVITE` | Fallback erreur | `Client/net/Protocol.gd` |
| `Action indisponible` | `MSG_POPUP_INVITE_BUSY` | `BUSY` | Fallback erreur | `Client/net/Protocol.gd` |
| `Action non gérée` | `MSG_POPUP_TECH_NOT_IMPLEMENTED` | `NOT_IMPLEMENTED` | Fallback erreur | `Client/net/Protocol.gd` |
| `Erreur serveur` | `MSG_POPUP_TECH_INTERNAL_ERROR` | `SERVER_ERROR` | Fallback erreur | `Client/net/Protocol.gd` |
| `Action impossible` | `MSG_POPUP_UI_ACTION_IMPOSSIBLE` | `GAME_MESSAGE.ERROR` (fallback `normalize_error_message`) | Fallback UI | `Client/net/Protocol.gd`, `Client/ui/Lobby.gd` |

| `Abandon` | `- (non envoyé au client)` | `GAME_END_REASONS.ABANDON` (`abandon`) | Raison interne serveur | `Serveur/domain/game/constants/gameEnd.js` |
| `Deck vide` | `- (non envoyé au client)` | `GAME_END_REASONS.DECK_EMPTY` (`deck_empty`) | Raison interne serveur | `Serveur/domain/game/constants/gameEnd.js` |
| `Gagnant: %s` | `MSG_POPUP_GAME_END_WINNER` | `evt game_end (template local)` | Popup game end | `Client/net/Protocol.gd` |
| `Victoire` | `MSG_POPUP_GAME_END_VICTORY` | `evt game_end (template local)` | Popup game end | `Client/net/Protocol.gd` |
| `Défaite` | `MSG_POPUP_GAME_END_DEFEAT` | `evt game_end (template local)` | Popup game end | `Client/net/Protocol.gd` |
| `Oui` | `-` | `-` | Bouton popup | `Client/ui/WindowPopup.gd`, `Client/ui/Lobby.gd` |
| `Non` | `-` | `-` | Bouton popup | `Client/ui/WindowPopup.gd`, `Client/ui/Lobby.gd` |
| `%s t'invite à jouer` | `MSG_POPUP_INVITE_RECEIVED` | `evt invite_request` | Popup invite | `Client/ui/WindowPopup.gd` |
| `Accepter` | `-` | `-` | Bouton popup | `Client/ui/WindowPopup.gd` |
| `Refuser` | `-` | `-` | Bouton popup | `Client/ui/WindowPopup.gd` |


| `Erreur get_players` | `MSG_POPUP_LOBBY_GET_PLAYERS_ERROR` | `fallback local (get_players)` | UI lobby | `Client/ui/Lobby.gd` |
| `Invitation envoyée` | `MSG_POPUP_INVITE_SENT` | `GAME_MESSAGE.INFO` | UI lobby | `Client/ui/Lobby.gd` |
| `${actor} a refusé ton invitation` | `MSG_POPUP_INVITE_DECLINED` | `GAME_MESSAGE.INFO` | UI lobby | `Client/ui/Lobby.gd` |
| `Invitation impossible` | `MSG_POPUP_INVITE_FAILED` | `fallback local (invite)` | UI lobby | `Client/ui/Lobby.gd` |
| `Regarder cette partie en spectateur ?\n(game_id: %s)\nJoueurs: %s` | `MSG_POPUP_SPECTATE_CONFIRM` | `-` | Popup spectateur | `Client/ui/Lobby.gd` |
| `Se déconnecter et revenir à l'écran de connexion ?` | `MSG_POPUP_LOGOUT_CONFIRM` | `-` | Popup logout | `Client/ui/Lobby.gd` |
| `%s s'est déconnecté` | `MSG_POPUP_OPPONENT_DISCONNECTED` | `GAME_MESSAGE.WARN` | Message info | `Client/game/Game.gd` |
| `%s a rejoint la partie` | `MSG_POPUP_OPPONENT_REJOINED` | `GAME_MESSAGE.INFO` | Message info | `Client/game/Game.gd` |
| `Valider` | `MSG_INLINE_MOVE_OK` | `GAME_MESSAGE.MOVE_OK` | Message action | `Client/game/Game.gd`, `Client/game/helpers/GameMessage.gd` |
| `Déplacement refusé` | `MSG_INLINE_MOVE_DENIED` | `GAME_MESSAGE.MOVE_DENIED` (si `details.move_code=MOVE_DENIED`) | Message erreur | `Client/game/Game.gd` |
| `Retour lobby` | `-` | `-` | Bouton popup | `Client/game/Game.gd` |
| `Rester` | `-` | `-` | Bouton popup | `Client/game/Game.gd` |
| `Quitter la partie et revenir au lobby ?` | `MSG_POPUP_QUIT_CONFIRM` | `-` | Popup quitter | `Client/game/Game.gd` |
| `Annuler` | `-` | `-` | Bouton popup | `Client/game/Game.gd` |
| `Quitter` | `-` | `-` | Bouton popup | `Client/game/Game.gd` |
| `Attendre` | `-` | `-` | Bouton popup | `Client/game/Game.gd` |
| `%s s'est déconnecté.\nAttendre ou revenir au lobby ?` | `MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE` | `-` | Popup deconnexion adversaire | `Client/game/Game.gd` |
| `À vous de commencer` | `MSG_INLINE_TURN_START_FIRST` | `GAME_MESSAGE.TURN_START` | Message tour | `Client/game/helpers/GameMessage.gd` |
| `À vous de jouer` | `MSG_INLINE_TURN_START` | `GAME_MESSAGE.TURN_START` | Message tour | `Client/game/helpers/GameMessage.gd` |

## 3) Hors protocole (logs techniques, optionnels à coder)

| Phrase | Code cible | Code actuel | Source(s) |
|---|---|---|---|
| `Connection perdu` | `` | `-` | `Client/net/NetworkManager.gd` |
| `Max reconnect attempts exceeded` | `-` | `-` | `Client/net/NetworkManager.gd` |
| `Request timeout after %d retries` | `-` | `TIMEOUT` | `Client/net/NetworkManager.gd` |
| `Request timeout` | `-` | `TIMEOUT` | `Client/net/NetworkManager.gd` |
| `Queue full` | `-` | `CLIENT_ERROR` | `Client/net/NetworkManager.gd` |
| `WebSocket connect error: %s` | `-` | `-` | `Client/net/NetworkManager.gd` |
| `WebSocket send failed for type: %s (error: %s)` | `-` | `-` | `Client/net/NetworkManager.gd` |
| `JSON parse error at line %d: %s` | `-` | `-` | `Client/net/NetworkManager.gd` |
| `JSON serialization failed for type: %s` | `-` | `-` | `Client/net/NetworkManager.gd` |
 
