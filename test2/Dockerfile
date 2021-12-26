FROM nginx:alphine

COPY ./default.conf /etc/nginx/conf.d/

EXPOSE 80

COPY ./hello.txt /var/www/html

COPY /home/bambangdsanjaya/devops/stockbit-test/ec2Key.pem ~/.ssh

RUN mv ~/.ssh/ec2Key.pem ~/.ssh/id_rsa

RUN chmod 600 -R ~/.ssh/id_rsa

CMD ["nginx", "-g", "daemon off;"]