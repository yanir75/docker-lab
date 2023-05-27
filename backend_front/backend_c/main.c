#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    int opt = 1;
    char buffer[1024] = {0};

    // Create a TCP/IP socket
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    // Allow socket reuse
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR , &opt, sizeof(opt))){
        perror("setsockopt failed");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(10000);

    // Bind the socket to the port
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    // Listen for incoming connections
    if (listen(server_fd, 1) < 0) {
        perror("listen failed");
        exit(EXIT_FAILURE);
    }

    while (1) {
        // Wait for a connection
        printf("waiting for a connection\n");
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept failed");
            exit(EXIT_FAILURE);
        }

        printf("connection from %s:%d\n", inet_ntoa(address.sin_addr), ntohs(address.sin_port));

        // Receive the data in small chunks and retransmit it
        while (1) {
            memset(buffer, 0, sizeof(buffer));
            ssize_t valread = read(new_socket, buffer, sizeof(buffer));

            if (valread > 0) {
                printf("received: %s\n", buffer);

                printf("sending data back to the client\n");
                send(new_socket, buffer, strlen(buffer), 0);

                FILE *fp = fopen("logs.txt", "ab");
                if (fp) {
                    fwrite(buffer, sizeof(char), strlen(buffer), fp);
                    fclose(fp);
                    printf("Received %s\n",buffer);
                    fflush(stdout);
                }
            } else {
                printf("no data from %s:%d\n", inet_ntoa(address.sin_addr), ntohs(address.sin_port));
                break;
            }
        }

        // Clean up the connection
        close(new_socket);
    }

    return 0;
}
