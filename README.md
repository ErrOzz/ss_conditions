# RU
Данные файлы предназначены для настройки маршрутизации:
* [Shadowsocks для PC](https://github.com/shadowsocks/shadowsocks-windows/releases/latest "Shadowsocks github repo") 
* [Расширения для браузера SwitchyOmega](https://chrome.google.com/webstore/detail/proxy-switchyomega/padekgcemlokbadohgkifijomclgjgif "SwitchyOmega for Google Chrome")
* [Shadowsocks для Android](https://play.google.com/store/apps/details?id=com.github.shadowsocks "Shadowsocks in Google Play")
* [Shadowlink для iOS](https://apps.apple.com/us/app/shadowlink-shadowsocks-proxy/id1439686518) (временно не автоматизировано)

Так как сценарий настройки удалённый, любые изменения в списке сценариев синхронизируются с программой на ПК или с расширением для браузера.

**Внимание: список правил для Android не обновляется автоматически, его следует актуализировать вручную!**
Нет, лёгкого пути подключения PAC файла почему-то нет. Я бы не отказался.

## Shadowsocks для PC
1. Установить Shadowsocks из официального репозитория и прописать сервер
2. В настройках удалённого PAC указать ссылку на PAC файл
3. У системного прокси сервера включить режим работы - Сценарий настройки (PAC)

Ссылка на PAC файл: https://raw.githubusercontent.com/An-Eugene/ss_conditions/main/ss_conditions.pac

## Proxy SwitchyOmega для браузера
1. Установить Shadowsocks из официального репозитория и прописать сервер
2. Установить SwitchyOmega
3. Создать новый профиль - PAC Profile
4. Указать ссылку на PAC файл в соответствующей строке
5. Сохранить изменения
6. Настроить auto switch по желанию
   1. Создать новый профиль - proxy
   2. Прописать значения SOCKS5 127.0.0.1 1080
   3. Создать новый профиль - auto switch
   4. Указать маршрутизацию по умолчанию - PAC Profile
   5. Сохранить изменения
7. Выбрать необходимый профиль (PAC или auto switch)

Ссылка на PAC файл: https://raw.githubusercontent.com/An-Eugene/ss_conditions/main/ss_conditions.pac

**Внимание:** убедитесь, что Shadowsocks работает на порту 1080! Этот порт захардкоден и в PAC файл, поэтому менять смысла нет

**Внимание №2:** профиль auto switch нужен чтобы в 2 клика перенаправить не открывающийся сайт через прокси. Для этого и создаётся профиль proxy, чтобы было на что перенаправлять трафик. ***Если нашли нужный сайт, заблокированный в России - отправьте его мне, чтобы я добавил его в список***

**Внимание №3:** если вы используете удалённый PAC в расширении, то его не обязательно настраивать в самом Shadowsocks. В этом случае системный прокси-сервер можно поставить на "отключён". Однако, если вы планируете через auto switch делать свою маршрутизацию и у вас уже указан PAC файл в ShadowSocks - настройка PAC профиля в SwitchyOmega всё ещё обязательна.

## Shadowsocks для Android
1. Установить Shadowsocks из Google Play и прописать сервер
2. В настройках сервера указать маршрут - Пользовательские правила
3. Зайти в пользовательские правила -> добавить правило -> URL конфигурации и указать ссылку на ACL файл

Ссылка на ACL файл: https://raw.githubusercontent.com/An-Eugene/ss_conditions/main/ss_conditions.acl

## Shadowlink для iOS
1. Установить Shadowlink из AppStore. **Отказаться от всех навязываемых подписок и пробных периодов**: нас не интересуют сервера по умолчанию, мы добавляем собственную конфигурацию
2. Прописать собственный сервер. К сожалению, в отличие от SS для ПК и Android, данное приложение требует QR код. Для этого просто загоняем ссылку вида ss://<base64_info> в генератор QR кодов на компьютере, а потом сканируем с айфона конфигурацию
3. Заходим в Proxy Rule, создаём свою конфигурацию
4. Прописываем правило FINAL -> DIRECT, остальные правила должны быть вида DOMAIN-SUFFIX.

К сожалению, в виду отсутствия девайса, нормально отладить импорт правил для устройств Apple пока не вышло. Возможно, в будущем добавлю поддержку Apple.

# EN
TODO: write description in english
