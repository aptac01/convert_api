FROM python:3
WORKDIR /usr/src/convert_api
COPY requirements.txt ./
RUN apt-get update -y && apt-get install -y python3-dev build-essential
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
