# PR1 - Turn/Timeout (serveur autoritaire)

## Objectif

Faire expirer le tour **côté serveur** dès que le temps est écoulé, sans attendre un `move_request`, et empêcher le timer de dépasser sa valeur max initiale.

## Scope

- Expiration automatique de tour sur boucle serveur.
- Timeout métier (`tryExpireTurn`) avec auto-play As + switch de tour.
- Cap du timer (`durationMs`) à `TURN_MS` (15s).
- Messages UI ciblés lors du timeout:
  - `prev`: `Temps ecoule.`
  - `next`: `A vous de jouer.`

## Fichiers concernés

- `Serveur/domain/game/turn.js`
- `Serveur/app/context.js`
- `Serveur/app/server.js`

## Comportement attendu

1. Si `endsAt` est dépassé, le serveur expire le tour sans action client.
2. Si le joueur courant a un As en main au timeout, il est auto-joué sur Table.
3. Le tour passe au joueur suivant et le timer repart à 15s.
4. Le bonus temps ne peut jamais faire dépasser 15s de temps restant.
5. Le joueur expiré voit `Temps ecoule.`, le joueur suivant voit `A vous de jouer.` dans `GameMessage`.

## Vérification

```bash
cd Serveur
npm test -- --runInBand
```

Résultat attendu: tous les tests passent.

## Notes

- Cette PR est focalisée Turn/Timeout.
- Le reste des changements transport/lobby/ui peut être livré dans les PR suivantes.
