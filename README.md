# asterisk-changenumber-script
Bash script for Asterisk to change number on Cisco and Yealink desktop phones

Допустим есть кол центр, в нем работают операторы. У каждого оператора свой номер телефона который выдан ему при поступлении на работу.
Если опрераторы перемещаются по офисе, меняют свои рабочие места. То им нужно менять номер телефона, чтобы не пропадала статистика. 

Исходные данные:
* Кол центр на голом Asterisk
* Аппаратные телефоны Cisco SPA303 и Yealink T20 и T21
 
У этого решения есть минусы:

На машине где работает Asterisk, должен находится DHCP и TFTP сервер, хотя по идее эти сервисы можно и нужно перенести на другой сервер (ВМ). А к каталогу TFTP настроить доступ с Asterisk сервера по NFS.
Если номер который вводит оператор во время запуска скрипта активен на другом телефоне, то есть по нему ведется разговор, смена номера на служебный [60X] в таком случае произойдет только после завершения разговора на этом телефоне. Незнаю почему так, когда трубка ложится произойдет перезагрузка.
Периодически телефоны Cisco теряют регистрацию на Asterisk, из за чего скрипт по смене внутреннего номера может не запускаться, так как Asterisk не видит активность телефона из за потерянной регистрации. Есть специальная функция "Present" может перерегистрировать телефон пример использования которой можно увидеть на FreePBX или на профильных форумах.
 
Как использовать, вставляем в свой диалплан код вызова нашего скрипта: 

exten => _557XXX/_[126]XX,1,Answer()
        same => n,PauseQueueMember(,SIP/${CALLERID(num)});
        same => n,AGI(confgen2al.sh,${CHANNEL(uri)},${EXTEN:3},${CALLERID(num)})
        same => n,Hangup()

Описание кода вызова:
557 - если набрать 557, будет инициирован процесс смены активного номера на аппаратном телефоне
XXX - номер оператора который  заступил на смену
PauseQueueMember - приостанавливаем прием звонков на номер который активируются, чтобы потом по кнопке DND включить прием звонков.
AGI(confgen.sh) - Вызываем  bash скрипт по смене номера
Hangup - ложим трубку


Далее создаем скрипт, допустим /usr/bin/confgen.sh или /opt/confgen.sh со следующим содержимым:   

#!/bin/bash

CALLERIP=$1 
CHOSENNUM=$2
CALLERNUM=$3

