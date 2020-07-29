#!env/bin/python
# coding: utf-8

"""
Модуль с реализацией методов сервиса.
Большая часть сервиса обычно здесь.
Также, обычно здесь же и методы для ошибок, т.к. нигде кроме как здесь и в app они не нужны.
"""

import json
# noinspection PyUnresolvedReferences
import importlib

from flask import current_app as app


CURRENCY_CODES = ('RUB', 'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'UAH')
MINIMAL_AMOUNTS = {
    'RUB': 1,
    'USD': 2,
    'EUR': 3,
    'GBP': 4,
    'JPY': 5,
    'CNY': 6,
    'UAH': 7
}


def convert_currency(args):
    """
    Конвертировать одну валюту в другую
    """

    import requests

    from_arg = args.get('from', None)
    to_arg = args.get('to', None)
    amount = args.get('amount', None)

    if from_arg is None \
            or to_arg is None \
            or amount is None:
        return {}

    if not isinstance(amount, int):
        return {'error': f'amount must have integer type'}

    if from_arg not in CURRENCY_CODES \
            or to_arg not in CURRENCY_CODES:
        return {'error': f'Unknown currency, try one of {CURRENCY_CODES}'}

    if amount < MINIMAL_AMOUNTS[from_arg]:
        return {'error': f'Minimal amount for {from_arg} is {MINIMAL_AMOUNTS[from_arg]}, no less than that'}

    if from_arg == to_arg:
        return {'result': amount}

    # курсы валют якобы от ЦБ РФ
    request = requests.get('https://www.cbr-xml-daily.ru/daily_json.js')
    if request.ok:
        r_result = request.json()
    else:
        return {'error': 'Error connecting to data provider'}

    # чтобы посчитать курс делим value на nominal

    # чтобы пересчитать из рублей во что-то другое - amount/(курс)
    if from_arg == 'RUB':

        course = r_result['Valute'][to_arg]['Value']/r_result['Valute'][to_arg]['Nominal']
        result_amount = amount/course

    # чтобы из нерублей пересчитать в рубли - умножаем amount на курс
    elif to_arg == 'RUB':

        course = r_result['Valute'][from_arg]['Value'] / r_result['Valute'][from_arg]['Nominal']
        result_amount = amount * course

    # в любом другом случае - пересчитываем из чего-то в рубли, а из них - в другие нерубли
    else:

        course_from = r_result['Valute'][from_arg]['Value'] / r_result['Valute'][from_arg]['Nominal']
        course_to = r_result['Valute'][to_arg]['Value']/r_result['Valute'][to_arg]['Nominal']
        result_amount = (amount * course_from)/course_to

    if result_amount < MINIMAL_AMOUNTS[to_arg]:
        return {'error': f'Resulting amount less than minimal. Minimal amount for {to_arg} is {MINIMAL_AMOUNTS[to_arg]}, no less than that'}

    result = {'result': result_amount}

    return result


def returned_error(request_id, error_code, message, data=None, args=None):
    """
    Общая ошибка, для однообразности
    """
    error_text = {"jsonrpc": "2.0",
                  "error": {"code": error_code, "message": message, "data": data, "args": args}, "id": request_id
                  }
    
    app.logger.error(json.dumps(error_text, ensure_ascii=False))
    return error_text


def invalid_parameters(request_id, data=None, args=None):
    """
    Ошибка входных параметров, возникает когда в запросе неверные параметры
    """
    e_code = -12345678
    e_msg = "Неверные параметры"
    return returned_error(request_id, e_code, e_msg, data, args)


def parse_error(request_id, data=None):
    """
    Ошибка с кодом -32700, возникает когда во входном json ошибка
    """
    e_code = -32700
    e_msg = "Parse error"
    return returned_error(request_id, e_code, e_msg, data)
