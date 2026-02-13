Participant A (Inviteur)
Participant B (Invité)
Client A
Client B
Serveur

A -> Serveur : INVITE_SENT
Serveur -> B : INVITE_RECEIVED

B -> Serveur : INVITE_ACCEPTED
Serveur -> A : INVITE_ACCEPTED
Serveur -> B : INVITE_ACCEPTED

--- TRANSITION LOBBY → GAME_SETUP ---

Serveur -> A : GAME_SETUP_CREATED { gameId, playerIndex }
Serveur -> B : GAME_SETUP_CREATED { gameId, playerIndex }

Client A -> Client A : Changement de scène vers "Game"
Client B -> Client B : Changement de scène vers "Game"

--- INITIALISATION DE LA PARTIE ---

Serveur -> A : GAME_SETUP_STATE { slotsById, cardsById, turn }
Serveur -> B : GAME_SETUP_STATE { slotsById, cardsById, turn }

Client A -> Client A : Création des slots, cartes, UI
Client B -> Client B : Création des slots, cartes, UI

Serveur -> A : GAME_GAME_START
Serveur -> B : GAME_GAME_START

Client A -> Client A : Affiche "La partie commence"
Client B -> Client B : Affiche "La partie commence"

--- DÉBUT DU PREMIER TOUR ---

Serveur -> A : GAME_TURN_START { player: 1 }
Serveur -> B : GAME_TURN_START { player: 1 }

Client A -> Client A : Affiche "À vous de commencer"
Client B -> Client B : Affiche "L’adversaire commence"

--- TIMER ---

Serveur -> A : TIMER_START { duration: 30000 }
Serveur -> B : TIMER_START { duration: 30000 }

Client A -> Client A : Démarre UI du timer
Client B -> Client B : Démarre UI du timer

--- PENDANT LE TOUR ---

Serveur -> A : TIMER_UPDATE { remaining: X }
Serveur -> B : TIMER_UPDATE { remaining: X }

Client A -> Client A : Met à jour la barre
Client B -> Client B : Met à jour la barre

--- SI LE JOUEUR JOUE AVANT LA FIN ---

A -> Serveur : PLAY_CARD
Serveur -> A : CARD_MOVED
Serveur -> B : CARD_MOVED

Serveur -> A : TIMER_STOP
Serveur -> B : TIMER_STOP

Client A -> Client A : Stop timer
Client B -> Client B : Stop timer

--- FIN DU TOUR ---

Serveur -> A : GAME_TURN_END
Serveur -> B : GAME_TURN_END

Serveur -> A : GAME_TURN_START { player: 2 }
Serveur -> B : GAME_TURN_START { player: 2 }

Serveur -> A : TIMER_START { duration: 30000 }
Serveur -> B : TIMER_START { duration: 30000 }