# Проверка IP-адреса звонящего
IP=$(echo "$CALLERIP" | grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
echo "Выбран IP адрес - $IP" >> /var/log/debugast.log

# Получение IP-адреса активного пира
IP2=$(asterisk -rx "sip show peers" | grep "$CHOSENNUM" | grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}")

# Получение MAC-адресов звонящего и активного пира
YEALINKMAC=$(arp -en | grep "$IP" | grep -Eo '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | sed 's/://g')
CISCOMAC=$(arp -en | grep "$IP" | grep -Eo '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')

YEALINKMAC2=$(arp -en | grep "$IP2" | grep -Eo '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | sed 's/://g')
CISCOMAC2=$(arp -en | grep "$IP2" | grep -Eo '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')

# Получение пароля
PASSWD=$(awk -v num="$CHOSENNUM" '$0 ~ num {getline; print substr($2, 8)}' /etc/asterisk/sip.conf)

# Получение модели телефона
chosemodel=$(asterisk -rx "sip show peer $CHOSENNUM" | grep -Eo "Yealink|Cisco" | head -1)
callermodel=$(asterisk -rx "sip show peer $CALLERNUM" | grep -Eo "Yealink|Cisco" | head -1)

# Проверка активности номера
status1=$(asterisk -rx "sip show peers" | grep "$CHOSENNUM" | grep -Eo "OK")

# Функция для конфигурирования Yealink
changenumberyealink() {
    local mac="$1"
    local num="$2"
    local passwd="$3"
    local ip="$4"
    
    cfg_file="/var/lib/tftpboot/${mac}.cfg"
    cat > "$cfg_file" <<EOF
#!version:1.0.0.1
account.1.enable = 1
account.1.auth_name = $num
account.1.user_name = $num
account.1.password = $passwd
account.1.sip_server.1.address = 192.168.0.252
features.dnd.allow = 1
features.dnd.on_code = *75 
features.dnd.off_code = *76
linekey.2.type = 5
local_time.time_zone = +6
local_time.time_zone_name = Almaty
EOF

    curl -s "http://$ip/cgi-bin/ConfigManApp.com?key=Reboot" -u admin:admin
}

# Функция для конфигурирования Cisco
changenumbercisco() {
    local mac="$1"
    local num="$2"
    local passwd="$3"
    local ip="$4"
    
    cfg_file="/var/lib/tftpboot/spa303_${mac}.cfg"
    cat > "$cfg_file" <<EOF
<flat-profile>
    <User_ID_1_>$num</User_ID_1_>
    <Password_1_>$passwd</Password_1_>
</flat-profile>
EOF

    curl -s "http://$ip/admin/reboot"
}

####### Основная логика #######

if [ -n "$PASSWD" ]; then
    # Проверка активности номера на другом телефоне
    if [ "$status1" = "OK" ]; then
        # Поиск свободного номера из трех: 600, 601, 602
        for number in 600 601 602; do
            status2=$(asterisk -rx "sip show peers" | grep "$number" | grep -Eo "UNKNOWN")
            if [ "$status2" == "UNKNOWN" ]; then
                # Если найден свободный номер, берём его пароль
                PASSWD2=$(awk -v num="$number" '$0 ~ num {getline; print substr($2, 8)}' /etc/asterisk/sip.conf)
                break
            fi
        done
        
        # Конфигурирование по модели устройства
        if [ "$chosemodel" = "Yealink" ]; then
            echo "Конфигурирование Yealink с MAC $YEALINKMAC2 номером $number" >> /var/log/debugast3.log
            changenumberyealink "$YEALINKMAC2" "$number" "$PASSWD2" "$IP2"
        elif [ "$chosemodel" = "Cisco" ]; then
            echo "Конфигурирование Cisco с MAC $CISCOMAC2 номером $number" >> /var/log/debugast3.log
            changenumbercisco "$CISCOMAC2" "$number" "$PASSWD2" "$IP2"
        fi
    fi

    # Конфигурирование для звонящего
    if [ "$callermodel" = "Yealink" ]; then
        echo "Конфигурирование Yealink с MAC $YEALINKMAC номером $CHOSENNUM" >> /var/log/debugast3.log
        changenumberyealink "$YEALINKMAC" "$CHOSENNUM" "$PASSWD" "$IP"
    elif [ "$callermodel" = "Cisco" ]; then
        echo "Конфигурирование Cisco с MAC $CISCOMAC номером $CHOSENNUM" >> /var/log/debugast3.log
        changenumbercisco "$CISCOMAC" "$CHOSENNUM" "$PASSWD" "$IP"
    fi

    echo "$(date +%F\ %T) User $CALLERNUM успешно выбрал номер $CHOSENNUM" >> /var/log/confgen.log
else
    echo "$(date +%F\ %T) User $CALLERNUM выбрал несуществующий номер $CHOSENNUM" >> /var/log/confgen.log
fi

Как работает скрипт:

Веденный номер оператора проверяется на активность в Asterisk, если он уже установлен на каком либо аппарате, находим этот аппарат по IP адресу и меняем на нем номер из диапазона 600-602. Номера на 60X - это такие неиспользуемые временные номера, которые устанавливаются на телефон.
Далее проверяются модели телефонов, в зависимости от этого, запускается генерация конфигурационного файла настроек с введенным номером оператора и последующей перезагрузкой аппаратов.
после перезагрузки телефон проверяет на TFTP сервере конфиг настроек, и если он изменился, идет загрузка его в телефон.

