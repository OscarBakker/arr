# Simple Node todo app for k3d/Helm
FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]
