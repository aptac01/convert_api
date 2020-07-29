#!env/bin/python
# coding: utf-8

"""
Модуль основного приложения, который паралелится через uwsgi
"""

import os
import datetime
import logging
from logging.handlers import RotatingFileHandler
from flask import Flask, jsonify, abort, Request, redirect, make_response, request, send_from_directory
from flask_httpauth import HTTPBasicAuth
from werkzeug.security import generate_password_hash, check_password_hash
from methods import invalid_parameters, parse_error, convert_currency

# --------------- flask      ---------------
app = Flask(__name__)

# --------------- app config ---------------
app.config.from_object(os.environ['APP_SETTINGS'])

# --------------- basic auth ---------------
auth = HTTPBasicAuth()
users = {
    "user": generate_password_hash("basic_password")
}


@auth.verify_password
def verify_password(username, password):
    """
    Проверить пароль пользователя. Метод для базовой авторизации для доступа к интерактивному парсеру документации
    """
    if username in users and \
            check_password_hash(users.get(username), password):
        return username


# --------------- logs       ---------------
LOG_PATH = os.getcwd() + '/log/'
LOG_FILENAME = f'{LOG_PATH}convert_api.log'
handler = RotatingFileHandler(LOG_FILENAME, backupCount=2, maxBytes=250000)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
handler.setLevel(logging.INFO)
app.logger.addHandler(handler)
app.logger.setLevel(logging.INFO)

now = datetime.datetime.now()
app.logger.info(f'Startup timestamp: {now}')

# --------------- app        ---------------


# noinspection PyUnusedLocal
@app.errorhandler(400)
def incorrect_request(error):
    """
    Обработать ошибку с кодом 400
    """
    return make_response(jsonify({'error': 'An incorrect request format'}), 400)


# noinspection PyUnusedLocal
@app.errorhandler(404)
def not_found(error):
    """
    Обработать ошибку с кодом 404
    """
    return make_response(jsonify({'error': 'Not found'}), 404)


@app.route('/swagger_ui', methods=['GET'])
@auth.login_required
def swagger_ui():
    """
    Редиректим на swagger_ui_slash
    """
    return redirect('/swagger_ui/')


@app.route('/swagger_ui/', methods=['GET'])
@auth.login_required
def swagger_ui_slash():
    """
    Показать содержимое docs.yaml в удобном графическом интерфейсе
    """
    return send_from_directory('swagger_ui', 'index.html')


@app.route('/swagger_ui/<file>', methods=['GET'])
@auth.login_required
def swagger_ui_files(file):
    """
    Скрипты для swaggerUI
    """
    return send_from_directory('swagger_ui', file)


@app.route('/docs_scheme', methods=['GET'])
@auth.login_required
def swagger_ui_scheme():
    """
    Схема для swaggerUI
    """
    return send_from_directory('', 'docs.yaml')


# noinspection PyUnusedLocal
def on_json_loading_failed(self, e):
    """
    Вернуть специальную метку и описание возникшей ошибки в объекте запроса
    в случае, если не удалось спарсить json из запроса клиента
    """
    if e is not None:
        return {
            'e': e,
            'on_json_loading_failed': 1
                }


Request.on_json_loading_failed = on_json_loading_failed


# noinspection PyUnusedLocal
@app.route('/<var_route>', methods=['POST'])
def main_packet_handler(var_route):
    """
    Обработать запрос к сервису.
    """
    
    request_json = request.json
    result_batch = []

    # оборачиваем одиночный запрос в []
    if (not isinstance(request_json, list)) \
            and isinstance(request_json, dict):

        request_json = [request_json]

    for batch_elem in request_json:

        # если при парсинге json из запроса произошла ошибка - пытаемся помочь пользователю понять где она
        if 'e' in batch_elem\
           and 'on_json_loading_failed' in batch_elem:
            result_batch.append(parse_error(None, str(batch_elem['e'])))
            continue
        
        if var_route not in ('convert_currency',):
    
            abort(400)

        method_from_client = var_route
        params = batch_elem
        datetime_now = datetime.datetime.now()
        # адрес приложения
        ip0 = request.remote_addr
        # адрес пользователя
        ip1 = request.environ.get('HTTP_X_REAL_IP', request.remote_addr)
        
        app.logger.info(f'{datetime_now.strftime("%Y-%m-%dT%H:%M:%S")}: remote address: {ip0} real IP: {ip1} method: {method_from_client}')

        if method_from_client == 'convert_currency':

            result = convert_currency(params)

            result_batch.append(result)
        
        else:
            result_batch.append(invalid_parameters('no request id, due to fact that completely ' +
                                                   'different protocol is being used'))
    
    return jsonify(result_batch)


if __name__ == '__main__':
    app.run(
        host="0.0.0.0",
        port=1234,
        debug=False
    )
