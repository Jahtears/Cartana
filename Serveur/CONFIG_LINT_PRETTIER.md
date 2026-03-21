# Configuration ESLint & Prettier

Documentation des configurations de linting et formatage du serveur Cartana.

## 📋 Vue d'ensemble

Ce projet utilise:

- **ESLint 10** (nouveau format) pour l'analyse statique du code
- **Prettier 3** pour le formatage automatique du code
- **EditorConfig** pour la normalisation des paramètres éditeur

## 🔧 Configuration ESLint (`eslint.config.js`)

### Profils de configuration

#### 1. **Profil général** (tous les fichiers `.js`)

- **Parser**: ECMAScript 2022, modules ES6
- **Environnement**: Node.js avec globals standards
- **Plugins**:
  - `eslint:recommended` - Règles recommandées
  - `security` - Sécurité et détection de vulnérabilités
  - `sonarjs` - Détection de code smell

#### 2. **Profil tests** (fichiers `__tests__/**/*.js`, `*.test.js`, `*.spec.js`)

- Globals Vitest activés (`test`, `describe`, `expect`, `vi`, etc.)
- `no-console` et `require-await` désactivés
- Validation des tests (`no-disabled-tests`, `no-focused-tests`)

### Règles principales

#### Variables

- ✅ `const` par défaut, pas `var`
- ⚠️ Variables inutilisées = erreur (sauf paramètres prefixés `_`)
- ✅ Prefer rest params (`...args`) et spread syntax

#### Qualité du code

- ✅ `eqeqeq`: === obligatoire
- ✅ `curly`: accolades obligatoires pour tous les blocs
- ✅ `no-eval`, `no-new-func` interdit
- ✅ `require-await`: fonctions async doivent avoir `await`

#### Console

- ⚠️ Seuls `console.warn()` et `console.error()` autorisés
- ℹ️ En tests: `no-console` désactivé

#### Sécurité

- 🔒 `security/recommended` actif
- 🔒 Complexité cognitive max = 15
- 🔒 Pas de strings dupliquées (max 5 occurrences)

## 💅 Configuration Prettier (`.prettierrc`)

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "tabWidth": 2,
  "printWidth": 100,
  "arrowParens": "always",
  "useTabs": false,
  "endOfLine": "lf"
}
```

### Paramètres

- **Indentation**: 2 espaces
- **Guillemets**: simples (`'`)
- **Virgules finales**: toutes (ES5+)
- **Largeur**: 100 caractères max
- **Fin de ligne**: LF (Unix)

## 📦 Fichiers d'ignoration

### `.eslintignore`

Dossiers/fichiers ignorés par ESLint:

- `node_modules/`
- `coverage/`
- `dist/`, `build/`
- `*.pck` (exports Godot)

### `.prettierignore`

Dossiers/fichiers ignorés par Prettier:

- `node_modules/`
- `coverage/`
- `dist/`, `build/`
- `*.pck`
- `package-lock.json`

## ⚙️ Scripts disponibles

```bash
# Linting
npm run lint              # Vérifier les erreurs ESLint
npm run lint:fix          # Corriger automatiquement

# Formatage
npm run format            # Formater tous les fichiers
npm run format:check      # Vérifier le formatage sans modifier

# Combiné (recommandé avant commit)
npm run lint:fix && npm run format
```

## 🚀 Workflow recommandé

### Avant chaque commit

```bash
# 1. Corriger les erreurs ESLint
npm run lint:fix

# 2. Formater le code
npm run format

# 3. Vérifier les tests
npm run vitest
```

### Dans VS Code

Installer l'extension "ESLint" (Microsoft) pour:

- Voir les erreurs en temps réel
- Fixer automatiquement au sauvegarde (si configuré)

Installer l'extension "Prettier" (Prettier) pour:

- Prévisualiser le formatage
- Formatter à la sauvegarde (si configuré)

## ⚠️ Notes importantes

### Async sans await

Si une fonction est `async` mais n'a pas `await`, vous devez:

1. Retirer `async` si pas nécessaire, OU
2. Ajouter un vrai `await`, OU
3. Ajouter un commentaire `_async` au paramètre (paramètre inutilisé)

```javascript
// ❌ Erreur
async function ping() {
  return 'pong';
}

// ✅ Correct
function ping() {
  return 'pong';
}

// ✅ Ou si vraiment async
async function ping() {
  await someAsyncCall();
  return 'pong';
}
```

### Variables inutilisées

Préfixez avec `_` pour ignorer:

```javascript
// ❌ Erreur
function process(data, unused) {
  return data;
}

// ✅ Correct
function process(data, _unused) {
  return data;
}
```

### Curly brackets

Toutes les instructions conditionnelles doivent avoir des accolades:

```javascript
// ❌ Erreur
if (condition) return value;

// ✅ Correct
if (condition) {
  return value;
}
```

## 📊 Résumé des changements

| Outil        | Avant              | Après                            |
| ------------ | ------------------ | -------------------------------- |
| ESLint       | .eslintrc.cjs (V8) | eslint.config.js (V10)           |
| Règles       | 2 règles           | 25+ règles                       |
| Prettier     | ✓                  | ✓ Inchangé & amélioré            |
| EditorConfig | ✗                  | ✓ Nouveau                        |
| Scripts      | lint/vitest        | + lint:fix, format, format:check |

## 🔗 Ressources

- [ESLint 10 Documentation](https://eslint.org/)
- [Prettier Documentation](https://prettier.io/)
- [EditorConfig](https://editorconfig.org/)
- [Security Plugin](https://github.com/eslint-community/eslint-plugin-security)
- [SonarJS Plugin](https://github.com/SonarSource/eslint-plugin-sonarjs)
- [Vitest ESLint Plugin](https://github.com/vitest-dev/vitest/tree/main/packages/eslint-plugin)
