# Acceptance status

| Критерий первого этапа | Статус | Доказательство |
| --- | --- | --- |
| Новое фото принимается без photo-specific кода | Реализовано, live run ожидает ключ | multipart controller test + универсальный prompt/schema |
| Vision создаёт JSON автоматически | Реализовано, контракт протестирован | Responses API request с `input_image` и strict `json_schema` |
| Композиция и высоты представлены в IR | Реализовано | surfaces, polyline paths, objects/groups, absolute Y, source assumptions |
| Одна геометрия для preview/export | Проверено | оба потребителя используют один SceneIR |
| JSON можно редактировать и пересобрать | Проверено в браузере | repeat count 10 → 3, part count 105 → 77 |
| Скачивается настоящий `.rbxlx` | Проверено на endpoint/XML | HTTP attachment, Roblox XML v4, editable models/parts |
| Spawn и камера готовы | Проверено тестами | один neutral SpawnLocation + сохранённая camera CFrame |
| Стоимость и время каждого заказа | Реализовано | order_id, token usage, cost, vision/compile/total ms + structured log |
| Никаких model-generated scripts | Проверено | exporter test запрещает Script/LocalScript/ModuleScript |

## Оставшийся приёмочный шаг

В окружении проверки не было `OPENAI_API_KEY`, поэтому нельзя честно зафиксировать реальную цену, latency и качество реконструкции нового пользовательского фото. После добавления ключа нужно выполнить один UI-заказ, открыть скачанный файл в Roblox Studio и сохранить полученные metrics как baseline.
