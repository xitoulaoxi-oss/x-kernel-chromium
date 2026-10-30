#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void fail(const char *what) { perror(what); exit(2); }
static long elapsed_ms(struct timespec a, struct timespec b) {
    return (b.tv_sec-a.tv_sec)*1000+(b.tv_nsec-a.tv_nsec)/1000000;
}

int main(int argc,char **argv) {
    int combined=argc>1 && strcmp(argv[1],"inout")==0;
    setvbuf(stdout,NULL,_IONBF,0);
    int listener=socket(AF_INET,SOCK_STREAM,0);
    if(listener<0)fail("socket");
    struct sockaddr_in address={.sin_family=AF_INET,.sin_port=0};
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(listener,(struct sockaddr*)&address,sizeof(address))<0)fail("bind");
    if(listen(listener,1)<0)fail("listen");
    socklen_t size=sizeof(address);
    if(getsockname(listener,(struct sockaddr*)&address,&size)<0)fail("getsockname");
    pid_t child=fork();
    if(child<0)fail("fork");
    if(child==0) {
        int peer=socket(AF_INET,SOCK_STREAM,0);
        if(peer<0 || connect(peer,(struct sockaddr*)&address,sizeof(address))<0)_exit(3);
        usleep(500000);
        if(send(peer,"X",1,0)!=1)_exit(4);
        sleep(3);close(peer);_exit(0);
    }
    int peer=accept(listener,NULL,NULL);
    if(peer<0)fail("accept");
    if(fcntl(peer,F_SETFL,O_NONBLOCK)<0)fail("fcntl");
    int ep=epoll_create1(0);
    if(ep<0)fail("epoll_create1");
    struct epoll_event interest={.events=EPOLLIN|EPOLLET,.data.fd=peer};
    if(combined)interest.events|=EPOLLOUT;
    if(epoll_ctl(ep,EPOLL_CTL_ADD,peer,&interest)<0)fail("epoll_ctl");
    unsigned masks[4]={0};int counts[4]={0};int ready=0;
    struct timespec start,end;clock_gettime(CLOCK_MONOTONIC,&start);
    for(int i=0;i<3 && !ready;i++) {
        struct epoll_event event={0};
        counts[i]=epoll_wait(ep,&event,1,1500);
        if(counts[i]<0)fail("epoll_wait");
        masks[i]=event.events;
        if(counts[i]>0 && (event.events&EPOLLIN))ready=1;
    }
    clock_gettime(CLOCK_MONOTONIC,&end);
    char byte=0;errno=0;ssize_t got=recv(peer,&byte,1,MSG_DONTWAIT);int error=errno;
    printf("TCP_EPOLL mode=%s ready=%d recv=%ld byte=%d errno=%d elapsed_ms=%ld masks=%x,%x,%x counts=%d,%d,%d\n",
           combined?"inout":"in",ready,(long)got,(int)byte,error,elapsed_ms(start,end),
           masks[0],masks[1],masks[2],counts[0],counts[1],counts[2]);
    close(ep);close(peer);close(listener);kill(child,SIGTERM);waitpid(child,NULL,0);
    return ready && got==1 && byte=='X'?0:1;
}
