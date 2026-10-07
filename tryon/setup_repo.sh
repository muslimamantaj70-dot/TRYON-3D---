#!/usr/bin/env bash
# TryOn: 5-зертханалық жұмыс үшін жергілікті Git репозиторийін құрады.
# Іске қосу (Git Bash / Linux / macOS): ол үшін алдымен бір рет:
#   git config --global user.name  "Аты Жөні"
#   git config --global user.email "email@example.com"
# содан кейін, осы папканың ішінде:  bash setup_repo.sh
set -e

if ! command -v git >/dev/null 2>&1; then echo "Git табылмады. https://git-scm.com сайтынан орнатыңыз."; exit 1; fi
if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
  echo "Алдымен Git-ке атыңызды және email-ыңызды көрсетіңіз:"
  echo '  git config --global user.name  "Аты Жөні"'
  echo '  git config --global user.email "email@example.com"'
  exit 1
fi
if [ -d .git ]; then echo "Бұл папкада .git бар. Жаңадан бастау үшін .git папкасын жойыңыз."; exit 1; fi

git init
git checkout -b main
echo "setup_repo.sh" >> .git/info/exclude

git add README.md .gitignore
git commit -m "Initial commit: add README and .gitignore"

git add docs/requirements.md docs/use-case.md
git commit -m "docs: add requirements and use cases"

git add docs/diagrams
git commit -m "docs: add BPMN and UML diagrams"

git add database
git commit -m "db: add SQL schema, seed data and tests"

git add prototype
git commit -m "prototype: add 3D mannequin demo"

# --- жеке branch және ондағы өзгеріс (Pull Request үшін) ---
git checkout -b docs/fit-logic

cat > docs/fit-logic.md << 'EOT'
# Отыру логикасы (киім дене өлшеміне қалай сәйкес келеді)

Жүйе әр киім өлшемін клиенттің дене өлшемімен аймақ бойынша салыстырады.

```
айырма = киім өлшемі − дене өлшемі        (см, шеңбер бойынша)
```

| Айырма | Үкім | Манекендегі түс |
|---|---|---|
| 2 см-ден аз | қысады (`tight`) | қызыл |
| 2 – 10 см | дәл отырады (`fit`) | жасыл |
| 10 см-ден көп | бос (`loose`) | көк |

Шектер `fit_rules` кестесінде сақталады, сондықтан кодты өзгертпей түзетуге болады (сан аймағы үшін төменгі шек 1 см).

## Қай аймақ неге салыстырылады

| Киім | Аймақ | Дене өлшемі |
|---|---|---|
| Топ (футболка, свитер) | кеуде | кеуде |
| Топ | етек | жамбас |
| Төменгі киім (шорты, шалбар) | бел | бел |
| Төменгі киім | жамбас | жамбас |
| Төменгі киім | сан | жамбас × 0,56 (шамамен) |

## Өлшем ұсыну

Ұсынылатын өлшем: ешбір аймағы «қысады» болмайтын және қоймада бар ең кіші өлшем.

**Мысал.** Клиент: кеуде 112 см, жамбас 113 см. Футболка L (кеуде 114, етек 114): кеуде +2 (дәл), етек +1 (қысады), сондықтан жалпы үкім «қысады». XL (кеуде 122, етек 122): +10 және +9, екеуі де «дәл», сондықтан XL ұсынылады.

## Қайда жүзеге асқан

- `database/schema.sql`: `fit_rules` кестесі, `v_fit_zones`, `v_size_verdict`, `v_recommended_size` view-лері;
- `prototype/mannequin.html`: манекенде сол шектермен түстер көрсетіледі.
EOT
git add docs/fit-logic.md
git commit -m "docs: describe fit logic and thresholds"

printf '\n## Құжаттар\n\n- [Отыру логикасы](docs/fit-logic.md)\n' >> README.md
git add README.md
git commit -m "docs: link fit logic from README"

git checkout main
echo
echo "================ Дайын ================"
git log --oneline --graph --all
echo
echo "Тармақтар:"; git branch
