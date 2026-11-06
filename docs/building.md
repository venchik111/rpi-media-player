# Сборка

Сборка идёт в Docker-контейнере и работает на Linux и на Windows с Docker Desktop.
На Windows команды запускаются в Git Bash.

## Требования

- Docker
- Git
- Около 20 ГБ свободного места

## Сборка образа

```bash
git clone --recurse-submodules https://github.com/venchik111/rpi-media-player
```

```bash
cd rpi-media-player
```

```bash
scripts/docker.sh scripts/build.sh rpi4
```

Результат появится в `out/rpi4/sdcard.img`.

Для тестов нужен ещё вариант для эмулятора, результат будет в `out/qemu/`:

```bash
scripts/docker.sh scripts/build.sh qemu
```

Первая сборка занимает 1–2 часа, а при медленном доступе к GitHub дольше. Загрузки, кэш
компилятора и результаты сборки хранятся в Docker-томе `rpi-player-work`, поэтому после
правки скриптов пересборка занимает минуты.

## Что где лежит

```
buildroot/                         Buildroot (подмодуль, зафиксированная версия)
br2-external/
  configs/                         rpi4_player_defconfig и qemu_player_defconfig
  board/common/rpi-player.conf     настройки по умолчанию
  board/common/rootfs-overlay/     файлы системы: init-скрипты, player-ctl, конфиги
  board/common/busybox.fragment    дополнительные команды BusyBox
  board/rpi4/                      загрузка Pi, разметка карты, сборка образа
  board/qemu/                      дополнения для эмулятора
docker/Dockerfile                  окружение сборки и тестов
scripts/                           сборка, запуск эмуляторов, проверки
tests/                             автотесты
.github/workflows/build.yml        CI
```

## Как вносить изменения

| Что меняем | Что запускать |
|---|---|
| Скрипты и конфиги в `rootfs-overlay` | `scripts/docker.sh scripts/build.sh rpi4` |
| Набор пакетов в `configs/` | То же, а для уже собранного пакета ещё его пересборка, см. ниже |
| Опции уже собранного пакета | `scripts/docker.sh scripts/build.sh rpi4 <пакет>-reconfigure`, затем обычная сборка |

Пример для BusyBox после правки `busybox.fragment`:

```bash
scripts/docker.sh scripts/build.sh rpi4 busybox-reconfigure
```

```bash
scripts/docker.sh scripts/build.sh rpi4
```

Файлы копируются в `out/` только при запуске `build.sh` без дополнительной цели.

Если опция в `defconfig` зависит от другой опции, Buildroot молча её отбросит. Например,
`BR2_PACKAGE_KMOD_TOOLS` требует `BR2_PACKAGE_BUSYBOX_SHOW_OTHERS`.

## Медленный доступ к GitHub

Прошивка и ядро Raspberry Pi скачиваются с GitHub. Прошивка берётся частичным git-клоном,
ядро неглубоким, а такую загрузку нельзя продолжить после обрыва.

Если связь плохая, скачай архив ядра на другом устройстве. Коммит указан в
`br2-external/configs/rpi4_player_defconfig`, ссылка имеет вид
`https://codeload.github.com/raspberrypi/linux/tar.gz/<коммит>`. Сохрани файл в корне проекта
как `linux-<коммит>.tar.gz` и положи его в кэш:

```bash
scripts/docker.sh bash -c 'mkdir -p /work/dl/linux && cp linux-*.tar.gz /work/dl/linux/'
```

`build.sh` найдёт архив сам и не будет обращаться к git.

## CI

Сборка в GitHub Actions запускается только вручную, потому что полный прогон занимает около
2 часов и расходует минуты Actions:

```bash
gh workflow run build.yml --ref main
```

CI собирает оба образа с нуля, запускает все [проверки](testing.md) и сохраняет
`sdcard.img.xz` в разделе **Artifacts** запуска под именем `rpi4-sdcard`. Если образа нет,
запуск считается упавшим.
