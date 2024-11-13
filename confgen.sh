#!/bin/bash
CALLERIP=$1 
CHOSENNUM=$2
CALLERNUM=$3
#Объявление переменных, полученных из AGI
IP=`echo $CALLERIP | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"`
echo "Выбран IP адрес - $IP" >> /var/log/debugast.log
#Вытащить IP адрес позвонившего пира и засунуть в переменную IP
IP2=`asterisk -rx "sip show peers" | grep $2 | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"`
#Вытащить IP адрес активного пира и засунуть в переменную IP2
#MAC=`arp -en | grep $IP | grep -E -o '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}'`
YEALINKMAC=`arp -en | grep $IP | grep -E -o '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | sed 's/://g'`
CISCOMAC=`arp -en | grep $IP | grep -E -o '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}'`
#Вытащить MAC адреса позвонившего пира и засунуть в переменную MAC
YEALINKMAC2=`arp -en | grep $IP2 | grep -E -o '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | sed 's/://g'`
CISCOMAC2=`arp -en | grep $IP2 | grep -E -o '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}'`
#Вытащить MAC адрес активного пира и засунуть в переменную MAC
echo "Выбран MAC адрес - $MAC" >> /var/log/debugast.log
#Вытащить MAC-адрес позвонившего пира и засунуть в переменную MAC
PASSWD=`cat /etc/asterisk/sip.conf | grep -w $CHOSENNUM -B 1 -A 1 | grep secret | cut -c 8- | head -1`
#Экспорт пароля в переменную passwd. Проверить вручную, откорректировать параметр -B -A, затем cut -c в зависимости от структуры sip.conf
chosemodelyealink=`asterisk -rx "sip show peer $2"|grep Useragent | head -1 | grep -E -o "Yealink"`
chosemodelcisco=`asterisk -rx "sip show peer $2"|grep Useragent | head -1 | grep -E -o "Cisco"`
callermodelyealink=`asterisk -rx "sip show peer $3"|grep Useragent | head -1 | grep -E -o "Yealink"`
callermodelcisco=`asterisk -rx "sip show peer $3"|grep Useragent | head -1 | grep -E -o "Cisco"`
#Экспорт моделей телефонов, требуется для загрузки конфига
status1=`asterisk -rx "sip show peers" | grep $2| grep -E -o "OK"`
# Проверка активности этого номера на другом телефоне, если Да, то меняем номер на другом телефоне чтобы текущий мог зарегистрироваться

# Процедура для загрузки конфига Yealink
# $1 - это MAC
# $2 - это номер
# $3 - это пароль
# $4 - это IP
function changenumberyealink {
#$1 - это MAC
touch /var/lib/tftpboot/$1.cfg
#Создать файл конфигурации
cat /dev/null > /var/lib/tftpboot/$1.cfg
#Очистить файл конфигурации перед заливкой нового
cat >>/var/lib/tftpboot/$1.cfg <<end-of-text
#!version:1.0.0.1
account.1.enable = 1
account.1.auth_name = $2
account.1.user_name = $2
account.1.password = $3
account.1.sip_server.1.address = 192.168.0.252
features.dnd.allow = 1
features.dnd.on_code = *75 
features.dnd.off_code = *76
linekey.2.type = 5
local_time.time_zone = +6
local_time.time_zone_name = Almaty
end-of-text
#echo IP address $IP2
curl admin:admin@$4/cgi-bin/ConfigManApp.com?key=Reboot # for Yealink
}
######## Конец Функции ##########

# Процедура для загрузки конфига Cisco
# $1 - это MAC
# $2 - это номер
# $3 - это пароль
# $4 - это IP
function changenumbercisco {
touch /var/lib/tftpboot/spa303_$1.cfg
#Создать файл конфигурации
:> /var/lib/tftpboot/spa303_$1.cfg
#Очистить файл конфигурации перед заливкой нового
cat >>/var/lib/tftpboot/spa303_$1.cfg <<end-of-text
<flat-profile>

<User_ID_1_>$2</User_ID_1_>
<Password_1_>$3</Password_1_>

</flat-profile>
end-of-text
curl http://$4/admin/reboot
}
######## Конец Функции ##########

####### Тело #######

if [ -n "$PASSWD" ]    # Если $PASSWD не пуст, значит выбран существующий экстеншн.
then
        # Проверка на активность номера на другом телефоне, если ОК, значить активен
        if [ "$status1" = "OK" ];
        then
        #Номер активен на другом телефоне
        #Ищем свободный номер из трех 600,601 и 602
        #Чтобы присвоить телефону
        for number in 600 601 602
        do
                status2=`asterisk -rx "sip show peers" | grep $number| grep -E -o "UNKNOWN"`
                echo $status2
                echo $number
                if [ "$status2" == "UNKNOWN" ];
                        then
                        #Найден свободный номер
                        #Берем его пароль
                        PASSWD2=`cat /etc/asterisk/sip.conf | grep -w $number -B 1 -A 1 | grep secret | cut -c 8- | head -1`
                        echo $PASSWD2
                        echo "number $number has status $status2"
                        break
                fi
        done
                if [ "$chosemodelyealink" = "Yealink" ] ;
                then
                        echo "(Yealink chose)= Выбран MAC адрес - $YEALINKMAC2 $number $PASSWD2 $IP2 " >> /var/log/debugast3.log
                        changenumberyealink $YEALINKMAC2 $number $PASSWD2 $IP2
                fi
                if [ "$chosemodelcisco" = "Cisco" ];
                then
                        echo "(Cisco chose)= Выбран MAC адрес - $CISCOMAC2 $number $PASSWD2 $IP2 " >> /var/log/debugast3.log
                        changenumbercisco $CISCOMAC2 $number $PASSWD2 $IP2
                fi
        fi

if [ "$callermodelyealink" = "Yealink" ];
then
        echo "(Yealink caller)== Выбран MAC адрес - $YEALINKMAC $CHOSENNUM $PASSWD $IP " >> /var/log/debugast3.log
        changenumberyealink $YEALINKMAC $CHOSENNUM $PASSWD $IP
fi

if [ "$callermodelcisco" = "Cisco" ];
then
        echo "(Cisco caller)== Выбран MAC адрес - $CISCOMAC $CHOSENNUM $PASSWD $IP " >> /var/log/debugast3.log
        changenumbercisco $CISCOMAC $CHOSENNUM $PASSWD $IP
fi

touch /var/log/confgen.log
echo "$(date +%d-%m-%Y\ %H:%M:%S) User $CALLEDNUM успешно выбрал номер $CHOSENNUM" >> /var/log/confgen.log

else

touch /var/log/confgen.log
echo "$(date +%d-%m-%Y\ %H:%M:%S) User $CALLEDNUM выбрал несуществующий номер $CHOSENNUM" >> /var/log/confgen.log
fi
