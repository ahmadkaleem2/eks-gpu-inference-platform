FROM pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

WORKDIR /app

# System libraries required by OpenCV/Ultralytics
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Application dependencies
COPY requirements.txt .

RUN pip3 install --no-cache-dir -r requirements.txt

# Worker application
COPY worker.py .

CMD ["python3", "worker.py"]
