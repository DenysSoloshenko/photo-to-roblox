# SceneFoundry — photo to editable Roblox map

Первый сквозной прототип сервиса, который превращает фотографию реальной локации в редактируемую Roblox-карту:

`photo → OpenAI vision → SceneSpec JSON → deterministic compiler → SceneIR → Three.js preview / .rbxlx`

Пользовательский JSON не подготавливается вручную: production-сценарий получает его как strict structured output от vision-модели. Три JSON-файла в `examples/` используются только для разработки и автоматических тестов.

## Что уже работает

- загрузка JPEG, PNG или WebP до 10 MB;
- vision-анализ через OpenAI Responses API с изображением в Base64 data URL;
- компактный `SceneSpec 1.0` с поверхностями, ломаными дорожками, объектами, повторяемыми группами, точкой появления и камерой;
- серверная валидация диапазонов, semantic ID, ссылок, позиции spawn и лимитов сцены с точными JSON-путями ошибок;
- детерминированная сборка: одинаковые `SceneSpec + seed + component_version` дают одинаковую геометрию;
- единый `SceneIR` для интерактивного Three.js-превью и Roblox-экспорта;
- настоящий XML place-файл `.rbxlx` с редактируемыми `Model`, `Part`, `SpawnLocation`, камерой и освещением;
- время vision, сборки и всего заказа, token usage, расчётная стоимость API и `order_id` в ответе; успешный заказ также пишется структурированным событием `scene_order_completed` в Rails log;
- безопасная сборка без генерации/исполнения кода моделью, скриптов Roblox и внешних asset ID.

## Быстрый старт

Нужны Ruby 3.3.4, Bundler, Node.js 22+ и npm.

```bash
cp .env.example .env
# впишите OPENAI_API_KEY в .env
bin/setup --skip-server
bin/dev
```

Откройте `http://127.0.0.1:5173`. `bin/dev` запускает Rails на `3000`, Vite на `5173` и читает локальный `.env`; уже заданные переменные окружения имеют приоритет.

Без ключа UI честно блокирует загрузку фото. Кнопка development-примера остаётся доступной только в `development`/`test` и не выдаётся за результат распознавания.

## Архитектура

1. `POST /api/v1/scenes/analyze` проверяет файл и отправляет фото vision-модели.
2. Модель обязана вернуть структуру из `config/schema/scene_spec.schema.json`. Схема ограничена поддерживаемым Structured Outputs подмножеством JSON Schema; числовые диапазоны и межобъектные правила дополнительно проверяет `Scene::Validator`.
3. `Scene::Compiler` раскрывает только зарегистрированные компоненты (`tree`, `bush`, `rock`, `bench`, `fence`, `building`) в плоский, переносимый `SceneIR`.
4. Seed каждого semantic object выводится из глобального seed, semantic ID и версии библиотеки. Изменение одного объекта не перетасовывает остальные.
5. React/Three.js отображает `SceneIR`. `Roblox::Exporter` получает тот же `SceneIR`, группирует части по semantic ID и сериализует Roblox XML place.

Оси зафиксированы как `Y up`, `-Z forward`; размеры указаны в studs. Невидимые области описываются в `source.assumptions`, а масштаб — через `source.scale_confidence`.

## API

| Метод | Endpoint | Назначение |
| --- | --- | --- |
| `GET` | `/api/v1/status` | готовность vision, модель, версия компонентов |
| `GET` | `/api/v1/scenes/schema` | strict-generation JSON Schema |
| `POST` | `/api/v1/scenes/analyze` | multipart `photo` + необязательный `hint` → SceneSpec, SceneIR, metrics |
| `POST` | `/api/v1/scenes/compile` | изменённый `scene_spec` → SceneIR |
| `POST` | `/api/v1/scenes/export` | изменённый `scene_spec` → `.rbxlx` |

Успешный анализ возвращает, среди прочего:

```json
{
  "metrics": {
    "order_id": "request-id",
    "vision_model": "gpt-5.6-terra",
    "vision_ms": 0,
    "compile_ms": 0,
    "total_ms": 0,
    "input_tokens": 0,
    "cached_input_tokens": 0,
    "output_tokens": 0,
    "api_cost_usd": 0
  }
}
```

Стоимость вычисляется из фактического token usage ответа. Тарифы в `Vision::SceneAnalyzer` проверены 2026-09-10; для неизвестной модели стоимость возвращается как `null`, а не угадывается.

## Детерминизм и ограничения

- Лимиты по умолчанию: 1 500 частей и 120 000 оценочных треугольников; expansion повторяемых групп проверяется заранее.
- Spawn запрещён в воде и внутри зданий; semantic ID уникальны, ссылки на поверхность/путь обязаны существовать.
- Одна фотография не даёт истинную глубину или скрытую геометрию. Прототип сохраняет узнаваемую композицию и явно отмечает предположения, но не обещает фотограмметрическую точность.
- Геометрия первого этапа собрана из Roblox primitives. Текстуры, MeshPart, Terrain voxels и multiplayer/job persistence оставлены за следующим этапом.
- API-цена является расчётной по usage и прайсу, а не биллинговой квитанцией.

## Проверка

```bash
bin/verify
bundle exec rails scenes:generate
```

`bin/verify` запускает Rails-тесты, TypeScript typecheck, production build и `git diff --check`. Генератор создаёт три контрольных файла в `generated_maps/` и записывает фактические локальные времена/размеры в `generated_maps/generation_metrics.json`.

Последняя проверка этого коммита:

- Rails: 15 tests, 68 assertions, 0 failures;
- frontend: TypeScript typecheck и Vite production build — успешно;
- browser E2E: сцена появилась в WebGL, изменение repeat count уменьшило карту со 105 до 77 частей, export endpoint отдал `.rbxlx`;
- `.rbxlx`: XML разбирается, число частей совпадает с SceneIR, есть ровно один SpawnLocation, scripts отсутствуют;
- контрольная генерация: coast 70 parts / 108.52 ms, courtyard 110 / 121.55 ms, park 105 / 129.51 ms.

Live vision-вызов в текущем окружении не выполнялся: `OPENAI_API_KEY` отсутствовал. Контракт Responses API покрыт fake-transport тестом, а multipart upload → analyzer → validator → compiler — интеграционным тестом. Для полного приёмочного теста добавьте ключ и загрузите новое фото через UI.

## Основные файлы

- `config/schema/scene_spec.schema.json` — контракт структурированного ответа;
- `app/services/vision/scene_analyzer.rb` — vision request и метрики;
- `app/services/scene/validator.rb` — семантическая и budget-валидация;
- `app/services/scene/compiler.rb` — детерминированная сборка;
- `app/services/scene/component_registry.rb` — библиотека компонентов;
- `app/services/roblox/exporter.rb` — экспорт `.rbxlx`;
- `frontend/src/App.tsx` и `frontend/src/SceneViewer.tsx` — пользовательский сценарий и 3D-превью.
