#!/bin/bash
# author: Alex Tamilin, popovalex402@gmail.com
# help по скрипту: . ./название_этого_файла.sh --help
# путь до конфига: config_filename (↓) 
config_filename="/usr/src/convert_api/env_vars_w.ini"

help_message="
usage:
. ${BASH_SOURCE[0]} [flags] - предпочтительный вариант
${BASH_SOURCE[0]} [flags]   - возможно будет работать и так, но не тестировалось

Если поймали любой неизвестный аргумент - ничего не будет сделано
------------------------------------------------------------------------------------------------------

-a| --action     действие, их список - ниже
-r| --relog      bool(1|0), удалить существующие вторичные логи
-h| --help       если есть, будет показан этот меседж, без оглядки на остальные аргументы
------------------------------------------------------------------------------------------------------

Если флаг -r не был передан - вместо него будет использовано дефолтное значение.
Дефолтные значения флагов - в конфиге:
-r  -  DELETE_RELOG_FILES

Если не указан --action - действия не будет.

Идея использования этого скрипта состоит в том, чтобы максимально упростить 
развертывание и использование микросервисов на python написанных с использованием 
Flask и запускаемых через uwsgi путем сведения всех управляющих манипуляций к 
одному файлу, а все настройки в один конфиг. 

--action:

start    - запускает сервис через uwsgi
stop     - останавливает сервис по pid-файлу, который в папке tmp
hardstop - убивает сервис по порту, прописанному в конфиге
restart  - выполняет stop, ждёт пока освободится порт, а затем start
status   - проверяет текущий статус сервиса предполагая, что конфиг 
	 после запуска не менялся, выводит текущий хэш из гита

tests    - прогоняет тесты описанные в service_manager_lib.test_api
relog    - обрабатывает логи, название которых указано в RELOG_FILES
         (в виде регулярного выражения).
         service_manager_lib.relog
	 результаты помещает в */relogs/:
	        exceptions.log       = непойманные исключения
	        internal_errors.log  = пойманные исключения и ошибки отданные клиенту
Конфиг:

скрипт читает параметры из конфигурационного файла, имя которого записано 
 в переменной \$config_filename (в скрипте ${BASH_SOURCE[0]}). Ожидается, что он написан по таким правилам:
   1) переменные в формате:
        название_переменной=значение
        название_другой_переменной=значение
        (каждая на новой строке)
   2) значения переменных указываются без кавычек
   3) между названием переменной и знаком \"=\" может быть 0 или несколько 
 пробелов (табы и другие пробельные символы не работают, только пробелы).
 Между знаком \"=\" и значением, знаков пробела быть не может.
   4) можно писать коментарии, строка начинающаяся с символа \"#\" игнорируется
"
POSITIONAL=()

# Выводит переданный аргумент на экран и в лог-файл в качестве сообщения
log_msg() 
{
	echo $*
	echo $* >> ${nohup_out_log}
}

# список переменных из конфига делает переменными среды
# аргументы:
# первый - путь до файла с конфигом, полный или относительно текущей папки
export_env_vars() 
{
	if [ "$#" -eq 0 ]
	then
		log_msg "No filename was provided, can't set env vars, exiting without changes"
		return 
	fi
	# имя файла, которое передано в аргументе
	filename=$1

	# достаем содержимое файла
	vars=$(<$filename)

	# убираем лишние пробелы, если не убрать - работать не будет
	vars=$(echo "$vars" | sed 's/ //g' )
	
	# убираем все строки начинающиеся с символа "#", если не убрать - работать не будет
	vars=$(echo "$vars" | sed '/^#/ d' )
	
	#echo "$vars"
	
	# выполняем содержимое файла, 
	# после этой стороки к каждой переменной описанной в файле 
	# здесь можно обращаться как $variable
	eval "$vars"
	
	# экспортируем список переменных 
	# команда после export выдает в результате выполнения список вида
	# var1
	# var2 и т.д., каждая переменная на новой строке
	export $(echo "$vars"  | cut -d= -f1)

}

