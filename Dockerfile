FROM alpine:3.22.0

RUN apk add --no-cache bash && apk add --no-cache curl && apk add --no-cache yt-dlp && apk add --no-cache jq && apk add --no-cache util-linux 

WORKDIR /app

# Copy ard-plus-dl script
COPY ard-plus-dl.sh .

# Add a script-based download alias
RUN ln -s /app/ard-plus-dl.sh /usr/bin/download && \
    chmod +x /usr/bin/download
