FROM nginx:latest
LABEL description="webeserber-image"
WORKDIR /home/nginx
CMD ["nginx", "-g", "daemon off;"]