# проверяем, есть ли файл с конфигом, если нет - сообщаем об этом и тут же выходим
if [ ! -f $config_filename ]
then
    log_msg "File $config_filename was not found, cannot continue"
	return
fi

export config_filename

# экспортируем конфиг в переменные среды
export_env_vars "$config_filename"

# создаем временные папки
create_dirs=$(cat <<'EOF'
from service_manager_lib import create_temp_dirs

create_temp_dirs()
EOF
)
${env_python_exec} -c "$create_dirs"

log_msg "----------------- Service managing operation start -----------------"

log_msg "Exported env vars from $config_filename"

log_msg "Got these arguments: $*"

timestamp=$(date +"%Y.%m.%d %H:%M:%S")
log_msg "Timestamp: $timestamp"

# если аргументов нет - ничего не делаем и выходим
if [ "$#" -eq 0 ]
then
	log_msg "No arguments provided, exiting without any changes."
	log_msg "================= Service managing operation finish ================"
return
fi

# Формирует конфиг uwsgi из template и записывает его в файл переданный 
# в 1-м аргументе
# аргументы:
# первый - путь до файла куда записать конфиг, полный или относительно 
#	текущей папки
form_uwsgi_ini_string()
{

	if [ "$#" -eq 0 ]
	then
		log_msg "No filename was provided, can't set uwsgi config, exiting without changes"
		return 
	fi
	# имя файла, которое передано в аргументе
	filename=$1

	echo "
[uwsgi]
chdir=${uwsgi_conf_chdir}
virtualenv=${uwsgi_conf_virtualenv}
pythonpath=${uwsgi_conf_pythonpath}
module=${uwsgi_conf_module}
callable=${uwsgi_conf_callable}
processes=${uwsgi_conf_processes}
http=${uwsgi_conf_http}
master=${uwsgi_conf_master}
pidfile=${uwsgi_conf_pidfile}
vacuum=${uwsgi_conf_vacuum}
max-requests=${uwsgi_conf_max_requests}
disable-logging=${uwsgi_conf_disable_logging}
logto=${uwsgi_conf_logto}
log-maxsize=${uwsgi_conf_log_maxsize}
log-date=${uwsgi_conf_log_date}

# из-за того, как работают environment переменные, uwsgi должен 
# сам их устанавливать.
# внутренний механизм uwsgi, для каждой строки из конфига
# пишет в этот конфиг строку вида env = %строка из env_vars.ini%
for-readline = $config_filename
  env = %(_)
endfor ="  > $filename
}

# запускает сервис
start_service()
{
	cd ${api_directory}

	# формируем конфиг uwsgi
	form_uwsgi_ini_string "${uwsgi_config_file}"
	# запускаем сервис через uwsgi
	nohup $uwsgi_exec --ini "${uwsgi_config_file}" >> ${nohup_out_log} 2>>${nohup_out_log} &
	
	log_msg "Service started succesfully on ${SERVER_ADDRESS}:${SERVER_PORT}"
}

