FROM node:20

# コンテナ内の作業ディレクトリを作成
WORKDIR /usr/src/app

# package.json をコピーして依存関係をインストール
COPY package*.json ./
RUN apt-get update && apt-get install -y python3 make g++ cmake zlib1g-dev && npm install --omit=dev

# ソースコードをコピー
COPY . .

# 環境変数のデフォルト設定
ENV LISTEN_HOST=0.0.0.0
ENV LISTEN_PORT=19132
ENV DEST_HOST=10.43.91.112
ENV DEST_PORT=19132

# 待ち受けポート
EXPOSE 19132/udp

# アプリケーションの起動
CMD ["npm", "start"]
