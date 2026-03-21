# Cartana Server - Code Quality Setup

## 📁 Fichiers de configuration

```
Serveur/
├── eslint.config.js          ← Configuration ESLint (nouveau format V10)
├── .prettierrc                ← Configuration Prettier
├── .editorconfig              ← Configuration éditeur normalisation
├── .eslintignore              ← Fichiers ignorés par ESLint
├── .prettierrc-ignore         ← Fichiers ignorés par Prettier
└── CONFIG_LINT_PRETTIER.md    ← Documentation détaillée
```

## 🎯 Commandes rapides

| Commande               | Effet                    |
| ---------------------- | ------------------------ |
| `npm run lint`         | Vérifier les erreurs     |
| `npm run lint:fix`     | Corriger automatiquement |
| `npm run format`       | Formater le code         |
| `npm run format:check` | Vérifier le formatage    |

## 📝 Workflow type

```bash
# Développement local
npm run lint:fix && npm run format

# Avant de commiter
npm run lint && npm run format:check && npm run vitest

# CI/CD (verification uniquement)
npm run lint
npm run format:check
npm run vitest
```

## 🔍 Points clés

✅ **ESLint V10** - Nouveau format FlatConfig
✅ **Sécurité** - Plugin security renforcé
✅ **Qualité** - Plugin sonarjs pour code smells
✅ **Tests** - Support Vitest intégré
✅ **Prettier** - Formatage cohérent
✅ **EditorConfig** - Normalisation éditeur

## ⚙️ Installation des extensions VS Code (recommandé)

```json
// extensions.json ou via marketplace
"ESLint",           // Publisher: Microsoft
"Prettier - Code formatter"  // Publisher: Prettier
"EditorConfig for VS Code"  // Publisher: EditorConfig
```

## 🚨 Validation avant chaque commit

```bash
#!/bin/bash
npm run lint:fix
npm run format
npm run vitest
```

## 📊 Statistiques

- **Règles ESLint**: 25+ avec plugins security + sonarjs
- **Fichiers contrôlés**: app, domain, game, handlers, net, shared, **tests**
- **Cible Prettier**: 85 fichiers JS/JSON/MD
- **Ignoration**: node_modules, coverage, dist, build, \*.pck

---

Pour plus de détails, consultez [CONFIG_LINT_PRETTIER.md](./CONFIG_LINT_PRETTIER.md)