# останавливает сервис
stop_service()
{
	cd ${api_directory}
	
	# смотрим, есть ли pid файл
	# при наличии - останавливаем запущенный uWSGI через него
	# иначе - убиваем то, что работает на порту из конфига
	if [ -e ${pid_file} ]
	then
		${uwsgi_exec} --stop ${pid_file}
	else 
		kill -9 $(${lsof_command} -t -i tcp:${SERVER_PORT})
		# нужно подождать, пока не освободится порт
		log_msg "Waiting for port ${SERVER_PORT} to get free"
		while ${lsof_command} -ti:${SERVER_PORT}
		do   
			sleep 0.3s
		done
		log_msg "WARNING: Couldn't find pid file, thing working with tcp:${SERVER_PORT} was killed"
	fi
	# удаляем временные файлы prometheus_flask_exporter'a
	rm ${prometheus_multiproc_dir}/*
	
	log_msg "Service on ${SERVER_ADDRESS}:${SERVER_PORT} stopped succesfully"
}

# убивает сервис
hardstop_service()
{
	cd ${api_directory}
	
	# убиваем то, что работает на порту из конфига
	kill -9 $(${lsof_command} -t -i tcp:${SERVER_PORT})
	
	# ждём, пока не освободится порт
	log_msg "Waiting for port ${SERVER_PORT} to get free"
	while ${lsof_command} -ti:${SERVER_PORT}
	do   
		sleep 0.3s
	done
	log_msg "Thing working with tcp:${SERVER_PORT} was killed"
	
	# удаляем временные файлы prometheus_flask_exporter'a
	rm ${prometheus_multiproc_dir}/*
	
	log_msg "Service on ${SERVER_ADDRESS}:${SERVER_PORT} was hardstopped"
}

# проверяет текущее состояние сервиса
check_status()
{

	# hash текущего коммита в git
	current_version=$(git rev-parse HEAD)
	log_msg "Current hash in GIT: ${current_version}"

	# если на указанном в кофиге порту есть процесс - service_instance 
	# будет содержать pid этого процесса, иначе - будет пуста
	service_instance=$(${lsof_command} -ti:${SERVER_PORT})
	
	if [ "$service_instance" != "" ]
		then
			log_msg "${SERVICE_NAME} IS WORKING on tcp:${SERVER_PORT}"
			log_msg "Conclusion: ${SERVICE_NAME} is running in DEVELOPMENT mode"
		else
			log_msg "${SERVICE_NAME} is NOT WORKING on tcp:${SERVER_PORT}"
			log_msg "Conclusion: ${SERVICE_NAME} is NOT running at all"
		fi
	
}

# выполнить тесты
do_tests()
{
	test_proc=$(cat <<'EOF'
from service_manager_lib import test_api
test_api()
EOF
)
	${env_python_exec} -c "$test_proc"
}

# выполнить релог
do_relog()
{
	relog_proc1=$(cat <<'EOF'
from service_manager_lib import execute_relog
execute_relog(
EOF
)
	relog_proc2=$(cat <<'EOF'
)
EOF
)

	${env_python_exec} -c "$relog_proc1 $relog_del $relog_proc2"
}

help_message()
{
	echo -e "${help_message}"
}

always_do_this_on_exit()
{
	log_msg "Something went wrong, exiting after this message"
	log_msg "================= Service managing operation finish ================"
	exit 1
}
#=================================

# аргументы
action=""
relog_del=2
user_needs_help=0

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
	-h|--help|\?)
	user_needs_help=1
	shift # past argument
	;;
	-a|--action)
	action="$2"
	shift # past argument
	shift # past value
	;;
	-r|--relog)
	relog_del="$2"
	shift # past argument
	shift # past value
	;;
	*)    # unknown option
	POSITIONAL+=("$1") # save it in an array for later
	shift # past argument
	;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ "$user_needs_help" == 1 ]
then
	log_msg "Got help flag, only showing documentation and exiting"
	help_message
	log_msg "================= Service managing operation finish ================"
	return
fi

if [ "${#POSITIONAL[@]}" != 0 ]; then
	echo "Unknown args found, exiting"
	log_msg "================= Service managing operation finish ================"
	return
fi

#пока не до конца разобрался, как оно работает, нужно будет доковырять когда-нибудь
#trap always_do_this_on_exit EXIT

# выполняем action в соответствии с аргументами
if [ "$action" == "start" ] 
then
	start_service

elif [ "$action" == "stop" ] 
then
	stop_service

elif [ "$action" == "hardstop" ] 
then
	hardstop_service

elif [ "$action" == "restart" ] 
then
	stop_service
	
	# просто так остановить и запустить сервис заново нельзя, 
	# нужно подождать, пока не освободится порт
	log_msg "Waiting for port ${SERVER_PORT} to get free"
	while ${lsof_command} -ti:${SERVER_PORT}
	do   
		sleep 0.3s
	done
	
	start_service

elif [ "$action" == "status" ] 
then
	check_status
	
elif [ "$action" == "tests" ] 
then
	do_tests
	
elif [ "$action" == "relog" ] 
then
	do_relog
	
else
	log_msg "invalid action, try . ${BASH_SOURCE[0]} -h for help"
fi
	

log_msg "================= Service managing operation finish ================"
