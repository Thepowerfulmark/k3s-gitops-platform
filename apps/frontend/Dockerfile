FROM nginx:1.27-alpine
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY index.html /usr/share/nginx/html/index.html
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 0755 /docker-entrypoint.sh \
    && chown nginx:nginx /etc/nginx/nginx.conf.template /usr/share/nginx/html/index.html
USER nginx
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
