FROM python:3.9-bookworm
ENV WORKDIR=/usr/src/convert_api
WORKDIR ${WORKDIR}
COPY . .
RUN apt-get update -y && apt-get install -y \
      python3-dev \
      build-essential \
      lsof \
      openssl && \
    python3 -m venv env && \
    ${WORKDIR}/env/bin/python -m pip install --no-cache-dir -r requirements.txt
EXPOSE 1234
